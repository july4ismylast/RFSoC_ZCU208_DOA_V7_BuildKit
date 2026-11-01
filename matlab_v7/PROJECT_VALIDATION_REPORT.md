# V7 validation report and evidence boundary

## Checks completed in the delivery environment

| Check | Result |
| --- | --- |
| Twelve JPEG diagrams generated | PASS; each is 1600 x 440 baseline JPEG |
| Master/block Markdown local links | PASS; no missing local targets |
| Every block page structure | PASS; image, header index, I/O, algorithm, code walkthrough, example and checks |
| Complete code guide | PASS; 63 implementation sources documented exactly once, 75 explicit anchors resolve, complete source listings present |
| Python documentation generators | PASS; both compile |
| Simulink source/estimator/truth pose ports | Static audit PASS; position, yaw, pitch and roll are consistently wired |
| Covariance convention | Static audit PASS; HLS, MATLAB fixed-point reference and PS reconstruction use `R(second,first)=sum(x_second*conj(x_first))` |
| HLS frame structure | Static audit PASS; 512-bit input, four lanes, four channels, complex int16, 16 signed int64 outputs |
| HLS self-test source | Included; checks every output and `TLAST` exactly |
| Multi-frequency calibration regression | Independent numerical reproduction passes gain, center-phase and time-skew tolerances |
| Realistic DOA plausibility cross-check | Independent 250-trial reproduction: about 0.0902 deg at 15 dB, 0.0565 deg at 20 dB and 0.0424 deg at 25 dB |

The independent DOA reproduction is a plausibility check, not a substitute for
running the supplied 1000-trial MATLAB campaign. The approximate 95% interval
around the 250-trial 15 dB RMS estimate was 0.0832 to 0.0993 degree.

## Checks that require the user's toolchain or hardware

MATLAB R2024a, Simulink, Vitis HLS/Vivado 2023.2 and a ZCU208 were not available
in the delivery environment. Therefore these results are deliberately not
claimed as completed:

1. `verify_r2024a_setup` and both 1000-trial MATLAB campaigns;
2. generated Simulink model update and closed-loop arrival run;
3. Vitis HLS C simulation, synthesis timing, II and utilization report;
4. full Vivado RFDC/MTS shell place-and-route timing/utilization;
5. repeated-boot MTS/calibration stability;
6. exact 16-word board HIL capture;
7. calibrated far-field antenna/radome measurement.

## Required acceptance sequence

```matlab
verify_r2024a_setup
run_accuracy_campaign('acceptance')
run_realistic_accuracy_campaign('acceptance')
run_3d_doa_sim
START_HERE
run_zcu48dr_hil('prepare')
run_zcu48dr_hil('loopback')
```

Then build and implement `doa_covariance_4ch_v4`, replay the generated frame,
capture 16 signed integers, and run:

```matlab
run_zcu48dr_hil('compare','capture.csv')
```

A production claim requires all steps above, plus far-field calibration. A
simulation pass alone does not prove physical 0.1-degree accuracy or ZU48DR
timing closure.
