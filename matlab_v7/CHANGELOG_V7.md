# V7 realistic receiver, bounded refinement and ZU48DR HIL

V7 retains the V6.2 row-vector and `SimulationOutput` fixes and adds the pieces
needed to distinguish an ideal estimator result from an implementable receiver
design.

## Estimation and geometry

- Full ZYX yaw/pitch/roll direction-cosine matrix in source truth, error monitor
  and the navigation-frame unit-vector EKF.
- Calibrated six-baseline weighted phase-interferometry seed.
- Existing fixed 36-score local ML search followed by two bounded
  Gauss-Newton polishing steps.
- Fixed four-step power iteration instead of a general eigendecomposition on
  the selected fast path.
- Forward-hemisphere limitation remains explicit for the planar 2x2 array.

## Realistic receiver

- Actual versus calibrated element coordinates.
- Mutual coupling and estimated inverse coupling.
- Static gain/phase, RF time skew, residual drift and frame jitter.
- Common and differential phase noise, thermal noise, common AGC, DC offset,
  clipping and 14-bit ADC quantization.
- `IDEAL`, `CALIBRATED_LOS` and deliberately difficult `FIELD_STRESS` profiles.
- Separate 1000-trial realistic accuracy campaign.
- Executable multi-frequency boresight calibration for relative gain, center
  phase and time skew, including packed Q2.14 PL coefficients and a regression.

## RFSoC and HIL

- New 512-bit, four-time-sample-per-clock Vitis HLS covariance core targeting
  `xczu48dr-fsvg1517-2-e` at 128 MHz.
- Self-checking HLS C testbench requiring an exact match on all 16 covariance
  words and `TLAST`.
- Deterministic MATLAB vector generator, bit-accurate fixed-point reference,
  machine-readable manifest and separate board-capture comparison harness.
- Exact integer covariance comparison plus a 0.1-degree DOA check from the
  captured covariance.

## Documentation

- Illustrated master guide with a clickable index.
- Twelve dedicated block pages, each with a JPEG block diagram, inputs,
  outputs, algorithm, statement-by-statement code walkthrough, worked example
  and implementation checks.
- Separate HIL guide with AXI packing, PL/PS integration and pass criteria.
- Single 9000+ line code guide covering every implementation file, function,
  important source line and complete distributed source code.

## Evidence boundary

The MATLAB and independent numerical checks support plausibility. A final
ZU48DR fit/performance claim still requires the included Vitis HLS synthesis
report, Vivado place-and-route timing/utilization report, repeated RFDC MTS
startup measurements, exact board HIL capture and a calibrated far-field test.

## V07.1 wideband phase interferometry (2026-11-06)

* **Convention alignment.** `PhaseInterferometryEstimator` now forms
  `S_ba = X_b*conj(X_a)` — the product order `doa_covariance_4ch_v4` and
  `estimate_doa_from_covariance_v7.m` already use — and applies the leading
  minus of `directionYZ = -(B'WB)^-1*B'W*phi/k`, in both the fixed-point and the
  floating-point paths. The HLS block was changed to match, so its 16-word
  `m_axis` output feeds `estimate_doa_from_covariance_v7.m` unchanged; without
  the matched order every angle is mirrored. The diagnostic phase-slope fit
  carries the corresponding minus. Sign is asserted by
  `verify_phase_interferometry_2x2.m` case 3, the g++ host test and
  `scripts/phase_interf_verify.py`.
* **HLS-hazard fixes in the block.** The CORDIC normaliser is no longer a pair of
  data-dependent `while` loops (51 fixed-trip conditional steps now), and the
  phase loop is no longer `PIPELINE II=1` (which would have required six
  unrolled 16-stage 64-bit CORDIC chains inside 4.0 ns). `build_hls.tcl` now
  constrains `WIDEBAND_CLOCK_PERIOD_NS` (4.0 ns, the clock the block actually
  runs on) instead of `PL_CLOCK_PERIOD_NS` (7.8125 ns). The resource table in
  V07 §7.4 is now counted from the per-beat multiply tree instead of asserted.
* **New tools.** `ip/custom/phase_interf_4ch/tb/host_shim/` + `make
  host-kernel-check` run the production kernel and its Vitis testbench on g++;
  `gate3_ooc.tcl` + `make gate3-ooc` are the (unrun) OOC timing gate.

- `PhaseInterferometryEstimator`: per-bin cross-spectrum DOA on the four channel
  spectra, six-baseline coherence-weighted least squares, contraction to the
  +x hemisphere, automatic cluster detection, and per-cluster diagnostics
  (coherence, SNR, amplitude balance, ambiguity flag).
- The multi-frequency phase-slope fit is retained only as a reported diagnostic:
  measured 457x worse than coherent WPI for a 50 MHz emitter and 5.8x worse even
  for a 2 GHz band-filling emitter (see `V07_PHASE_INTERFEROMETRY.md`).
- `FixedPointMode` reproduces the PL exactly: Q3.17 calibrated integers, exact
  integer cross-spectrum sums, and the same 16-iteration CORDIC as
  `ip/custom/phase_interf_4ch` (`phase_from_cordic_q13`, bit-identical to the
  C++ core on 48/48 test vectors).
- `verify_phase_interferometry_2x2`: time-domain chain (IFFT, 16-bit
  quantisation, raised-cosine window, FFT), CORDIC accuracy, fixed-point parity,
  narrowband vs wideband estimator comparison, and the 50 mm ambiguity case.
- Geometry unchanged and now explicitly justified: 25 mm axes / 35.4 mm
  diagonal, unambiguous to 4.24 GHz.
