# `run_3d_doa_sim` Standalone MATLAB Guide

> **V7 note:** Historical MUSIC examples inherited later in this guide are
> background only. The runnable script uses the realistic 2x2 receiver,
> calibrated WPI + bounded ML/GN + full-attitude unit-vector EKF. See
> `REALISTIC_DOA_ENGINEERING_GUIDE.md` for the authoritative algorithm.

This document explains the scripted MATLAB closed-loop implementation in
`run_3d_doa_sim.m`. The automatically generated Simulink model is documented
separately in `SIMULINK_MODEL_GUIDE.md`.

## 1. Run command

From the extracted project directory:

```matlab
clearvars
rehash path
verify_r2024a_setup
run_3d_doa_sim
```

If MATLAB cached an older class definition, use the compatibility launcher:

```matlab
run_3d_doa_sim_compat
```

## 2. What the script does

`run_3d_doa_sim.m` executes the entire RF search, DOA, error measurement, and
navigation loop directly with MATLAB System objects. It does not create or
require an `.slx` model.

The order is:

1. Clear variables/figures, refresh the path cache, and load `sim3d_params.m`.
2. Seed the random generator for repeatable waveforms and noise.
3. Construct every processing object with the master parameters.
4. Preallocate the result structure `L`.
5. For each navigation time step:
   - generate four coherent IQ channels;
   - channelize and calculate the spectrum;
   - estimate noise and run CA-CFAR;
   - cluster detected bins and select a source candidate;
   - select coherent spatial snapshots;
   - estimate azimuth/elevation;
   - calculate truth and DOA errors;
   - apply detection-gated guidance and move the receiver;
   - log all values and update the live GUI;
   - stop after arrival.
6. Trim unused preallocated rows.
7. Report arrival/final range and travelled distance.
8. Create the complete nine-panel results dashboard.

## 3. Object construction

The script instantiates these objects once before the loop:

| MATLAB variable | Class | Function |
|---|---|---|
| `source` | `SourceModel3D` | Waveform, propagation, array phase, noise |
| `channelizer` | `PFBFFTChannelizer4` | Four coherent PFB/FFT paths |
| `spectrumEstimator` | `SpectrumEstimator4` | Smoothed combined spectrum |
| `noiseEstimator` | `NoiseFloorEstimator1D` | Median noise floor |
| `cfar` | `CACFAR1D` | Adaptive detection threshold |
| `cluster` | `BinClusterEstimator` | Contiguous-bin clusters and bandwidth |
| `selector` | `CandidateSelector` | Bandwidth/SNR filtering and selection |
| `snapshotSelector` | `SnapshotDecimator4` | 256 coherent spatial snapshots |
| `doaEstimator` | `DOAEstimator4Ch` | MUSIC/MVDR/ESPRIT/phase DOA |
| `truthMonitor` | `TruthErrorMonitor3D` | True DOA and error calculations |
| `platform` | `PlatformDynamics3D` | Filtered detection-gated guidance |

All parameter values are passed by name. This is why each class contains an
explicit constructor:

```matlab
function obj=ClassName(varargin)
    setProperties(obj,nargin,varargin{:});
end
```

Without it, R2024a can forward name-value inputs to the internal superclass and
produce the `matlab.system.SystemInterface` constructor error.

## 4. Result structure `L`

The script preallocates one row for every possible time step. Important fields
are:

| Field | Units/shape | Meaning |
|---|---|---|
| `L.time` | seconds, `K x 1` | Navigation time |
| `L.pos` | metres, `K x 3` | Receiver world position |
| `L.yaw`, `L.pitch`, `L.roll` | degrees | Receiver attitude |
| `L.range` | metres | Distance to fixed source |
| `L.doaAz`, `L.doaEl` | degrees | Estimated body-frame DOA |
| `L.trueAz`, `L.trueEl` | degrees | Ground-truth body-frame DOA |
| `L.azError`, `L.elError` | degrees | Signed component errors |
| `L.angularError` | degrees | Exact total direction separation |
| `L.signalPeak_dB` | dB | Maximum current PFB spectrum value |
| `L.snr` | dB | Spectrum peak minus global noise floor |
| `L.detected` | logical | Candidate selector validity |
| `L.fc_Hz` | Hz | Selected baseband center offset |
| `L.bw_Hz` | Hz | Selected cluster bandwidth |

After the loop, every field is trimmed to `1:lastIndex`, so early arrival does
not leave zero-filled samples in the figures.

## 5. One iteration in detail

### 5.1 Current truth geometry

Before signal generation, the script calculates

```matlab
delta = P.Source.Position - platformPosition;
trueRange = norm(delta);
trueAz = wrapTo180(atan2d(delta(2),delta(1)) - platformYaw);
trueEl = atan2d(delta(3),norm(delta(1:2))) - platformPitch;
```

The implementation uses an equivalent `mod(...)-180` expression so it does not
require Mapping Toolbox.

### 5.2 Four-channel signal

```matlab
iq4 = source(platformPosition,platformYaw,platformPitch);
```

The output contains four phase-coherent channels. The common waveform has the
same random symbols on every channel; only propagation phase, channel errors,
and independent receiver noise differ.

### 5.3 Search branch

```matlab
subbands = channelizer(iq4);
[~,powerSum,power_dB,frequencyHz] = spectrumEstimator(subbands);
[~,~,noise_dB] = noiseEstimator(powerSum);
[detections,~,~] = cfar(powerSum);
[clusterCount,centers,bandwidths,~,~,peaks] = ...
    cluster(detections,powerSum,frequencyHz);
[valid,~,centerHz,bandwidthHz,~] = ...
    selector(clusterCount,centers,bandwidths,peaks,noise_dB);
```

This branch determines whether a source-like spectral candidate is present. It
does not estimate direction.

### 5.4 DOA branch

```matlab
snapshots = snapshotSelector(iq4);
[azimuth,elevation,doaSpectrum] = doaEstimator(snapshots);
```

This branch preserves complex inter-channel phase. MUSIC must never receive a
power spectrum because power discards the phase differences that encode
direction.

### 5.5 Truth and error

```matlab
[trueAz,trueEl,azError,elError,angularError] = truthMonitor( ...
    platformPosition,platformYaw,platformPitch,azimuth,elevation);
```

Azimuth error is circularly wrapped. Total angular error is computed from the
dot product of estimated and true unit vectors, so it remains meaningful near
azimuth wrapping and high elevation.

### 5.6 Navigation

```matlab
[platformPosition,platformYaw,platformPitch,platformRoll,range,arrivedNow] = ...
    platform(azimuth,elevation,valid,P.Source.Position);
```

The `valid` input is essential. The old behavior steered on scan-edge estimates
even when detection was false; that allowed noise to drive the receiver away
from the source. The corrected platform only accepts a new DOA command when
candidate selection is valid.

## 6. Core equations

### Propagation loss

Wavelength:

```text
lambda = c/fc.
```

One-metre free-space loss:

```text
FSPL_1m_dB = 20*log10(4*pi/lambda).
```

Range-dependent loss with exponent `n`:

```text
PL_dB = FSPL_1m_dB + 10*n*log10(range).
```

Received power:

```text
P_rx_W = 10^((PowerdBm - PL_dB - 30)/10).
```

### Thermal noise

```text
P_noise_W = k_B * 290 * Fs * 10^(NoiseFigure_dB/10).
```

Complex noise samples use variance `P_noise_W`, split equally between real and
imaginary components.

### Array manifold

For direction unit vector

```text
u = [cos(el)cos(az), cos(el)sin(az), sin(el)]
```

and antenna position `r_m`, channel phase is

```text
a_m = exp(-j*2*pi*fc*(r_m dot u)/c).
```

### MUSIC covariance

For `X` shaped as snapshots-by-channels:

```text
R = X^T*conj(X)/Ns.
```

This is then Hermitian-symmetrized before eigendecomposition.

### Guidance filter

For azimuth, circular innovation is

```text
innovation = wrap180(measuredAz - filteredAz)
filteredAz = wrap180(filteredAz + alpha*innovation).
```

Elevation uses an ordinary first-order update:

```text
filteredEl = filteredEl + alpha*(measuredEl-filteredEl).
```

## 7. Complete numerical example using defaults

### Initial range and DOA

```text
source position   = [500 300 200] m
receiver position = [0 0 50] m
delta             = [500 300 150] m
range             = 602.0797 m
azimuth           = 30.9638 deg
elevation         = 14.4264 deg.
```

### Path loss, received power, and noise

At 4 GHz:

```text
lambda       = 0.0749481 m
FSPL at 1 m  = 44.4890 dB
20log10(R)   = 55.5931 dB
total loss   = 100.0821 dB
received     = 40 - 100.0821 = -60.0821 dBm.
```

For `Fs = 2.048 GHz` and 3 dB noise figure:

```text
P_noise = 1.6361e-11 W = -77.8619 dBm
frame-wide SNR approximately 17.7798 dB.
```

The per-bin SNR depends on waveform bandwidth and PFB leakage, so the displayed
spectral peak SNR is not identical to this frame-wide value.

### CA-CFAR multiplier

With 24 training cells on each side, `N=48`. For `Pfa=1e-3`:

```text
alpha = 48*((1e-3)^(-1/48)-1) = 7.4295
threshold margin = 10log10(alpha) = 8.7096 dB.
```

### PFB and snapshot counts

```text
PFB bin width = 2.048e9/1024 = 2 MHz
PFB time rows = 8192/1024 = 8
DOA snapshots = 8192/32 = 256.
```

### First motion update

The requested initial yaw/pitch corrections are about `30.96/14.43` degrees.
Rate limits permit only `2 deg` yaw and `1 deg` pitch in `0.1 s`. With speed
25 m/s, the first displacement is approximately

```text
Delta_position = [2.4981 0.0872 0.0436] m.
```

With stable valid DOA, the default receiver reaches the 10 m arrival region in
about 24 seconds in the idealized kinematic check.

## 8. Live GUI behavior

When `P.GUI.Enable = true`, `doa_3d_gui` creates:

- a live 3D target/receiver trajectory;
- current PFB spectrum;
- current 2D DOA pseudospectrum;
- estimated versus true azimuth;
- status text containing time, position, range, DOA, truth, errors, attitude,
  SNR, and detection validity.

`P.GUI.UpdateRate` controls display refresh frequency, not signal-processing or
navigation calculations. Set

```matlab
P.GUI.Enable = false;
```

for a faster noninteractive batch run.

## 9. Selecting another DOA algorithm

Edit:

```matlab
P.DOA.Algorithm = 'MUSIC';
```

Supported values are:

- `MUSIC`: grid-search subspace method; default and most robust in this model;
- `MVDR`: grid-search minimum-variance response;
- `ESPRIT`: direct single-source X/Y/Z phase estimate;
- `PHASE_INTERFEROMETRY`: direct baseline cross-phase estimate.

MUSIC and MVDR return a full pseudospectrum for the live image. The direct
methods return a zero-filled spectrum because they do not scan a grid.

## 10. Changing the run without editing algorithms

Select `P.Source.ModulationType` in `sim3d_params.m`. The corresponding
`switch/case` in `source_modulation_profile.m` loads all waveform-specific
fields. Put temporary experiment overrides after the profile-loading block.
Examples:

```matlab
% New receiver start and source position
P.Platform.Position0 = [-200 100 20];
P.Source.Position = [700 500 250];

% Slower platform and tighter arrival sphere
P.Platform.Velocity = 15;
P.Nav.ArrivalRadius = 5;
P.Sim.StopTime = 120;

% Denser DOA grid
P.DOA.ScanResolution = 0.5;

% LFM waveform
P.Source.ModulationType = 'LFM';
% The following LFM values belong after profile loading:
P.Source.SweepStartHz = -30e6;
P.Source.SweepStopHz = 30e6;
P.Source.SweepTimeSeconds = 4e-6;
P.Source.BandwidthHz = 60e6;
P.Candidate.BW_MaxHz = 80e6;
```

A smaller scan resolution improves angular quantization but increases MUSIC or
MVDR computation approximately in proportion to the number of scan points.

## 11. Difference from the Simulink run

| Standalone MATLAB | Simulink |
|---|---|
| Explicit `for` loop | Signal-flow model with feedback delays |
| Objects called directly | MATLAB System blocks |
| Results stored in structure `L` | Results stored in `timeseries` variables |
| Live custom MATLAB GUI | Four Scope blocks and numeric Display blocks |
| Script breaks immediately on arrival | Stop Simulation block ends on arrival |
| Calls `plot_homing_results(L,P)` | Stop callback calls `plot_simulink_results` |

Both implementations use the same classes, equations, parameters, source
waveforms, and final nine-panel dashboard.
