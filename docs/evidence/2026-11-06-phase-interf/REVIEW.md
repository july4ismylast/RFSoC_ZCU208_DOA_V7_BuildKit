# Evidence — V07 phase interferometry (2026-11-06)

Host-generated evidence for
[`V07_PHASE_INTERFEROMETRY.md`](../../../V07_PHASE_INTERFEROMETRY.md). Nothing
here was produced by Vivado, Vitis HLS, MATLAB or a board; it is arithmetic and
Monte-Carlo reproducible on any machine with `python3` + `numpy` and `g++`.

| File | Produced by | What it settles |
|---|---|---|
| `phase_interf_reference_check.txt` | `python3 scripts/phase_interf_verify.py` | Estimator physics: coherent WPI vs the external review's phase-slope fit, per-bin SNR sweep, snapshot averaging, calibration sensitivity, and the 50 mm vs 25 mm geometry decision |
| `wideband_frontend_screen.txt` | `python3 scripts/estimate_wideband_dsp_resources.py` | Front-end feasibility: 1024-band channelizer (measured) vs 1024/4096/16384-point SSR-8 FFT, device projection, IP support, and the equal-integration-time argument |

Reproduce everything, including the bit-exact host test of the production HLS
core (`ip/custom/phase_interf_4ch/src/phase_interf_core.hpp`):

```bash
make verify-phase-interf
```

## What this evidence does NOT prove

* No synthesis, placement, routing, timing, power or resource utilisation is
  measured here. The resource report is an explicit *screen* with a range, and
  its pessimistic end is what the build kit's V06 gate discipline exists for.
* The Monte-Carlo model generates complex spectra directly. Time-domain
  windowing, 16-bit quantisation and the FFT round trip are covered separately
  by `matlab_v7/verify_phase_interferometry_2x2.m`, which has **not been run**
  in this environment (no MATLAB licence).
* No RF, cable, antenna, calibration, MTS or thermal behaviour is measured.
  The accuracy numbers are simulation contracts, not field results.
