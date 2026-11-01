# V6.2 changes

V6.2 fixes the Simulink-only circling failure while preserving the V6.1
rotating-frame EKF and `SimulationOutput` logging fixes.

## Corrected Simulink position-vector shape

The generated `Source_Position` Constant can deliver `[x y z]` as a 3x1
column vector. `PlatformDynamics3D` previously subtracted it from its 1x3
internal position. MATLAB implicit expansion produced a 3x3 matrix, so
`norm(...)` reported about 1020.6 m instead of the correct initial range of
602.08 m. The arrival test could therefore never stop the vehicle. It passed
the source, the body-frame azimuth flipped by 180 degrees, and the vehicle
entered a loop.

All source and platform position inputs are now normalized to 1x3 in
`PlatformDynamics3D`, `SourceModel3D`, and `TruthErrorMonitor3D`. The generated
Constant block also preserves the row-vector parameter shape.

`verify_simulink_vector_shapes` is a new regression test. It passes a 3x1
source position into the platform, verifies the 602.08 m initial range, and
verifies that a platform 5 m from the source asserts arrival.
