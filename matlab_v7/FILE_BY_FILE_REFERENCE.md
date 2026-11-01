# File-by-File Technical Reference

> **V7 note:** This inherited inventory retains historical descriptions for
> unchanged files. Use `REALISTIC_DOA_ENGINEERING_GUIDE.md`, its twelve linked
> block pages, `HIL_ZU48DR_GUIDE.md` and `CHANGELOG_V7.md` as authoritative.

This reference explains every distributed project file. The files are grouped
by purpose rather than alphabetically.

## 1. Quick-start and documentation files

### `START_HERE.m`

The primary entry point. It clears variables (not global classes), runs
`verify_r2024a_setup`, builds `DOA_3D_Homing.slx`, and starts the Simulink
simulation. Use this when testing the complete package for the first time.

### `README_FIRST.txt`

A short plain-text checklist intended to be visible immediately after ZIP
extraction. It lists the required command, expected motion, expected arrival,
and result plots.

### `README.md`

Project overview, toolbox requirements, quick commands, RFSoC-HDL separation,
physical antenna note, and the most important source files.

### `SIMULINK_MODEL_GUIDE.md`

Detailed explanation of the generated behavioral Simulink model, every major
block, model timing, live scopes, workspace logs, callbacks, equations, and a
worked first-update example.

### `RUN_3D_DOA_SIM_GUIDE.md`

Detailed explanation of the direct MATLAB loop in `run_3d_doa_sim.m`, object
construction, the result structure, per-iteration execution, equations,
numerical calculations, GUI, and differences from Simulink.

### `SOURCE_WAVEFORM_PARAMETER_GUIDE.md`

Complete source-parameter and waveform guide. It documents all implemented
modulations, LFM/NLFM/PM/FM equations, practical parameter combinations,
detection interactions, and the procedure for adding another waveform.

### `ALGORITHM_CALCULATION_EXAMPLES.md`

Standalone worked calculations for geometry, wavelength, phase delays, path
loss, thermal noise, PFB resolution, CA-CFAR threshold, MUSIC covariance,
error metrics, and navigation.

### `CHANGELOG.md`

Records the R2024a constructor correction, covariance sign fix, signed 3D array
geometry, detection-gated navigation, arrival stop, Simulink dashboard, and
waveform/documentation additions.

## 2. Master configuration

### `sim3d_params.m`

The single source of configuration for both full closed-loop implementations.
It creates structure `P` with these groups:

- `P.Source`: position, RF frequency, bandwidth, power, modulation, and
  waveform-specific controls;
- `P.Platform`: initial state, speed, rate limits, and navigation filter;
- `P.Antenna`: actual and calibrated square Y-Z element coordinates;
- `P.Receiver`, `P.Multipath`, `P.Realism`: realistic impairment profiles;
- `P.Channel`: path-loss exponent, noise figure, and channel calibration error;
- `P.PFB`: sample rate, frame length, channel count, decimation, and filter;
- `P.Spectrum`, `P.Noise`, `P.CFAR`, `P.Cluster`, `P.Candidate`: search rules;
- `P.DOA`: algorithm, snapshot count, scan limits/resolution, and source count;
- `P.Nav`: guidance law and arrival radius;
- `P.Sim`: update step, stop time, frame period, and random seed;
- `P.GUI`: enable and refresh rate.

The assertions at the end catch invalid PFB divisibility, median-window parity,
and signal-count settings before simulation.

### `source_modulation_profile.m`

Contains the modulation-specific `switch/case` configuration requested for the
RF source. `sim3d_params.m` supplies `ModulationType`; this function returns the
matching bandwidth, chip rate, sweep start/stop/time, PM/FM/AM controls, FSK
deviation, NLFM shape, pulse width, and PRF. Unused fields retain safe defaults
so the System-object interface stays fixed for Simulink.

### `source_modulation_summary.m`

Formats only the relevant parameters for the currently selected profile. The
standalone runner prints this text, and the Simulink builder places it in the
source annotation so irrelevant controls are not presented as active.

### `doa_search_params.m`

Separate configuration for the standalone multi-target search-stage test. It
defines two targets and two interferers by baseband offset, bandwidth, SNR, and
direction. It does not drive the moving-platform homing model.

## 3. Closed-loop source and receiver System objects

### `SourceModel3D.m`

Produces the `FrameLength x 4` coherent complex-IQ array received from a fixed
source at the current platform pose.

Algorithm:

1. Generate CW, digital modulation, LFM, NLFM, PM, FM, AM, FSK, pulsed-LFM, or
   band-limited noise.
2. Limit the complex-baseband spectrum to `BandwidthHz`.
3. Normalize waveform average power.
4. Calculate world range and body-frame DOA.
5. Convert `PowerdBm` to received watts after path loss.
6. Apply `exp(-j*2*pi*fc*tau_m)` for each X/Y/Z antenna location.
7. Add thermal receiver noise.
8. Apply per-channel gain and phase error.

Input ports: platform position, yaw, pitch. Output: `X4`.

### `PFBFFTChannelizer4.m`

Behavioral four-channel polyphase filter-bank/FFT front end. It creates one
`dsp.Channelizer` per coherent antenna channel. The output shape is
`FrameLength/DecimationFactor x NumBands x 4`.

### `SpectrumEstimator4.m`

FFT-shifts PFB bins, averages power over PFB time rows, maintains a first-order
smoothed power state, combines four channels, converts to dB with a power
floor, and supplies the baseband frequency axis.

### `NoiseFloorEstimator1D.m`

Calculates a sliding-median local noise vector and a scalar global-median noise
floor. The scalar dB output is used for candidate SNR and the displays.

### `CACFAR1D.m`

Implements one-dimensional cell-averaging CFAR. For every testable bin, it
averages two training regions around excluded guard cells, multiplies the
result by the exponential-noise CA-CFAR factor, and outputs detection,
threshold, and noise-estimate vectors.

### `BinClusterEstimator.m`

Converts the fixed detection mask into at most `MaxClusters` frequency
clusters. It optionally fills short internal gaps, rejects clusters below a
minimum bin count, and estimates power-weighted center, start/stop frequency,
bandwidth, and peak dB.

### `CandidateSelector.m`

Rejects clusters outside the configured bandwidth range or below minimum SNR.
It then selects the highest scoring valid cluster. Outputs are logical valid,
selected index, baseband center, bandwidth, and peak dB.

### `SnapshotDecimator4.m`

Selects evenly spaced rows from the raw `FrameLength x 4` complex IQ matrix.
With the defaults it produces `256 x 4` spatial snapshots. It deliberately
bypasses the power/search branch so inter-channel phase is preserved.

### `DOAEstimator4Ch.m`

Estimates source azimuth/elevation from four coherent channels and a
non-coplanar array.

Implemented algorithms:

- MUSIC: signal/noise subspace eigendecomposition plus 2D grid scan;
- MVDR: diagonally loaded inverse-covariance grid scan;
- ESPRIT: direct single-source X/Y/Z baseline phase calculation;
- phase interferometry: direct average cross-phase calculation.

The covariance uses `X.'*conj(X)` because rows are time snapshots and the
source manifold uses a negative spatial phase. This sign convention is vital
for homing in the correct direction.

### `TruthErrorMonitor3D.m`

Calculates true body-frame azimuth/elevation from source and receiver geometry.
It outputs wrapped azimuth error, elevation error, and exact three-dimensional
angular separation from the estimated/true unit-vector dot product.

### `SignalMetricsMonitor.m`

Converts vector spectrum/candidate outputs into scalars convenient for
Simulink displays and logs: spectrum peak, peak-to-global-noise SNR, selected RF
center in GHz, and selected bandwidth in MHz. Invalid candidates produce `NaN`
for the selected RF parameters.

### `PlatformDynamics3D.m`

Stateful target/receiver kinematics and guidance.

Key behavior:

- detection validity gates DOA steering;
- circular azimuth filtering handles the `-180/+180` boundary;
- pure pursuit, lead, and proportional modes are available;
- yaw/pitch commands are rate-limited;
- velocity is resolved into world X/Y/Z components;
- roll is a bounded visualization state based on turn rate;
- position freezes and `Arrived=true` inside the arrival radius.

## 4. Full closed-loop runners and figures

### `run_3d_doa_sim.m`

Direct MATLAB implementation of the complete closed loop. It constructs all
System objects, executes an explicit time loop, records structure `L`, updates
the optional live GUI, breaks on arrival, prints a summary, and calls
`plot_homing_results`.

### `run_3d_doa_sim_compat.m`

Small launcher that clears cached class definitions and then invokes
`run_3d_doa_sim.m`. Use it after replacing class files while MATLAB remains
open.

### `build_3d_doa_simulink.m`

Programmatically constructs `DOA_3D_Homing.slx`. It adds/configures all MATLAB
System blocks, delayed navigation feedback, truth/error monitoring, four live
scopes, numeric displays, arrival stop, and timeseries logging. Model callbacks
open the scopes at start and call `plot_simulink_results` at stop.

### `run_simulink_homing.m`

Shorter Simulink launcher. It clears classes, builds the model, and calls
`sim('DOA_3D_Homing')`. Unlike `START_HERE`, it does not run the verification
suite first.

### `plot_homing_results.m`

Common nine-panel English dashboard used by the MATLAB runner and the Simulink
postprocessor. It plots trajectory, range, detection/SNR, azimuth, elevation,
errors, selected source parameters, and attitude, then calculates detection
percentage and mean absolute valid-detection errors.

### `plot_simulink_results.m`

Reads Simulink `timeseries` logs from the base workspace, normalizes vector
shapes, constructs the common log structure, calls `plot_homing_results`, and
creates a separate final RF spectrum plot. It catches plotting/log errors so a
dashboard problem does not hide the simulation result.

### `doa_3d_gui.m`

Creates the dark live MATLAB GUI for the standalone runner. Graphics handles
are created once for efficient updates.

### `doa_3d_gui_update.m`

Updates existing GUI objects without recreating them: path, PFB spectrum, DOA
pseudospectrum, estimated/truth azimuth, and status text.

## 5. Standalone search-stage files

### `SyntheticFourChannelSource.m`

Creates a repeatable four-channel wideband test containing multiple targets,
multiple interferers, white receiver noise, and channel calibration errors. A
band is synthesized in the frequency domain, transformed to time, scaled by
specified SNR, and given a planar-array spatial phase. This test is independent
of the moving-platform source model.

### `run_search_chain_matlab.m`

Runs the standalone search branch for 30 frames, prints the selected candidate,
and plots final spectrum and CA-CFAR threshold. It tests PFB, spectrum, noise,
CFAR, clustering, and candidate selection without DOA navigation.

### `build_doa_search_model.m`

Builds `DOA_SearchStage_Executable.slx`, the Simulink equivalent of the search
test. It logs spectrum, frequency, detections, selected center/bandwidth, and
candidate validity.

## 6. RFSoC and HDL files

### `design_pfb_coefficients.m`

Builds a behavioral `dsp.Channelizer` with the requested bands, taps per band,
and stopband attenuation, extracts its transfer-function coefficients with
`tf`, and returns a row vector for the HDL DUT. It requires critical sampling
because the R2024a `dsphdl.Channelizer` path uses
`DecimationFactor == NumBands`.

### `ZU48DRChannelizer4.m`

Hardware-oriented four-lane wrapper containing four parallel
`dsphdl.Channelizer` instances. Inputs are four scalar complex fixed-point
samples plus `validIn`; outputs are four channel-bin vectors plus a combined
`validOut`. Identical coefficients preserve coherent phase between lanes.

This is the synthesizable front-end DUT. Source generation, floating-point
MUSIC, plotting, and navigation are testbench/behavioral functions and are not
inside this DUT.

### `build_rfsoc_hdl_frontend_model.m`

Builds `DOA_RFSoC_HDL_FrontEnd.slx` with four signed 16-bit complex inputs,
`validIn`, the `ZU48DRChannelizer4` DUT, and five outputs. When HDL Coder is
available, it configures Verilog generation and the ZU48DR device target.

### `generate_rfsoc_hdl_frontend.m`

Runs the HDL model builder, confirms HDL Coder availability, calls `makehdl` on
the channelizer DUT, and writes generated HDL below `hdl_prj/hdlsrc`.

## 7. Verification files

### `verify_r2024a_setup.m`

Performs fast environment and constructor checks:

- clears/reloads classes;
- shows every resolved `SourceModel3D` path;
- warns about duplicate class copies;
- checks `matlab.System` and `dsp.Channelizer`;
- constructs every custom behavioral object with name-value inputs;
- calls the deterministic DOA direction test;
- reports whether DSP HDL Toolbox is available.

### `verify_doa_direction.m`

Constructs synthetic high-SNR snapshots from the exact non-coplanar steering
manifold and checks two directions, including negative elevation. MUSIC must
recover both within one grid degree. This regression catches covariance
conjugation, azimuth sign, and elevation-sign errors before running the moving
platform.

### `verify_source_waveforms.m`

Instantiates `SourceModel3D` once for every documented modulation type and
checks that each mode produces a finite, nonzero `8192 x 4` coherent IQ frame.
It is called automatically by `verify_r2024a_setup`.

## 8. Files generated after commands run

These are intentionally generated on the user's MATLAB installation:

| Generated output | Command |
|---|---|
| `DOA_3D_Homing.slx` | `build_3d_doa_simulink` |
| `DOA_SearchStage_Executable.slx` | `build_doa_search_model` |
| `DOA_RFSoC_HDL_FrontEnd.slx` | `build_rfsoc_hdl_frontend_model` |
| `hdl_prj/hdlsrc/...` Verilog | `generate_rfsoc_hdl_frontend` |

Generating models locally ensures their block metadata matches MATLAB R2024a
and the toolboxes installed on that machine.
