# R2024a RFSoC-HDL correction

## Homing and Simulink-results revision

- Corrected the spatial covariance conjugation so MUSIC, MVDR, and the source
  model use the same steering-vector sign; this removes the mirrored DOA that
  previously sent the receiver away from the source.
- Increased the default coherent snapshots from 8 to 256 and raised the
  simulated received-SNR margin for stable four-channel direction finding.
- Replaced the ambiguous planar array default with a four-channel non-coplanar
  geometry and a signed -60 to +60 degree elevation scan. MUSIC, MVDR, ESPRIT,
  phase interferometry, and the source model now include the Z baseline.
- Added circular azimuth filtering, detection-gated steering, pure-pursuit
  guidance, an arrival output, and a hard stop inside the arrival radius.
- Added a Simulink truth/error monitor for true azimuth/elevation, azimuth
  error, elevation error, and total 3D angular error on every update.
- Added live Simulink scopes and numeric displays for DOA, truth, errors, range,
  arrival, detection, SNR, selected RF center, and estimated bandwidth.
- Changed behavioral-model logs to `timeseries` and added automatic English
  result dashboards, including trajectory, source parameters, detection,
  navigation, and the final PFB spectrum.
- Added a deterministic DOA direction-sign regression check.
- Added explicit CW, BPSK, QPSK, 8PSK, QAM16, QAM64, LFM, cubic-NLFM, PM,
  FM, AM, FSK, pulsed-LFM, and band-limited-noise source modes.
- Added independent waveform controls for tone frequency, PM index, AM depth,
  FM/FSK deviation, NLFM shape, pulse width, and PRF.
- Added `source_modulation_profile.m`: selecting `ModulationType` now fetches
  the matching parameters through an explicit switch/case. LFM/NLFM have
  independent sweep-start, sweep-stop, and sweep-time controls.
- Added separate detailed Markdown guides for the Simulink model, standalone
  MATLAB runner, source parameters/waveforms, worked calculations, and every
  project file.

## Constructor and RFSoC revision

- Added `setProperties` constructors to all custom `matlab.System` classes.
- Marked configuration properties as nontunable for predictable Simulink use.
- Rebuilt the four-channel behavioral PFB with one channelizer per coherent input.
- Added fixed-size snapshot selection before the DOA estimator.
- Corrected ESPRIT and phase-interferometry phase-sign handling.
- Restricted the default elevation scan to the physically selected positive
  hemisphere of the planar array.
- Preserved configured platform initial state through `setupImpl` and reset.
- Completed the Simulink navigation feedback wiring with Unit Delay blocks.
- Added a separate fixed-point, valid-qualified, four-channel `dsphdl.Channelizer`
  DUT for RFSoC/HDL Coder.
- Avoided the post-R2024a `PreservePhase` property.
- Added deterministic random seeds and a constructor/path verification script.
