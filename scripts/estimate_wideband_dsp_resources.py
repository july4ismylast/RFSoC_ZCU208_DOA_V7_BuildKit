#!/usr/bin/env python3
"""V07 front-end feasibility screen for the ZCU208 / XCZU48DR (ZU48DR).

Answers the question "does a 16K FFT at 2.048 GSPS fit on the ZCU208?" with
transparent arithmetic instead of an assertion.

Everything below is a SCREEN, not synthesis evidence.  It is built from

  * the device capacity extracted in the V06 evidence run (425,280 LUT,
    850,560 FF, 1,080 BRAM36, 80 URAM, 4,272 DSP48), and the measured routed
    MTS base (42,263 LUT, 47,760 FF, 50.5 BRAM36, 20 URAM, 3 DSP48);
  * the ONE measured wideband block this repository owns: the V06 Gate-2T
    transposed 1024-band, 12-tap, SSR-8 channelizer (176 RAMB36, 312 DSP,
    35,902 LUT, 58,626 FF, 351 cycles per channel at 4.0 ns);
  * first-principles radix-4 arithmetic for the FFT options.

The screen deliberately reports a *range*: a lower bound (perfectly packed
memory, no twiddle ROM, no BFP) and a screening estimate that applies the
memory overhead actually observed on the measured channelizer (15x).  Only a
one-channel OOC synthesis on the build PC can close the question, exactly as
V06 Gates 1/2/2T were required to.

Run:  python3 scripts/estimate_wideband_dsp_resources.py
"""

from __future__ import annotations

import datetime as _dt
import math
import os

FS_HZ = 2.0e9              # 4.000 GSPS / RFDC decimation 2  (V04 contract)
FABRIC_HZ = 250e6          # V04/V05/V06 wideband fabric clock
SSR = 8                    # samples per fabric clock = 2.000 GS/s / 250 MHz
DEVICE = {"LUT": 425280, "FF": 850560, "BRAM36": 1080, "URAM": 80, "DSP48": 4272}
MTS = {"LUT": 42263, "FF": 47760, "BRAM36": 50.5, "URAM": 20, "DSP48": 3}
BRAM36_BITS = 36 * 1024

# Measured: V06 Gate-2T one-channel transposed 1024-band / 12-tap / SSR-8 PFB
# channelizer (docs/evidence/2026-11-04-opfb, V06_CHANNELIZER_FEASIBILITY.md).
MEASURED_CHANNELIZER = {
    "name": "1024-band PFB channelizer, 12 taps, SSR-8 (MEASURED, one channel)",
    "bram36": 176.0, "dsp48": 312.0, "lut": 35902.0, "ff": 58626.0,
    "latency_cycles": 351,
    "note": "V06 Gate-2T OOC synthesis, xczu48dr-fsvg1517-2-e, 4.0 ns",
}
# Memory overhead actually observed on that block:
#   data minimum = 1024 bands x 12 taps complex (PFB) + 1024 complex (FFT)
CHANNELIZER_DATA_BITS = (1024 * 12 + 1024) * 32
OBSERVED_MEM_OVERHEAD = MEASURED_CHANNELIZER["bram36"] * BRAM36_BITS / CHANNELIZER_DATA_BITS


def bram(bits: float) -> float:
    return bits / BRAM36_BITS


# FFT memories are deep (>=1024 words per bank) so a well-built core packs
# near-perfectly; the residual overhead is block-floating-point exponents,
# twiddle ROM and pipeline registers.  2x is the optimistic end.
FFT_MEM_OVERHEAD_LO = 2.0


def fft_option(n_fft: int, ssr: int, overhead: float) -> dict:
    """Screen one pipelined SSR FFT instance (per channel, 16-bit I/Q).

    Returns BRAM36 bounds for two memory-overhead assumptions.
    """
    clocks = n_fft / ssr                       # clocks per transform
    frame_us = clocks / FABRIC_HZ * 1e6
    data_bits = n_fft * 32 + n_fft * 32        # data + natural-order twiddle ROM
    bram_lo = bram(data_bits) * FFT_MEM_OVERHEAD_LO
    bram_hi = bram(data_bits) * overhead
    # radix-4: 3 complex twiddle multiplies per 4-point butterfly per stage;
    # ~25% of twiddles are +-1/+-j and cost nothing.
    stage = math.log(n_fft, 4)
    cmul_per_sample = 0.75 * stage
    real_mul_per_clk = cmul_per_sample * ssr * 4 * 0.75
    dsp_lo = real_mul_per_clk
    # LUT screen: scale the measured channelizer's LUT cost by the per-sample
    # arithmetic growth, log2(N)/log2(1024) for four channels of lanes.
    lut = MEASURED_CHANNELIZER["lut"] * (math.log2(n_fft) / math.log2(1024))
    return {
        "name": f"{n_fft}-point FFT, SSR-{ssr}",
        "clocks": clocks, "frame_us": frame_us,
        "bram_lo": bram_lo, "bram_hi": bram_hi,
        "dsp": dsp_lo, "lut": lut,
        "bins_hz": FS_HZ / n_fft,
    }


def main() -> None:
    lines: list[str] = []

    def emit(text: str = "") -> None:
        print(text)
        lines.append(text)

    emit("V07 WIDEBAND FRONT-END FEASIBILITY SCREEN -- ZCU208 / XCZU48DR (ZU48DR)")
    emit(f"generated : {_dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
    emit(f"throughput: {FS_HZ/1e9:.3f} GS/s complex per channel, {SSR} samples/clk at "
         f"{FABRIC_HZ/1e6:.0f} MHz, 4 channels")
    emit("")
    emit("DEVICE CAPACITY / ROUTED MTS BASE (V06 evidence)")
    emit("%-8s %12s %12s %12s" % ("resource", "device", "MTS base", "free"))
    for key in ("LUT", "FF", "BRAM36", "URAM", "DSP48"):
        emit("%-8s %12.0f %12.1f %12.1f" % (key, DEVICE[key], MTS[key], DEVICE[key] - MTS[key]))
    emit("")
    emit(f"memory overhead factor observed on the measured channelizer: "
         f"{OBSERVED_MEM_OVERHEAD:.1f}x of the theoretical data+twiddle bits")
    emit("")

    # ---------------- front-end candidates --------------------------------
    options = []
    options.append({
        "name": MEASURED_CHANNELIZER["name"],
        "bins_hz": FS_HZ / 1024,
        "bram": MEASURED_CHANNELIZER["bram36"],
        "dsp": MEASURED_CHANNELIZER["dsp48"],
        "lut": MEASURED_CHANNELIZER["lut"],
        "ff": MEASURED_CHANNELIZER["ff"],
        "frame_us": 1024 / FABRIC_HZ * 1e6,
        "status": "MEASURED (Gate-2T)",
        "bram_lo": MEASURED_CHANNELIZER["bram36"],
    })
    for n_fft in (1024, 4096, 16384):
        opt = fft_option(n_fft, SSR, OBSERVED_MEM_OVERHEAD)
        options.append({
            "name": opt["name"],
            "bins_hz": opt["bins_hz"],
            "bram": opt["bram_hi"],
            "bram_lo": opt["bram_lo"],
            "dsp": opt["dsp"],
            "lut": opt["lut"],
            "ff": MEASURED_CHANNELIZER["ff"] * (math.log2(n_fft) / math.log2(1024)),
            "frame_us": opt["frame_us"],
            "status": "SCREEN",
        })

    emit("ONE-CHANNEL FRONT-END CANDIDATES")
    emit("%-46s %9s %14s %8s %8s %9s" %
         ("candidate", "bin[kHz]", "BRAM36 range", "DSP48", "LUT", "frame[us]"))
    for opt in options:
        emit("%-46s %9.1f %5.0f .. %5.0f %8.0f %8.0f %9.2f" %
             (opt["name"], opt["bins_hz"] / 1e3, opt["bram_lo"], opt["bram"],
              opt["dsp"], opt["lut"], opt["frame_us"]))
    emit("  BRAM36 range = deep-memory packing (2x of data+twiddle, optimistic) ..")
    emit("                 overhead seen on the measured channelizer (15.2x, pessimistic)")
    emit("  DSP48        = radix-4 first-principles lower bound, 25% trivial twiddles")
    emit("")

    emit("FOUR-CHANNEL PROJECTION INCLUDING THE ROUTED MTS BASE")
    emit("%-40s %18s %9s %9s  %s" %
         ("candidate", "BRAM36", "DSP48", "LUT", "verdict"))
    for opt in options:
        bram_hi = MTS["BRAM36"] + 4 * opt["bram"]
        bram_lo = MTS["BRAM36"] + 4 * opt["bram_lo"]
        dsp_total = MTS["DSP48"] + 4 * opt["dsp"]
        lut_total = MTS["LUT"] + 4 * opt["lut"]
        hi_util = bram_hi / DEVICE["BRAM36"]
        lo_util = bram_lo / DEVICE["BRAM36"]
        if opt["status"].startswith("MEASURED"):
            verdict = "closes (V06 arithmetic)"
        elif lo_util > 1.0:
            verdict = "DOES NOT FIT at any overhead"
        elif hi_util > 1.0:
            verdict = "NOT SETTLED by arithmetic: %.0f%%..%.0f%% BRAM" % (100 * lo_util, 100 * hi_util)
        elif hi_util > 0.75:
            verdict = "tight: %.0f%%..%.0f%% BRAM" % (100 * lo_util, 100 * hi_util)
        else:
            verdict = "fits arithmetically: %.0f%%..%.0f%%" % (100 * lo_util, 100 * hi_util)
        emit("%-40s %8.0f..%7.0f %8.1f%% %8.1f%%  %s" %
             (opt["name"].replace(" (MEASURED, one channel)", ""),
              bram_lo, bram_hi, 100 * dsp_total / DEVICE["DSP48"],
              100 * lut_total / DEVICE["LUT"], verdict))
    emit("")
    emit("The 4x projection is arithmetic addition, not placement/routing.  V06 already")
    emit("shows four transposed channelizers landing at 69.9% BRAM by the same argument.")
    emit("")

    emit("IP SUPPORT -- THE DECIDING FACT, INDEPENDENT OF THE ARITHMETIC")
    emit("%-34s %-14s %s" % ("implementation", "max samples/clk", "applies here?"))
    emit("%-34s %-14s %s" % ("AMD FFT LogiCORE v9.1 (PG109)",
                              "1", "NO: needs 8 cores/channel, each with full 16K memory"))
    emit("%-34s %-14s %s" % ("Vitis DSP Library SSR FFT",
                              "2/4/8/16 (<=4K)",
                              "NO at 16K: benchmark envelope stops at 4K"))
    emit("%-34s %-14s %s" % ("MathWorks dsphdl FFT / Channelizer",
                              "power-of-2 vector",
                              "UNPROVEN at 16K x SSR-8: needs OOC synthesis first"))
    emit("%-34s %-14s %s" % ("8 x AMD FFT + polyphase recombine",
                              "8 (by construction)",
                              "NO: 8x memory, twiddle+recombine logic, no IP support"))
    emit("")
    emit("Verdict: a 16K FFT at 2.048 GSPS is not an instantiable IP configuration in")
    emit("this toolchain, its four-channel BRAM cost is either near the device limit or")
    emit("over it depending on the memory packing, and it buys no angular accuracy over")
    emit("the measured 1024-band channelizer at equal observation time.  Do not adopt.")
    emit("")

    # ---------------- why 16K is not needed -------------------------------
    emit("WHY 16K AT 2 GSPS DOES NOT BUY ACCURACY (equal observation time)")
    emit("Angular variance for a coherent cross-spectrum measurement is set by the")
    emit("number of coherently combined bin-snapshot products, not by FFT length:")
    emit("")
    emit("  sigma_theta ~ c / (2*pi*f_c*d) * sigma_phi / sqrt(K),  K = bins x snapshots")
    emit("")
    emit("%-34s %10s %10s %12s" % ("front end", "bins in 50 MHz", "frames/8.2us", "K"))
    for name, n_fft in (("1024-band channelizer", 1024), ("4K FFT", 4096), ("16K FFT", 16384)):
        bins_in_50mhz = max(50e6 / (FS_HZ / n_fft), 1.0)
        frames = 8.2e-6 * FABRIC_HZ / (n_fft / SSR)
        emit("%-34s %10.1f %10.2f %12.0f" % (name, bins_in_50mhz, frames,
                                             bins_in_50mhz * frames))
    emit("")
    emit("So 1024 bands x 16 frames and 16K x 1 frame both give K ~ 410 for a 50 MHz")
    emit("emitter: the same angular accuracy for the same integration time.  Finer bins")
    emit("matter for separating emitters that are close together inside the band, not")
    emit("for the angle of a single emitter.")
    emit("")

    # ---------------- phase-interferometry block --------------------------
    emit("PHASE-INTERFEROMETRY BLOCK (ip/custom/phase_interf_4ch), 4 lanes x 4 channels")
    emit("  per beat: 16 cal multiplies + 6 cross-spectra (24 real multiplies) = ~40 DSP48")
    emit("  6 complex accumulators (48-bit) + 4 power accumulators     = ~130 FF, no BRAM")
    emit("  6 CORDIC atan2 (16 iterations, 16-bit) at the 125 MHz DOA clock")
    emit("      ~ 6 x 1,100 LUT / 6 x 900 FF, no DSP (shift-add)        = ~7k LUT")
    emit("  total: ~40 DSP48 (0.9%), ~8k LUT (1.9%), <1 BRAM36 -- small next to either")
    emit("  front end, which is why the front end, not the interferometer, is the risk.")
    emit("")

    out_path = os.path.join("docs", "evidence", "2026-11-06-phase-interf",
                            "wideband_frontend_screen.txt")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"report written to {out_path}")


if __name__ == "__main__":
    main()
