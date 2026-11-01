# V6 changes

- Replaced the reference + X/Y/Z geometry with a physical nose-mounted 2x2
  square Y-Z array.
- Defined 0.1 degree as 3-D great-circle Monte Carlo RMSE over independent
  estimates, with separate bias, azimuth/elevation RMSE, and P95 reporting.
- Increased each raw estimate to 4096 coherently accumulated snapshots.
- Added inverse complex channel calibration with explicit nonzero residuals.
- Added six-baseline coherence-weighted phase least squares.
- Added fixed-cost off-grid local single-source ML refinement: 36 scores/frame.
- Added a normalized unit-vector plus angular-rate EKF.
- Updated the MATLAB runner and generated Simulink builder for the new block.
- Added deterministic and Monte Carlo acceptance scripts.
- Added a ZU48DR implementation/resource guide.
