# Algorithms, step 0 → step 7

The host side of the project: eight benches that decide the algorithms before any RTL exists. Each
benches a claim; the claims are what a user usually asks about. Sources: `stepN_*/GUIDE.md`, which is
the curated text behind every number below.

## step0 — array and scene (`step0_antenna/`)

- Uniform rectangular array, **4 elements**, spacing `ARRAY_AXIS_SPACING_M = 0.030` m (30 mm), search
  cone half-angle `ARRAY_CONE_HALF_ANGLE_DEG = 55`.
- Unambiguous band edge `f_max = c/(2d)`: **5.996 GHz** at 25 mm, **4.997 GHz** at 30 mm — above that
  the phase wraps.
- At 4 GHz the array is `dy/λ = 0.33`, `dz/λ = 0.40`: inside the grating-lobe limit, no ambiguity.
- Angle accuracy of one baseline, `σ_φ = 1/√(2K·SNR)`, `σ_θ = σ_φ·λ/(2πd)`, `K = 4096`, `d = 25 mm`,
  `fc = 4 GHz`: **0.302° at 0 dB**, **0.030° at 20 dB**.
- 30 mm rather than 50 mm is a recorded decision: 50 mm wraps inside the operating band (see
  `V07_PHASE_INTERFEROMETRY.md` §11).

## step1 — RFDC, quantisation, MTS (`step1_rfadc_mts/`)

- SQNR of the 8-bit path: **66.08 dB measured vs 66.06 dB** crest-corrected theory (74.0 dB plain,
  crest factor 7.9 dB).
- 1 ps of inter-channel skew costs **0.693°** against a formula prediction of 0.687°; the resulting
  skew budget is **0.73 ps**, which is why the clock tree (MTS) is treated as a block, not a detail.
- This is the step that says 8-bit ADC data is usable *because* the DOA chain integrates 4096
  snapshots per estimate.

## step2 — the PL datapath and fixed point (`step2_pl_ip/`)

- Phase resolution of the Q3.13 format: **7.67e−4 rad = 0.021°** — 24× margin against the 0.5°
  requirement, and the reason the CORDIC output is 16-bit.
- This step also fixes the stream shapes (512/256/192/64-bit) that the RTL must keep.

## step3 — DOA on the R5F: WPI → Bartlett → Gauss–Newton (`step3_r5_doa/`)

```
capture ─► WPI seed ─► Bartlett 3×3 grid, 4 stages ─► Gauss–Newton ─► az, el
```

- **WPI (seed).** Six baselines, one phase each, weighted least squares with weights
  `w = γ/(1−γ)` clipped to `[0.05, 100]`, `γ = |R[b,a]|²/(R[a,a]·R[b,b])`. Exact for one emitter and
  already at the CRLB at high SNR — a good seed, a poor finisher.
- **Bartlett (ML).** For one emitter the generalised likelihood ratio collapses to
  `P(u) = a(u)ᵀ R a(u)`, maximised over direction. Full search at 0.005° over ±55° × ±45° is 4·10⁸
  evaluations — impossible on an R5F at 10 Hz. So the search is **local**: four 3×3 stages at
  0.5 → 0.1 → 0.02 → 0.005°, **36 evaluations**, starting from the WPI seed.
- **Gauss–Newton (finisher).** Minimises `J = ‖(I − vvᵀ)a(θ)‖²` against the dominant eigenvector `v`
  (four power iterations, no eigendecomposition), 2×2 Hessian with a 1e−7 ridge, step clipped to
  `GNMaxStep_deg = 0.05`.
- Measured: WPI alone is **0.320°** off at 20 dB in band (+12.548/−6.933 against +12.50/−7.25);
  ML+GN is **not worse** than the seed and recovers the 0.005° grid.
- Contract: `doa_core.c` returns **0 = solved, 1 = singular**; callers must handle the singular case.

## step4 — AMC on the R5F (`step4_r5_amc/`, `firmware/amc_r5/`)

Six features, all from `amc_features()` in `amc.c`: `|C40|` (fourth-order cumulant, the BPSK/QPSK
discriminator), `C42 = mean|x|⁴ / power²`, `sigma_ap` (amplitude variation), `gamma_max` (peak of the
amplitude-ripple spectrum), `freq_std` (phase-increment spread → FSK), `spike` (spectral line →
residual carrier). Each is scaled by a class-dependent constant in `amc_model.h` (60 constants,
sha256 `62bc0ee7287bfe1f`).

| check | result |
|---|---|
| T4.1 both builds compile | `test_amc_double`, `test_amc_single` |
| T4.2 label agreement with the MATLAB model | **100.0 %** (double and single, 120 bursts) |
| T4.4 accuracy against ground truth | **72.5 %** — and *the model scores the same*, so this is the feature set's ceiling, not the firmware's |
| T4.5 tables | 60 constants, hashed in `amc_model.h` |

72.5 % is a synthetic five-class result at 0–20 dB. Never quote it as field performance.

## step5 — tracking ladder and decoys (`step5_r5_tracking/`)

- Ladder rungs `RUNGS = ("modulation", "direction", "bandwidth", "cadence")`, tolerances
  `SIGMA = {direction: 0.5, bandwidth: 0.35, cadence: 1.5}`, weights
  `WEIGHT = {modulation: 1.0, direction: 1.0, bandwidth: 1.0, cadence: 0.5}`, gates
  `GATE = {modulation: 0.5, direction: 1.5, bandwidth: 1.0, cadence: 1.2}`, label mismatch 9.0,
  `Store(rungs, retire_after=RETIRE_FRAMES)` — all in `step5_r5_tracking/py/ladder.py`.
- T5.1 rung order matters: full ladder keeps **2** tracks, direction-only keeps **1**.
- T5.2 decoy check on a repeater: **40.0 ns** delay, correlation **0.36**, flagged; a single emitter
  stays clear.
- T5.3 cost is monotone: near 0.04 < far 4.00, wide 9.85; modulation mismatch **81**.
- T5.4 lifecycle: a track survives one empty frame, the ghost retires at frame 6.
- Decoy physics lives in `scripts/radar_decoys.py` (cepstral variant included); the criterion is in
  `docs/DECOY_DISCRIMINATION.md`, gate G7a **PASS (host models only)**.

## step6 — the A53 supervisor (`step6_ps_linux/`)

`supervisor.cpp`, C++17, 37 kB binary, no dependencies beyond libstdc++. It replays the ladder and the
policy, writes a text report, and is the twin of the Python path.

| check | result |
|---|---|
| T6.1 builds | `supervisor`, 37 kB |
| T6.2 same tracks as the Python ladder | 3 and 3 |
| T6.3 the modulation rung does the work | full 3 tracks, direction-only 2 |
| T6.4 the ghost is retired | 1 retired, 1 ghost |
| T6.5 `--quiet` and the exit code | silent, exit 0, `malformed=0` |

## step7 — bring-up (`step7_board_bringup/`)

`checklist.sh` prints twelve commands in the only order that works, each tagged with the gate it
closes; `--run N` runs exactly one. Steps 1 (`make steps`) is already closed by this repository; the
rest need tools, a licence or the board. The checklist is not a test suite and does not pretend to be:
a gate closes when its log exists in `docs/evidence/`, not when the command was typed.

## What the benches prove, and what they do not

Proven on the host: the array geometry, the quantisation budget, the estimator's convergence, the
feature tables, the ladder's lifecycle, the supervisor's agreement with Python, 8/8 benches green
(`make steps`).

Not proven: anything that needs RF. There is no capture, no calibration, no chamber run, no radar, no
repeater. `G5`, `G6`, `G7b`, `G8c` are open and the answer to "does it work on the board?" is "not
measured".
