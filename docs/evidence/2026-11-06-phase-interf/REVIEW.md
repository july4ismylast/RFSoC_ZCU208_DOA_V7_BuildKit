# Evidence — V07 phase interferometry (2026-11-06)

Host-generated evidence for
[`V07_PHASE_INTERFEROMETRY.md`](../../../V07_PHASE_INTERFEROMETRY.md). Nothing
here was produced by Vivado, Vitis HLS, MATLAB or a board; it is arithmetic and
Monte-Carlo reproducible on any machine with `python3` + `numpy` and `g++`.

| File | Produced by | What it settles |
|---|---|---|
| `phase_interf_reference_check.txt` | `python3 scripts/phase_interf_verify.py` | Estimator physics: coherent WPI vs the external review's phase-slope fit, per-bin SNR sweep, snapshot averaging, calibration sensitivity, and the 50 mm vs 25 mm geometry decision |
| `wideband_frontend_screen.txt` | `python3 scripts/estimate_wideband_dsp_resources.py` | Front-end feasibility: 1024-band channelizer (measured) vs 1024/4096/16384-point SSR-8 FFT, device projection, IP support, and the equal-integration-time argument |
| `phase_interf_kernel_hostrun.txt` | `make -C ip/custom/phase_interf_4ch host-kernel-check` (`g++`) | The **production kernel and production Vitis testbench** compile and pass: AXI beat packing, 16-word order + `TLAST`, phase-record bit positions, frame-tag echo, az/el sign — over a 16-sample frame, the 4096-sample production frame, and a physical steering case |
| `matlab_syntax_check.txt` | `mh_lint` (MISS_HIT 0.9.44) | The three `matlab_v7/*.m` reference files parse as MATLAB. Parse only — they have not been executed |
| `wpi_vs_music_check.txt` | `python3 scripts/compare_wpi_vs_music.py` (`make compare-estimators`) | V07 §10: WPI at 1.22× the CRB vs 2.5–4.8× worse for per-bin and narrowband MUSIC; the 2×2 manifold rank that makes two-emitter subspace processing impossible; per-bin vs single-coefficient calibration; position sensitivity |
| `wideband_df_check.txt` | `python3 scripts/compare_wideband_estimators.py` (`make wideband-df`) | V07 §11: the wrap-free rule for a square 2×2 (`d·√2·sin θ ≤ λ/2` → 32.3 mm for ±55° at 4 GHz), five estimators compared on the same per-bin cross-spectra over the full 2–4 GHz band, the measured 37.5/50 mm diagonal aliasing, position-error sensitivity, and the narrowband frames the unwrap-plus-intercept fit loses (10/10) while the through-origin fit loses none |
| `multisource_capacity.txt` | `python3 scripts/multisource_capacity.py` (`make multisource-df`) | V07 §12: elements vs M−1 vs measured manifold rank for 2×2…6×6, eight-emitter detection and accuracy per array (2×2 → 1.2 of 8, 6×6@75 mm → 8 of 8 at 0.295°), and the aperture-vs-bandwidth experiment that shows 2 GHz of bandwidth does not buy resolution |
| `narrowband_targets.txt` | `python3 scripts/narrowband_targets.py` (`make narrowband-targets`) | V07 §12.4: eight 1–50 MHz targets at different carriers on the shipped 2×2 — 8.0 of 8 detected in 20/20 trials, accuracy vs bandwidth and dwell (0.59°→0.12° for a 1 MHz target from 16→256 snapshots), the co-channel case where 2×2 recovers 0.2 of 2 while 3×3/4×4 recover 2 of 2 |
| `decoy_discrimination.txt` | `python3 scripts/decoy_discrimination.py` (`make decoy-df`) | V07 §13: one protected 2.5 GHz emitter behind decoys — off-carrier decoys cost 0.00° of accuracy (1/2/4/7 clusters for 0/1/3/6), independent co-channel decoys recover 0.4 of 2 on the 2×2 and 2.0 on 3×3, a coherent repeater is flagged by 43.8° rms DOA wobble (clean 0.31°) and a cepstrum peak of 101 ns from a true 100 ns, and a joint delay+angle ML recovers both directions 100% at 20–50 MHz but 0% at 1 MHz; the co-located zero-delay case is stated as indistinguishable |
| `packaging_vlnv_check.txt` | `common/scripts/check_component_vlnv.sh` | The VLNV `config.mk` asks for is the one `build_hls.tcl` would export (`openai:doa:phase_interf_4ch:1.0`) and `step06` rejects any other. Exercises the checker with a synthetic `component.xml`; it does not prove Vitis produced one |

Reproduce everything, including the bit-exact host test of the production core
and the shimmed execution of the production kernel plus its Vitis testbench
(`ip/custom/phase_interf_4ch/`):

```bash
make verify-phase-interf     # host checks + both estimator studies (quick)
make compare-estimators      # V07 §10 and §11 at full trial counts
```

## The one thing that could silently have been wrong

The block accumulates its cross-spectra as `X_b·conj(X_a)`. The whole point of
that particular order is that it is **the order `doa_covariance_4ch_v4` already
accumulates**, so `m_axis` is a drop-in replacement and the PS reuses
`estimate_doa_from_covariance_v7.m` — with its leading minus — unchanged. The
opposite order (`X_a·conj(X_b)`) is equally defensible physics but silently
mirrors every reported angle once the PS applies that minus. Both variants were
run through the same reference WLS: `X_b·conj(X_a)` with the minus reports
az `+12.5°` as `+12.5°`, and the mirrored pairing reports `-12.5°` with identical
RMSE. The convention is now asserted in four places (host core test with a
target at az +20°/el -12°, the C-simulation testbench through the AXI ports, the
Python steering model, and the MATLAB estimator's product order) so a later
"sign fix" cannot land quietly.

## Three defects this pass found and fixed before they reached a licence

1. **The block accumulated the opposite cross-product** to `doa_covariance_4ch_v4`
   (see above) — a silent angle mirror once the PS applied the existing minus.
2. **The CORDIC normaliser was two data-dependent `while` loops.** Vitis HLS
   cannot schedule a loop bound that depends on data; this would have failed or
   mis-built `csynth`. It is now 51 fixed-trip conditional steps, with the host
   test still at 1 LSB worst-case error.
3. **`build_hls.tcl` constrained 7.8125 ns** (`PL_CLOCK_PERIOD_NS`) for a block
   that runs on the 250 MHz wideband clock. A passing csynth report would have
   described a clock the block never sees. It now uses
   `WIDEBAND_CLOCK_PERIOD_NS` (4.0 ns), and `gate3_ooc.tcl` fails the gate if the
   packaged IP's `ap_clk` is not that period.

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
