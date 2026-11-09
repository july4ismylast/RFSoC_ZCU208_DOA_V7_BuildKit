# phase_interf_4ch — V07 per-bin phase interferometer

PL front end for the phase-interferometry DOA described in
[`V07_PHASE_INTERFEROMETRY.md`](../../../V07_PHASE_INTERFEROMETRY.md). It turns
four calibrated channel bins into six complex cross-spectra and six CORDIC
phases, so the PS never has to run `atan2` per bin.

VLNV: `openai:doa:phase_interf_4ch:$(IPVER_PHASE_INTERF)` (default `1.0`).

## Interface

| Port | Direction | Width | Meaning |
|---|---|---|---|
| `s_axis` | in | 512 bit | lane-major `word = lane*4 + channel`, `{Q[31:16], I[15:0]}`, 4 lanes × 4 channels per beat — identical to `doa_covariance_4ch_v4` |
| `m_axis` | out | 64 bit × 16 | per frame: `power[0..3]`, `crossReal[0..5]`, `crossImag[0..5]`, `TLAST` on word 15 — identical layout to the covariance block |
| `m_phase` | out | 128 bit × 1 | per frame: 6 × phase Q3.13 rad, `[111:96]` frame tag, bit 112 phases-valid |
| `cal0..cal3` | AXI-lite | 32 bit | per-channel complex gain, Q2.14 (`{im[31:16], re[15:0]}`) |
| `frameSamples` | AXI-lite | 16 bit | samples per channel per frame (0 → 4096) |
| `frameTag` | AXI-lite | 16 bit | echoed in `m_phase` so the PS can pair it with the search result |

## Clock domain

`ap_clk` is the **250 MHz wideband fabric clock** (`WIDEBAND_CLOCK_PERIOD_NS` =
4.0 ns): the block consumes the 1024-band channelizer's SSR-8 output, which is
in that domain, not the 125/128 MHz DOA-side domain that `PL_CLOCK_PERIOD_NS`
describes. `build_hls.tcl` constrains `create_clock -period 4.0` accordingly,
and `gate3_ooc.tcl` refuses to report a pass if the packaged IP's `ap_clk` is
not the 4.0 ns period.

## Math and sign convention

```text
A_n = exp(-j*2*pi*f*(p_n.u)/c)
S_ba = X_b * conj(X_a)  =>  phase(S_ba) = -2*pi*f*(p_b - p_a).u/c
uy = -phase(baseline 0: CH1->CH2, +y) * c / (2*pi*f*d)
uz = -phase(baseline 1: CH1->CH3, +z) * c / (2*pi*f*d)
```

The product order is deliberately `X_b*conj(X_a)` — the order
`doa_covariance_4ch_v4` uses — so `m_axis` is a drop-in replacement for that
block's output and `matlab_v7/estimate_doa_from_covariance_v7.m` consumes it
unchanged (`directionYZ = -(B'WB)^-1*B'W*phi/k`). A target at positive `uy`
gives a **negative** baseline-0 phase; dropping the minus mirrors every angle.

Baselines 2…5 — `(0,3)`, `(1,2)`, `(1,3)`, `(2,3)` — are redundant and exist so
the PS can form the same coherence-weighted six-baseline least squares as
`estimate_doa_from_covariance_v7.m`.

The sign convention is asserted three times: in the host core test (steering
phasors for az +20 deg / el -12 deg), in the HLS C-simulation testbench through
the AXI ports, and against an independent steering model in
`scripts/phase_interf_verify.py`.

## Why one CORDIC instead of six

The six phases are needed once per frame, and a frame is 4096 samples of an
~2 MS/s channelised bin — about 2 ms. A single normaliser+CORDIC datapath run six
times costs ~250 cycles (~1 µs), 0.05 % of the frame, and a fraction of the LUT of
six replicas; `PIPELINE II=1` on that loop was deliberately removed for the same
reason (at `II=1` HLS would unroll six 16-stage 64-bit adder chains into one
4.0 ns cycle). The CORDIC normaliser is written as 51 fixed-trip conditional
steps rather than two `while` loops because HLS cannot schedule a data-dependent
loop bound.

## Fixed-point formats

| Stage | Format |
|---|---|
| input sample | `int16` (Q1.15) |
| calibration | `int16` real/imag Q2.14 |
| calibrated value | `int20` Q3.17 (`>>14` rescale, as in the covariance block) |
| accumulators | `int64`; worst case 51 bits for 4096 samples (checked by the host test) |
| phase out | `int16` Q3.13 rad, CORDIC 16 iterations, ≤ 2 LSB error |

## Verification

| Check | Command | Status |
|---|---|---|
| Core (CORDIC table/accuracy, sign, accumulation, width) on g++ | `make host-check` | **PASS** |
| Production kernel + production C-sim testbench compiled and run on the host (AXI packing, record layout, `TLAST`, tag echo) | `make host-kernel-check` | **PASS** |
| HLS C-simulation, synthesis, export | `make` (needs Vitis HLS 2023.2) | **NOT RUN** |
| OOC synthesis + timing at 4.0 ns | `make gate3-ooc` (Vivado 2023.2) | **NOT RUN** |

`make host-check` compiles `src/phase_interf_core.hpp` — the same header the
kernel includes — with no Xilinx headers, so the arithmetic it proves is the
arithmetic that is synthesised.

`make host-kernel-check` goes one step further and compiles **the kernel and the
Vitis testbench unmodified** against `tb/host_shim/` (a minimal `ap_int.h`,
`hls_stream.h`, `ap_axi_sdata.h`). That executes the AXI unpack/pack paths and
the 16-word record for real. It is not `csim_design`: no scheduling, initiation
interval, latency or HLS overflow semantics — see `tb/host_shim/README.md`.

## Why phases and not only accumulators

`m_axis` alone is enough for the PS to do everything in software. `m_phase`
exists so that:

* the phase path is a fixed, testable hardware contract rather than an R5
  software routine whose precision depends on the build;
* one shared CORDIC datapath costs ~2–3 k LUT, no DSP and ~250 cycles per frame —
  cheaper than six `atan2` calls on the R5, and deterministic (the software path's
  precision depends on the build);
* a future bin-rate mode (one phase per bin) is a pipelining change inside this
  block, not a new design.
