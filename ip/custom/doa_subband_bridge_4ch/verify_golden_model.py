#!/usr/bin/env python3
"""Bit-exact reference model and structural check for doa_subband_bridge_4ch."""

from __future__ import annotations

import pathlib
import sys


def to_signed(val: int, bits: int) -> int:
    mask = (1 << bits) - 1
    val &= mask
    if val & (1 << (bits - 1)):
        return val - (1 << bits)
    return val


def to_unsigned(val: int, bits: int) -> int:
    return val & ((1 << bits) - 1)


def quantize_s26_to_s16(raw26: int, shift: int) -> int:
    """Bit-exact match to Verilog function quantize_s26_to_s16."""
    assert 0 <= shift <= 15
    ext_val = to_signed(raw26, 26)
    round_bias = 0 if shift == 0 else (1 << (shift - 1))
    shifted = (ext_val + round_bias) >> shift
    if shifted > 32767:
        shifted = 32767
    elif shifted < -32768:
        shifted = -32768
    return to_unsigned(shifted, 16)


def pack_iq52(re_s26: int, im_s26: int) -> int:
    return (to_unsigned(im_s26, 26) << 26) | to_unsigned(re_s26, 26)


def pack_channelizer_beat(lanes_re_im: list[tuple[int, int]]) -> int:
    assert len(lanes_re_im) == 8
    word = 0
    for lane, (re_v, im_v) in enumerate(lanes_re_im):
        word |= pack_iq52(re_v, im_v) << (52 * lane)
    return word


def pack_iq32_from_s26(re_s26: int, im_s26: int, shift: int) -> int:
    i16 = quantize_s26_to_s16(re_s26, shift)
    q16 = quantize_s26_to_s16(im_s26, shift)
    return (q16 << 16) | i16


def test_quantizer_numerics() -> None:
    # Unity gain check: sfix26_En24 -> sfix16_En15 with shift=9
    # +0.5 in sfix26_En24 is 0.5 * 2^24 = 8388608 -> +0.5 in sfix16_En15 = 16384 (0x4000)
    assert quantize_s26_to_s16(8388608, 9) == 0x4000
    # -0.5 in sfix26_En24 is -8388608 -> -16384 (0xC000)
    assert quantize_s26_to_s16(-8388608, 9) == 0xC000
    # Zero stays zero
    assert quantize_s26_to_s16(0, 9) == 0x0000
    # Half-LSB rounding (+256 at shift=9 rounds +1 LSB)
    assert quantize_s26_to_s16(256, 9) == 0x0001
    assert quantize_s26_to_s16(255, 9) == 0x0000
    # Positive saturation (> +1.0 in sfix26_En24, e.g. +1.5 = 25165824)
    assert quantize_s26_to_s16(25165824, 9) == 0x7FFF
    # Negative saturation (< -1.0 in sfix26_En24, e.g. -1.5 = -25165824)
    assert quantize_s26_to_s16(-25165824, 9) == 0x8000
    # Digital subband boost (shift=5 => x16 gain)
    assert quantize_s26_to_s16(8388608 >> 4, 5) == 0x4000


def test_search_and_capture_packing() -> None:
    shift = 9
    # Deterministic per-(bin, channel) signature in sfix26_En24
    def bin_ch_s26(k: int, ch: int) -> tuple[int, int]:
        re_s16 = (k * 7 + ch * 3 + 11) - 2048
        im_s16 = -(k * 5 + ch * 13 + 7) + 1024
        return (re_s16 << 9), (im_s16 << 9)

    # Build one 128-beat 4-channel SSR-8 snapshot
    ch_beats = [[0] * 128 for _ in range(4)]
    for b in range(128):
        for ch in range(4):
            lanes = [bin_ch_s26(8 * b + ln, ch) for ln in range(8)]
            ch_beats[ch][b] = pack_channelizer_beat(lanes)

    # Verify 256-beat search packing matches spectrum_power4 / candidate_peak4 contract:
    # beat s in 0..255 carries bins 4*s .. 4*s+3, word = lane*4 + ch.
    for s in range(256):
        b = s >> 1
        half = s & 1
        beat512 = 0
        for lane in range(4):
            src_lane = lane + (4 if half else 0)
            k = 8 * b + src_lane
            for ch in range(4):
                lane52 = (ch_beats[ch][b] >> (52 * src_lane)) & ((1 << 52) - 1)
                re26 = lane52 & ((1 << 26) - 1)
                im26 = (lane52 >> 26) & ((1 << 26) - 1)
                iq32 = pack_iq32_from_s26(re26, im26, shift)
                exp_re, exp_im = bin_ch_s26(k, ch)
                assert iq32 == pack_iq32_from_s26(exp_re, exp_im, shift)
                word_idx = lane * 4 + ch
                beat512 |= iq32 << (32 * word_idx)
        assert 0 <= beat512 < (1 << 512)

    # Verify 4-snapshot selected-bin packing matches doa_covariance_4ch_v4 / beam_weight_4ch
    target_bin = 514  # beat 64, lane 2 (lo half, sub_lane 2)
    assert (target_bin >> 3) == 64 and (target_bin & 7) == 2
    snaps = []
    for snap_idx in range(4):
        snap128 = 0
        for ch in range(4):
            re26, im26 = bin_ch_s26(target_bin + snap_idx, ch)
            iq32 = pack_iq32_from_s26(re26, im26, shift)
            snap128 |= iq32 << (32 * ch)
        snaps.append(snap128)
    packed512 = snaps[0] | (snaps[1] << 128) | (snaps[2] << 256) | (snaps[3] << 384)
    for lane in range(4):
        for ch in range(4):
            word_idx = lane * 4 + ch
            got_iq32 = (packed512 >> (32 * word_idx)) & 0xFFFFFFFF
            exp_re, exp_im = bin_ch_s26(target_bin + lane, ch)
            assert got_iq32 == pack_iq32_from_s26(exp_re, exp_im, shift)


def test_rtl_ports() -> None:
    rtl_path = pathlib.Path(__file__).resolve().parent / "rtl" / "doa_subband_bridge_4ch.v"
    text = rtl_path.read_text(encoding="utf-8")
    required_tokens = [
        "module doa_subband_bridge_4ch",
        "s_axis_ch0_tdata",
        "s_axis_ch3_tdata",
        "s_axis_candidate_tdata",
        "m_axis_search_tdata",
        "m_axis_capture_tdata",
        "m_axis_beam_tdata",
        "m_axis_mon_ch0_tdata",
        "m_axis_mon_ch3_tdata",
        "s_axi_ctrl_awaddr",
        "endmodule",
    ]
    for tok in required_tokens:
        if tok not in text:
            raise AssertionError(f"Missing required token '{tok}' in {rtl_path}")


if __name__ == "__main__":
    test_quantizer_numerics()
    test_search_and_capture_packing()
    test_rtl_ports()
    print("PASS doa_subband_bridge_4ch golden verification")
    sys.exit(0)
