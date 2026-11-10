# Signal chain, block by block

One section per block, in the order the signal sees them. Every fact names its file. If a user asks
"what is inside X", this is the short answer; `docs/BLOCK_GUIDE.md` Part 5 has the picture.

## 1. RF Data Converter (`rfdc`) — `usp_rf_data_converter:2.6`

Configuration as written by the block-design Tcl (stage 08), quoted from the RFDC configuration:

| property | value | meaning |
|---|---|---|
| `Mixer_Type` | 2 | fine mixer |
| `Mixer_Mode` | 0 | complex-to-complex |
| `Data_Type` | 1 | I/Q output |
| `Data_Width` | 8 | **8-bit** ADC data path |
| `Decimation_Mode` | 2 | decimate by 2 → 2 GSPS complex |
| `NCO_Freq` | −3.000 GHz | shifts the 2–4 GHz band to baseband (`RF_CENTER_HZ` = 3 GHz) |
| `NCO_Phase` | 0 | — |
| `Nyquist` | 1 | zone 1 |
| `CalOpt_Mode` | 1 | background calibration |
| `PL_Clock_Freq` | 500.000 MHz | `RFDC_PL_CLOCK_HZ` |
| tiles / pairs | `00 02 10 12` | four ADC tiles, one channel each |

`Multi_Tile_Sync` (MTS) is the one RFDC setting that has **not** been verified against a board; the
`docs/evidence/2026-11-04-opfb/` MTS material and `make mts-base` exist, but treat MTS as designed,
not proven. Eight-bit ADC data is deliberate (bandwidth over dynamic range) and is why the
channelizer input is `sfix16_En15` after the repack, not wider.

## 2. `rfdc_repack4` — 4 × 128-bit → 4 × 256-bit, 250 MHz

`ip/custom/rfdc_repack4/src/rfdc_repack4.cpp`, header `rfdc_repack4.hpp`
(`ap_uint<128>` → `ap_uint<256>`).

The RFDC presents eight 128-bit lanes at 250 MHz (8 samples/clk × I/Q × 16 bit × 4 channels =
1024 bit). The repack gives each ADC channel its own 256-bit lane (8 samples × {Q[31:16], I[15:0]}),
which is what one channelizer consumes. Lane `s` carries the earliest sample in bits `[16s+15:16s]`.
`#pragma HLS INTERFACE ap_ctrl_none port=return`: free-running, one beat per clock, no `ap_start`.

## 3. `matlab_channelizer` ×4 — 1024-band PFB, transposed, 250 MHz

`ip/matlab/channelizer_hdl/` (MATLAB R2024a + HDL Coder); VLNV `openai:doa:matlab_channelizer:7.0`.

| property | value | where |
|---|---|---|
| bands | 1024 | `CHANNELIZER_NUM_BANDS` |
| taps per band | 12 → **12 288** coefficients | `CHANNELIZER_TAPS_PER_BAND` |
| stopband attenuation | 100 dB | `CHANNELIZER_STOPBAND_DB` |
| FFT normalisation | **off** (`NormalizeFFT=false`) | `CHANNELIZER_NORMALIZE=0` |
| filter structure | **transposed** | `CHANNELIZER_FILTER_STRUCTURE` |
| samples per clock | 8 (SSR-8) | `WIDEBAND_SAMPLES_PER_CLOCK` |
| bin spacing | 1.953125 MHz | `CHANNELIZER_BIN_SPACING_HZ` = 1953125 |
| output type | `sfix26_En24`, 8 lanes × 26 bit × I/Q = 416 bit | HDL Coder report |

Inside: `ChannelizerCore` (a MATLAB System block wrapping `dsphdl.Channelizer`) is `u_FilterBank`
(16 real/imag sub-filters, 12 taps each) followed by `u_FFT` (1024-point). The transposed form was
chosen over systolic because the systolic variant's FilterBank needed 63 439 LUTs and 57 670 SRLs
against 10 800 LUTs / 15 055 FFs / 176 RAMB36 / 192 DSPs, and halved the latency (351 vs 1760
cycles). Frames are 128 beats; `TLAST` marks the frame.

The generated core has **no TREADY**. `channelizer_axis_wrapper.sv` is the AXI4-Stream shell: it uses
the core's clock enable as the handshake and drives `s_axis_tready` from it. Repackaging without the
wrapper produces an IP the block design cannot wire.

## 4. `doa_subband_bridge_4ch` — hand-written Verilog, 250 MHz

`ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`, packaged by `package_ip.tcl`
(VLNV `openai:doa:doa_subband_bridge_4ch:1.0`).

Purpose: turn four 416-bit single-channel channelizer streams into the three 512-bit four-lane
streams `/doa_v7` expects, and close the candidate loop back into the hardware.

| in / out | width | rate |
|---|---|---|
| `s_axis_ch0..3` | 416 bit (8 lanes × 26 bit × 2) | 128 beats/frame |
| `m_axis_search` | 512 bit | 1024 bins = **256 beats/frame** |
| `m_axis_capture` | 512 bit | 4 snapshots/beat on `active_bin` |
| `m_axis_beam` | 512 bit | 4 snapshots/beat on `active_bin` |
| `m_axis_mon_ch0..3` | 128 bit | 8 × 16-bit samples (legacy capture hierarchies) |
| `s_axis_candidate` | 192 bit | terminated, drives closed-loop bin tracking |
| `s_axi_ctrl` | 32-bit AXI4-Lite | register file |

Internals worth quoting:

- **Quantizer**: `quantize_s26_to_s16()` — half-up rounding, symmetric 16-bit saturation, default
  `scale_shift = 9` (2⁻²⁴ · 2⁹ = 2⁻¹⁵, unity gain).
- **Search path**: a three-state FSM `SRCH_IDLE → SRCH_CAPTURE → SRCH_FETCH` fills a dual 128×512
  snapshot buffer with one coherent 128-beat snapshot and a 256-beat serializer reads it out.
- **Capture / beam**: `reg_capture_beats` (default 1024) and `reg_beam_beats` (default 64) bound each
  frame; both drop-count on overflow (`capture_drop_count`, `beam_drop_count`).
- **Back-pressure**: `s_axis_ch*_tready = aresetn` and `s_axis_candidate_tready = aresetn` — the
  bridge never stalls the channelizers; it drops and counts instead.
- **Register file** (byte addresses; 16 registers):

| addr | name | meaning |
|---|---|---|
| `0x00` | CTRL | `auto_bin`, `capture_en`, `search_en`, `beam_en`, `mon_en` |
| `0x04` | MANUAL_BIN | bin index when auto tracking is off (reset value 18) |
| `0x08` | SCALE_SHIFT | quantizer shift (reset 9) |
| `0x0C` | CAPTURE_BEATS | capture frame length (reset 1024) |
| `0x10` | BEAM_BEATS | beam frame length (reset 64) |
| `0x14` | STAT | `srch_state`, `has_auto_bin`, `last_cand_valid`, `active_bin` |
| `0x18` | CAND_BIN | last candidate bin + valid |
| `0x1C`/`0x20` | CAND_PEAK | 64-bit peak |
| `0x24`/`0x28` | CAND_AVG | 64-bit average |
| `0x2C` | SNAPSHOTS | snapshot counter |
| `0x30` | SEARCH_FRAMES | frame counter |
| `0x34` | CAPTURE_FRAMES | frame counter |
| `0x38` | CANDIDATES | candidate counter |
| `0x3C` | DROPS | `{capture_drop_count, beam_drop_count}` |

`active_bin` is the frequency bin the DOA chain integrates on: the candidate stream proposes it, the
PS can override it through `MANUAL_BIN`, and capture/beam snapshots all come from that one bin — this
is what makes the 4×4 covariance spatially coherent.

## 5. `spectrum_power4` — 512-bit → 256-bit, 125 MHz

`ip/custom/spectrum_power4/src/spectrum_power4.cpp`. Per-bin power for four lanes; `ap_ctrl_none`;
VLNV `openai:doa:spectrum_power4:2.0`. Its output feeds `candidate_peak4`, not the PS directly.

## 6. `candidate_peak4` — 256-bit → 192-bit, 125 MHz

`ip/custom/candidate_peak4/src/candidate_peak4.cpp`. Picks the strongest bins out of the spectrum
and emits a compact candidate list (bin, peak, average, valid). That list leaves `/doa_v7` as
`M_AXIS_CANDIDATE` and comes back into the bridge, which is the closed loop: peak → `active_bin` →
capture → covariance → angles.

## 7. `doa_covariance_4ch_v4` — 512-bit → 64-bit, 125 MHz

`ip/custom/doa_covariance_4ch_v4/src/doa_covariance_4ch_v4.cpp`; VLNV `openai:doa:doa_covariance_4ch_v4:7.1`;
`ap_ctrl_hs` (the PS triggers one integration frame with `ap_start`).

Accumulates the 4×4 Hermitian covariance as `S_ba = X_b · conj(X_a)`. **The product order is a
contract**: the MATLAB estimator `estimate_doa_from_covariance_v7.m` carries a leading minus that
assumes it. Reversing to `X_a · conj(X_b)` yields identical RMSE and silently mirrors every reported
angle — the failure mode `docs/evidence/2026-11-06-phase-interf/REVIEW.md` records fixing. The 16
complex accumulators are serialised onto the 64-bit output.

## 8. `beam_weight_4ch` — 512-bit → 256-bit, 125 MHz

`ip/custom/beam_weight_4ch/src/beam_weight_4ch.cpp`; VLNV `…:beam_weight_4ch:2.1`; `ap_ctrl_none`.
v2.0 used `#pragma HLS INTERFACE s_axilite port=return` (`ap_ctrl_hs`) and stalled one beat per
clock; the pragma is now `ap_ctrl_none`, with the reason in the source comment.

## 9. `phase_interf_4ch` — the V07 per-bin interferometer, 250 MHz

`ip/custom/phase_interf_4ch/src/phase_interf_core.hpp` (+ `.cpp`); VLNV
`openai:doa:phase_interf_4ch:1.0`; constrained at **4.0 ns** because it is a wideband block.

- Six cross-spectra, `S_ba = X_b · conj(X_a)`, with the baseline pairs fixed in the header:
  `kFirst = {0,0,0,1,1,2}`, `kSecond = {1,2,3,2,3,3}`.
- One **time-multiplexed** `atan2_q13()` CORDIC (vectoring, 16 iterations, 32-entry `kAtanQ30`
  table, `round(atan(2^-i)·2^30)`), producing Q3.13 radians = 0.021° LSB.
- The normaliser is 51 fixed-trip conditional steps, not the data-dependent `while` loops of the
  first draft — Vitis HLS cannot schedule a data-dependent trip count.
- Outputs: 128-bit stream (6 phases + tag + valid) and 64-bit accumulator words (16 per frame).

## 10. Clocks, resets, CDC

`clk_wiz` in the MTS base supplies the 500/250/125 MHz tree; `proc_sys_reset` per domain supplies
`rst_rf_250m_n` and `rst_doa_125m_n`. Crossings are explicit `axis_clock_converter` instances (search,
capture, beam, candidate), each with a FIFO depth and its own reset, in `config/zcu208_bd_map.tcl`.
Do not describe the CDC as "just a FIFO": the converters are the reason the DOA side can run at
125 MHz without touching the 250 MHz channelizer cadence.

## 11. What the PS reads

| interface | IP | domain | what the PS gets |
|---|---|---|---|
| `/doa_cov_fifo/S_AXI` | `axi_fifo_mm_s:4.3` | 125 MHz | one covariance frame (16 complex accumulators) |
| `/doa_beam_fifo/S_AXI` | `axi_fifo_mm_s:4.3` | 125 MHz | beam-monitor snapshots |
| `S_AXI_COV_CTRL`, `S_AXI_CANDIDATE_CTRL`, `S_AXI_BEAM_CTRL` | the three kernels | 125 MHz | `ap_start`/thresholds |
| `/doa_subband_bridge_0/s_axi_ctrl` | the bridge | 250 MHz | bin tracking, scaling, counters |

No DMA, no custom Linux driver, no interrupt path in this design. The A53 supervisor polls the FIFOs;
the R5F is driven by the PS-side software, not by an IRQ from the PL.
