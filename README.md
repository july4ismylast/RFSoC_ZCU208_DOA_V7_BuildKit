# ZCU208 DOA V7 FPGA Build Kit

![ZCU208 DOA V7 architecture](docs/diagrams/zcu208-overall.jpg)

This is the corrected ZCU208 implementation draft for the V7 2×2 DOA
simulation. It is a restartable build system and a hardware/software partition,
not a claim that a bitstream was generated in this environment.

The critical design decisions are:

- use a verified **ZCU208** RFDC/clock/MTS base project; never port a different
  RFSoC board by changing only `PART`;
- keep search and triggered covariance on independent streams so a completed
  covariance frame cannot stop continuous detection;
- process four complex samples per clock on all custom PL blocks;
- compute calibrated four-channel/six-baseline cross-spectra in PL, per
  frequency bin, and extract the six baseline phases in a small CORDIC block
  (V07 phase interferometry — see
  [V07_PHASE_INTERFEROMETRY.md](V07_PHASE_INTERFEROMETRY.md));
- initially run V7 WPI, bounded local ML/Gauss–Newton, and the unit-vector EKF
  on the R5, with the A53 supervising calibration, logging, and networking;
- require C simulation, BD validation, timing closure, exact covariance HIL,
  and angle acceptance as separate gates.

## Start here

```bash
make help
make status
# Vivado/Vitis are locked to 2023.2 (V00): every IP VLNV lives in
# config/ip_versions.tcl and step00 proves it against your installed catalog.
make step00_preflight \
  BASE_XPR=/absolute/path/verified_zcu208_base.xpr
```

Vivado-first flow: the production base is the pinned Xilinx RFSoC-MTS
ZCU208 design. See [V03_MTS_BASE_2023P2.md](V03_MTS_BASE_2023P2.md) for how
that 2022.1.2 base is brought under the 2023.2 lock before step07, and
[V00_V01_V02_CHANGES.md](V00_V01_V02_CHANGES.md) for the version-pinning
changes (branch `vivado-2023.2-v00-v01`).

Run or debug any stage directly:

```bash
make step02_hls_covariance
make step10_synth
make rebuild STEP=step10_synth
make clean-stage STEP=step10_synth
make -n step10_synth
```

The production integration stage intentionally stops until
[`config/zcu208_bd_map.tcl`](config/zcu208_bd_map.tcl) is mapped to the actual
RFDC base-design pin names. For a structural-only BD check, use
`INTEGRATION_MODE=external_ports`; that result is not deployable.

## Documentation

- [Wideband phase interferometry: adopt / correct / reject](V07_PHASE_INTERFEROMETRY.md)
- [Implementation and algorithm guide](ZCU208_IMPLEMENTATION_GUIDE.md)
- [Every build stage and recovery command](BUILD_STAGES.md)
- [File-by-file and code walkthrough](FILE_AND_CODE_GUIDE.md)
- [Primary-source research and adoption decisions](RESEARCH_REFERENCES.md)
- [First-draft audit and direct comparison](AUDIT_AND_COMPARISON.md)
- [What was and was not validated here](VALIDATION_REPORT.md)
- [Original draft source matrix](SOURCE_MATRIX.md)

## Why the DOA estimator is phase interferometry, not phase slope

The wideband path measures the angle from the *carrier* phase of the summed
cross-spectrum, not from a phase-versus-frequency slope. `scripts/phase_interf_verify.py`
(committed report under `docs/evidence/2026-11-06-phase-interf/`) measures
0.22° RMSE at 20 dB/bin for a 50 MHz emitter with the coherent estimator, and
101° for the slope estimator proposed by the external review — the slope
estimator's effective lever arm is `B/sqrt(12)` against the carrier's `f_c`, and
`f_c > B` always. The same script rejects 50 mm element spacing (106° error at
3.75 GHz where 25 mm gives 0.27°), and
`scripts/estimate_wideband_dsp_resources.py` shows why a 16K FFT at 2.048 GSPS
is neither instantiable nor necessary.

Over the *whole* 2–4 GHz band the answer is more precise, and it is measured in
`scripts/compare_wideband_estimators.py` (V07 §11): a square 2×2 is wrap-free
while `d·√2·sin θ ≤ λ/2`, which allows 32.3 mm for the declared ±55° scan at
4 GHz, so the array pitch in `config.mk` is **30 mm** — not the review's 50 mm,
which is 1.7× too wide and is measured 34° and 104° off where 30 mm holds 1.6°
and 1.1°. In the same run a *through-origin* frequency-domain fit reaches 0.066°
on a 2 GHz emitter and 0.25° on a 50 MHz one, while the review's
unwrap-plus-intercept variant reaches 0.235° and loses every narrowband frame.
Estimator: `make compare-estimators`. Geometry, not the estimator, sets 0.5°.

For **multiple emitters** the same script's sibling, `make multisource-df`, shows
the boundary (V07 §12): the 2×2 finds 1.2 of 8 emitters over 2 GHz, a 4×4 at
60 mm finds 7, and a 6×6 at 75 mm finds all eight at 0.295°. Doubling the aperture
doubles detection; tripling the bandwidth does not move it.

## Accuracy statement

V7 demonstrated a 3-D Monte-Carlo RMSE below 0.1° in its stated simulated
acceptance domain (SNR ≥ 15 dB, 4096 coherent snapshots, calibrated 2×2 array).
That is a simulation contract, not a guaranteed field result. A real ZCU208
build must also prove converter coherence, MTS repeatability, channel/cable and
mounting calibration, quantized parity, timing closure, and HIL/anechoic tests.
