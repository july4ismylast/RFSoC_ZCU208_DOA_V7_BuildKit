# V6.1 corrective update

- Fixed the high closed-loop homing error: the unit-vector EKF now tracks the
  line of sight in the navigation/world frame, using platform yaw and pitch,
  instead of treating the rotating body frame as inertial.
- Connected delayed yaw and pitch to the DOA System block in the generated
  Simulink model.
- Added `verify_rotating_frame_ekf.m`, which changes platform attitude while
  holding the world line of sight fixed and fails if the tracked DOA moves.
- Fixed the R2024a results dashboard by passing `Simulink.SimulationOutput`
  directly to `plot_simulink_results` after `sim` returns.
- Removed global `clear classes` commands that produced unrelated `digraph`,
  RTW, HDL Coder, and scope-object warnings.
- Changed final dashboard statistics from MAE to azimuth, elevation, and exact
  3-D RMSE.
