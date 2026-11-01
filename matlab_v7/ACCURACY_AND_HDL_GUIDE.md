# 0.1-degree 2x2 DOA definition and ZU48DR implementation guide

## The accuracy claim

In this project, **0.1 degree** means:

> The root-mean-square exact 3-D angular separation between the true and raw
> refined DOA unit vectors is at most 0.1 degree over 1000 independent Monte
> Carlo estimates.

The 1000 trials are used to estimate the statistic. Their output angles are
**not averaged together**. Every individual estimate coherently accumulates
4096 four-channel IQ snapshots. The test also reports azimuth RMSE, elevation
RMSE, azimuth/elevation bias, and 95th-percentile 3-D error. The 0.1-degree
number is an RMSE requirement, not a worst-case or 95th-percentile guarantee.

Qualified conditions:

- one dominant source in the selected PFB/DDC subband;
- per-channel input SNR at least 15 dB;
- 4096 coherent snapshots per independent estimate;
- azimuth from -45 to +45 degrees and elevation from -35 to +35 degrees;
- 4.000 GHz manifold frequency and 25 mm square element pitch;
- residual calibrated relative phase no larger than about 0.05 degree and
  residual gain no larger than about 0.01 dB;
- forward hemisphere known from installation/mission geometry;
- direction effectively constant during one covariance accumulation.

Run the formal test with:

```matlab
verify_hybrid_doa_2x2
results = run_accuracy_campaign('acceptance');
realisticResults = run_realistic_accuracy_campaign('acceptance');
```

The first campaign is the controlled calibration/noise baseline. The second
also injects actual/calibrated element-coordinate mismatch, coupling residual,
time skew, drift, phase noise, weak multipath, common AGC and ADC quantization.
The qualified V7 claim uses `CALIBRATED_LOS`; `FIELD_STRESS` is a degradation
study and is never relabeled as a pass.

The moving-platform plot is useful for system behavior, but it is not the
acceptance test because its SNR, angle, range, and tracker transient all change
at once.

## Why the original model stopped near 1 to 1.5 degrees

The original default was a full 2-D MUSIC scan on a 1-degree grid. Its output
was therefore quantized before noise, channel phase mismatch, and navigation
lag were considered. It also modeled a reference element plus independent
X/Y/Z baselines, not a physical square 2x2 aperture, and it injected channel
gain/phase errors without applying inverse calibration in the DOA block.

Changing only `ScanResolution` to 0.1 degree would make the grid roughly 100
times more expensive, would not remove calibration bias, and would still
quantize the result. It is not the selected solution.

## Selected estimator

1. Apply four complex channel calibration coefficients.
2. Accumulate the Hermitian 4x4 covariance; only four powers and six complex
   cross-products are unique.
3. Use the phase and coherence of all six baselines in a weighted 2x2
   least-squares solution for the Y and Z direction cosines.
4. Evaluate a single-source maximum-likelihood/Bartlett score locally. Four
   fixed stages of 3x3 candidates use steps of 0.5, 0.1, 0.02, and 0.005 degree,
   for exactly 36 scores per estimate.
5. Use a fixed four-step power iteration and two bounded Gauss-Newton updates
   to remove the final local-grid residue without a general eigendecomposition.
6. Track the refined measurement with a normalized six-state unit-vector and
   angular-rate EKF. Azimuth is never averaged across the -180/+180 boundary.

For one dominant source, local rank-one ML has no full eigendecomposition and
is substantially cheaper than full-grid 2-D MUSIC. The PFB/CFAR branch first
separates emitters in frequency; the DOA backend operates on one selected
cluster.

## Physical 2x2 geometry

The array lies on the nose Y-Z plane, centered on the boresight:

| Channel | X (m) | Y (m) | Z (m) |
| --- | ---: | ---: | ---: |
| 0 | 0 | -0.0125 | -0.0125 |
| 1 | 0 | +0.0125 | -0.0125 |
| 2 | 0 | -0.0125 | +0.0125 |
| 3 | 0 | +0.0125 | +0.0125 |

At 4 GHz, wavelength is 74.948 mm and the 35.355 mm diagonal is 0.472 lambda,
below lambda/2. Thus all six baseline phases are unambiguous. If center
frequency or element pitch changes, `sim3d_params.m` checks this condition.

A planar array has a front/back mirror ambiguity. This package resolves it by
the known nose forward-hemisphere constraint (`u_x > 0`); it does not claim
all-sky signed DOA.

## ZU48DR partition

| Stage | Recommended location | Hardware form |
| --- | --- | --- |
| RFDC, MTS, DDC/PFB, cluster selection | PL + hardened RFDC | Existing ZCU208 shell and coherent stream |
| Channel calibration | PL | Four complex constant multipliers |
| Covariance accumulation | PL | Streaming; no 4096-sample frame RAM required |
| Six phase/coherence values | PL | Time-shared CORDIC and reciprocal |
| Weighted 2x2 phase solve | PL or R5/A53 | Fixed-size arithmetic only |
| 36 local ML + 2 GN updates | R5/A53 initially | Bounded loop; no global grid/eigenvectors |
| Unit-vector EKF | R5/A53 initially | 6x6, one update per DOA frame |

The supplied PL covariance core needs only accumulator/register storage rather
than a 4096-sample frame RAM. No resource-fit percentage is claimed in V7:
the authoritative numbers are the generated HLS `csynth` and complete Vivado
implementation reports from the user's RFDC/MTS shell.

AMD lists the ZU48DR with 930K system logic cells, 4272 DSP slices, and 60.5 Mb
of programmable-logic memory:

- https://www.amd.com/en/products/adaptive-socs-and-fpgas/soc/zynq-ultrascale-plus-rfsoc.html
- https://docs.amd.com/v/u/en-US/ds889-zynq-usp-rfsoc-overview

## Hardware conditions that dominate accuracy

The algorithm cannot compensate for unstable channel phase. RFDC multi-tile
synchronization must be rerun at boot, followed by a calibration tone or known
far-field source that measures the complete RF path: antenna, cable, LNA,
mixer/DDC, and ADC channel. Temperature-dependent calibration should be
remeasured or interpolated. A residual differential phase of 0.1 degree can
already consume most of a 0.1-degree angular error budget for this aperture.

Element position error and mutual coupling must be included in the calibrated
array manifold for real measurements. The ideal square coordinates are only
the starting model.

## Commands

```matlab
verify_r2024a_setup
run_accuracy_campaign('acceptance')
run_realistic_accuracy_campaign('acceptance')
run_3d_doa_sim
build_3d_doa_simulink
sim('DOA_3D_Homing')
run_zcu48dr_hil('prepare')
run_zcu48dr_hil('compare','capture.csv')
```

For direct Simulink execution in R2024a, use
`simulationOutput=sim('DOA_3D_Homing'); plot_simulink_results(simulationOutput)`
so the dashboard reads logs from the returned simulation object.

The unit-vector EKF state is maintained in the navigation/world frame. The
snapshot block supplies current platform yaw, pitch and roll, the estimator converts
the body-frame measurement to a world-frame line of sight, performs the EKF
update, and converts the result back to body-frame azimuth/elevation. Tracking
directly in the rotating body frame is invalid and creates control oscillation.
