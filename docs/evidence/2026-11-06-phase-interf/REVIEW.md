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

Reproduce everything, including the bit-exact host test of the production core
and the shimmed execution of the production kernel plus its Vitis testbench
(`ip/custom/phase_interf_4ch/`):

```bash
make verify-phase-interf
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
