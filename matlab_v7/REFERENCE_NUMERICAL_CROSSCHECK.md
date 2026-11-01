# Independent numerical cross-check

The MATLAB acceptance campaign is authoritative. As a development check in an
environment without MATLAB, the same equations were independently executed
with double-precision array arithmetic, 1000 trials per SNR, random QPSK,
4096 snapshots, configured gain/phase mismatch, configured residual calibration
error, forward/backward averaging, weighted phase LS, and all 36 local ML
scores.

| SNR (dB) | Az bias (deg) | El bias (deg) | Az RMSE (deg) | El RMSE (deg) | 3-D RMSE (deg) | 3-D P95 (deg) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | -0.027820 | 0.007662 | 0.119342 | 0.104205 | 0.152808 | 0.265107 |
| 15 | -0.015448 | 0.001326 | 0.068809 | 0.055403 | 0.084821 | 0.148283 |
| 18 | -0.023036 | 0.002819 | 0.052543 | 0.039445 | 0.063049 | 0.112521 |
| 20 | -0.020325 | 0.002628 | 0.042427 | 0.033572 | 0.051926 | 0.092876 |
| 25 | -0.019109 | 0.003243 | 0.028161 | 0.018780 | 0.032294 | 0.054451 |

The 0.1-degree 3-D RMSE threshold passes from 15 dB upward under the qualified
conditions. The table also shows why this must not be described as a
95th-percentile guarantee at 15 dB.

A separate 250-trial check at 20 dB quantized each complex input component to
signed 16-bit with 14 fractional bits. The floating-input 3-D RMSE was
0.053774 degree and the quantized-input result was 0.053775 degree, a measured
degradation of about 0.000001 degree. This covers input quantization only; the
complete HLS accumulator/CORDIC path still needs RTL or C/RTL cosimulation.

## V6.1 rotating-platform cross-check

The closed-loop geometry, navigation-frame EKF, calibration residuals, 4 GHz
2x2 manifold, range-dependent free-space loss, 2.048 GHz receiver-noise
bandwidth, 4096 snapshots, and guidance loop were then exercised together.
The receiver arrived at 9.17 m after 23.8 s. Raw-refined 3-D RMSE was 0.0343
degree and navigation-frame EKF output RMSE was 0.0274 degree. This check is
why `verify_rotating_frame_ekf.m` is now part of `verify_r2024a_setup`.
