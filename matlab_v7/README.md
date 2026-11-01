# Realistic 0.1-degree 2x2 DOA V7 — MATLAB R2024a + ZU48DR HIL

This V7 package models a physical nose-mounted 2x2 coherent receiver, wideband
PFB/FFT search, CA-CFAR detection, calibrated weighted phase interferometry,
off-grid bounded maximum-likelihood/Gauss-Newton refinement, full-attitude
navigation-frame unit-vector EKF tracking, and closed-loop 3D platform homing.
The new receiver model includes element-coordinate error, coupling, RF time
skew, channel drift, phase noise, thermal noise, AGC, clipping and a 14-bit ADC.
The separate HIL flow targets the ZCU208/XCZU48DR with a four-sample-per-clock
streaming calibration/covariance core.

Start with `COMPLETE_FILE_AND_CODE_GUIDE.md` for the single-document reference
covering all 63 implementation files, functions, important lines and complete
source code. `REALISTIC_DOA_ENGINEERING_GUIDE.md` contains the shorter clickable
block index, twelve dedicated block pages, and twelve JPEG diagrams. Use
`HIL_ZU48DR_GUIDE.md` for the board procedure and exact AXI/covariance formats.
See `CHANGELOG_V7.md` for the complete delta from V6.2.

The 0.1-degree requirement is a
great-circle Monte Carlo RMSE under explicit SNR, snapshot, calibration, field
of-view, and single-source conditions; it is not the 2-D grid spacing and not a
worst-case claim.

Run the statistical acceptance test before the homing demonstration:

```matlab
verify_hybrid_doa_2x2
results = run_accuracy_campaign('acceptance');
realisticResults = run_realistic_accuracy_campaign('acceptance');
```

## The reported constructor error is fixed

Every custom class derived from `matlab.System` now contains an explicit
name-value constructor:

```matlab
function obj=ClassName(varargin)
    setProperties(obj,nargin,varargin{:});
end
```

This prevents MATLAB R2024a from forwarding the name-value arguments to the
internal `matlab.system.SystemInterface` superclass.

## Start here

Extract the ZIP, open MATLAB in this directory, then run:

```matlab
START_HERE
```

This verifies the R2024a classes, builds `DOA_3D_Homing.slx`, and runs the
Simulink homing model. Use `run_3d_doa_sim` for the standalone MATLAB version.

## Detailed technical documentation

- `COMPLETE_FILE_AND_CODE_GUIDE.md`: one complete document with the overall
  diagram, clickable block/file headers, every implementation file, function
  explanations, important-line walkthroughs and full source code.
- `REALISTIC_DOA_ENGINEERING_GUIDE.md`: illustrated master guide and clickable
  block index.
- `HIL_ZU48DR_GUIDE.md`: separate vector generation, HLS, replay, capture and
  exact comparison procedure.
- `SIMULINK_MODEL_GUIDE.md`: complete Simulink signal flow, block algorithms,
  timing, logs, scopes, calculations, and troubleshooting.
- `RUN_3D_DOA_SIM_GUIDE.md`: separate explanation of the standalone MATLAB
  loop, result structure, equations, and numerical example.
- `SOURCE_WAVEFORM_PARAMETER_GUIDE.md`: changing source position, RF power,
  bandwidth, array, detection, navigation, and modulation.
- `ALGORITHM_CALCULATION_EXAMPLES.md`: worked geometry, path loss, noise,
  PFB, CFAR, MUSIC, error, and guidance calculations.
- `FILE_BY_FILE_REFERENCE.md`: purpose and algorithm of every distributed file.

The main source now supports `CW`, `BPSK`, `QPSK`, `8PSK`, `QAM16`, `QAM64`,
`LFM`, `NLFM`, `PM`, `FM`, `AM`, `FSK`, `PULSED_LFM`, and
`WIDEBAND_NOISE`. Select one in `sim3d_params.m`, then rerun the MATLAB script
or rebuild the Simulink model.

`source_modulation_profile.m` contains the modulation-specific `switch/case`.
Selecting `P.Source.ModulationType='LFM'`, for example, fetches LFM sweep start,
sweep stop, sweep time, and bandwidth; selecting `PM` fetches its tone and phase
index.

To create and open the fully connected behavioral Simulink model:

```matlab
run_simulink_homing
```

Equivalently, run:

```matlab
build_3d_doa_simulink
simulationOutput = sim('DOA_3D_Homing');
plot_simulink_results(simulationOutput)
```

Passing `simulationOutput` is required in R2024a when Single simulation output
is enabled; the logged `timeseries` objects are members of that object rather
than base-workspace variables.

The generated model is `DOA_3D_Homing.slx`. Four live scopes open when the
simulation starts. Arrival stops the Simulink run automatically; MATLAB then
creates the complete English results dashboard and the final RF spectrum
figure.

## What is visible in Simulink

The model canvas contains live numeric displays for:

- detection validity and arrival state;
- current range to the source and peak signal SNR;
- estimated and true azimuth/elevation;
- azimuth, elevation, and total angular errors;
- detected RF center frequency and estimated bandwidth.

The scopes show estimated-versus-true DOA, all DOA errors, range/arrival, and
detection/SNR. The automatic final dashboard also shows the 3D receiver path,
source position, range, signal characteristics, receiver attitude, detection
history, and error histories.

All corresponding signals are saved as `timeseries` variables, including the
full PFB spectrum and RF frequency axis.

## RFSoC HDL and HIL path

The floating-point source, path-loss model, local-ML/EKF controller, GUI, and
vehicle dynamics are verification/testbench components. The streaming
calibration/covariance stage runs in PL; bounded WPI/ML/GN and the EKF can
initially execute on the R5/A53 at one update per DOA frame.

```matlab
run_zcu48dr_hil('prepare')
run_zcu48dr_hil('loopback')       % host-only parser check, not hardware
run_zcu48dr_hil('compare','capture.csv')
```

The package does not claim a placed-and-routed resource/timing result: run the
included HLS self-test and synthesis, then Vivado implementation in the verified
BuildKit RFDC/MTS shell. Hardware acceptance requires those reports plus the
real board capture and far-field calibration campaign.

Create the four-channel fixed-point streaming channelizer model with:

```matlab
build_rfsoc_hdl_frontend_model
```

Generate Verilog with:

```matlab
generate_rfsoc_hdl_frontend
```

The HDL DUT uses four parallel `dsphdl.Channelizer` instances—one for each
coherent ADC/IQ stream—with `validIn` and `validOut`. It targets:

- Board: ZCU208
- Device: `xczu48dr-fsvg1517-2-e`
- Vivado: 2023.2
- MATLAB: R2024a

`PreservePhase` is not used because that property is unavailable in R2024a.
All four paths use identical coefficients and architecture, preserving the
inter-channel phase differences needed by DOA processing.

Connect the four coherent RF inputs to the square Y-Z geometry in
`P.Antenna.Positions`. The array normal/boresight is +X. Because any planar
array has a front/back mirror ambiguity, operation is explicitly restricted to
the known forward hemisphere.

The generated scalar-stream channelizer remains a functional MATLAB HDL
reference. The V7 `doa_covariance_4ch_v4` HLS core is separately vectorized at
four time samples per 512-bit beat. The ZU48DR shell must still supply the
documented RFDC decimation, packing, clock converters and FIFOs.

## Standalone search-stage test

MATLAB execution:

```matlab
run_search_chain_matlab
```

Simulink model generation:

```matlab
build_doa_search_model
```

## Simulink closed-loop wiring

The 3D model is now wired as follows:

```text
Source X4 -> PFB/FFT -> Spectrum -> CFAR -> Clustering -> Candidate
         \-> Snapshot selection -> DOA -> detection-gated platform dynamics
Platform position/yaw/pitch/roll -> Unit Delays -> Source
Delayed pose + DOA -> truth/error monitor -> scopes, displays, logs
```

The Unit Delay blocks break the algebraic navigation loop. The DOA branch uses
4096 spatial snapshots by default. The spatial covariance convention matches the
source steering-vector convention, preventing a mirrored direction estimate.
The square 2x2 aperture is qualified over the forward field of view in
`P.Accuracy`. Invalid detections do not steer the receiver, azimuth filtering
wraps correctly at +/-180 degrees, and motion stops after arrival.

## Requirements

- MATLAB R2024a
- DSP System Toolbox
- Simulink for model generation
- DSP HDL Toolbox for the RFSoC HDL model
- Fixed-Point Designer and HDL Coder for Verilog generation
- Vivado 2023.2 for FPGA synthesis/integration

## Main files

| File | Purpose |
|---|---|
| `START_HERE.m` | One-command verification, Simulink build, and simulation |
| `README_FIRST.txt` | Short operating instructions and expected results |
| `ACCURACY_AND_HDL_GUIDE.md` | 0.1-degree definition, limits, and ZU48DR partition |
| `run_accuracy_campaign.m` | 1000-trial statistical acceptance test |
| `verify_hybrid_doa_2x2.m` | Noise-free geometry/calibration regression test |
| `SIMULINK_MODEL_GUIDE.md` | Detailed generated-model algorithm guide |
| `RUN_3D_DOA_SIM_GUIDE.md` | Detailed standalone MATLAB algorithm guide |
| `SOURCE_WAVEFORM_PARAMETER_GUIDE.md` | Modulation and experiment parameters |
| `ALGORITHM_CALCULATION_EXAMPLES.md` | Worked numerical calculations |
| `FILE_BY_FILE_REFERENCE.md` | Detailed explanation of every file |
| `verify_source_waveforms.m` | Regression check for every source modulation mode |
| `source_modulation_profile.m` | Switch/case waveform-specific parameter profiles |
| `source_modulation_summary.m` | Selected-profile text for MATLAB and Simulink |
| `verify_r2024a_setup.m` | Checks constructors, duplicate paths, and required classes |
| `run_3d_doa_sim.m` | Main MATLAB homing simulation |
| `run_simulink_homing.m` | One-command Simulink build and run launcher |
| `build_3d_doa_simulink.m` | Fully connected behavioral Simulink builder |
| `plot_simulink_results.m` | Automatic post-Simulink plots and RF spectrum |
| `plot_homing_results.m` | Complete MATLAB/Simulink homing dashboard |
| `sim3d_params.m` | Master source, antenna, search, DOA, and navigation parameters |
| `SourceModel3D.m` | RF waveform, path loss, noise, and coherent array channels |
| `PFBFFTChannelizer4.m` | Four parallel floating-point PFB channelizers |
| `DOAEstimator4Ch.m` | Calibrated weighted phase LS, local ML, and unit-vector EKF |
| `estimate_multifrequency_calibration.m` | Boresight gain/phase/time-skew calibration and Q2.14 register generation |
| `PlatformDynamics3D.m` | Stateful guidance and 3D kinematics |
| `TruthErrorMonitor3D.m` | True body-frame DOA and per-step error metrics |
| `SignalMetricsMonitor.m` | Peak, SNR, selected RF center, and bandwidth metrics |
| `verify_doa_direction.m` | Legacy MUSIC direction-sign regression check |
| `ZU48DRChannelizer4.m` | Four-channel synthesizable DSP HDL wrapper |
| `build_rfsoc_hdl_frontend_model.m` | RFSoC HDL Simulink model builder |
| `generate_rfsoc_hdl_frontend.m` | HDL Coder launcher |

## If MATLAB still shows the old constructor error

Run:

```matlab
clearvars
rehash path
which SourceModel3D -all
```

If more than one path appears, remove the old project directory from the MATLAB
path and keep this extracted directory first. If an older System object class
is already locked, restart MATLAB once; global `clear classes` is intentionally
not used because it produces unrelated `digraph`, Simulink and HDL warnings.
