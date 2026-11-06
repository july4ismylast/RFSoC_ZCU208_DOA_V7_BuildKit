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

## Math and sign convention

```text
S_ab = X_a * conj(X_b)  =>  phase(S_ab) = +2*pi*f*(p_b - p_a).u/c
uy = +phase(baseline 0: CH1->CH2, +y) * c / (2*pi*f*d)
uz = +phase(baseline 1: CH1->CH3, +z) * c / (2*pi*f*d)
```

Baselines 2…5 — `(0,3)`, `(1,2)`, `(1,3)`, `(2,3)` — are redundant and exist so
the PS can form the same coherence-weighted six-baseline least squares as
`estimate_doa_from_covariance_v7.m`.

The sign convention is asserted three times: in the host core test, in the HLS
C-simulation testbench, and against an independent steering model in
`scripts/phase_interf_verify.py`.

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
| HLS C-simulation, synthesis, export | `make` (needs Vitis HLS 2023.2) | **NOT RUN** |
| OOC timing at 4.0 ns | see V07 §8 G3 | **NOT RUN** |

`make host-check` compiles `src/phase_interf_core.hpp` — the same header the
kernel includes — with no Xilinx headers, so the arithmetic it proves is the
arithmetic that is synthesised.

## Why phases and not only accumulators

`m_axis` alone is enough for the PS to do everything in software. `m_phase`
exists so that:

* the phase path is a fixed, testable hardware contract rather than an R5
  software routine whose precision depends on the build;
* the six CORDICs cost ~7 k LUT and no DSP, which is cheaper than the R5 time
  for 6 `atan2` per frame at the DOA frame rate;
* a future bin-rate mode (one phase per bin) is a pipelining change inside this
  block, not a new design.
