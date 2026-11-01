# RF Source, Waveform, and Parameter Guide

> **V6 array note:** Waveform sections remain current. Any inherited reference
> to an X/Y/Z non-coplanar array is superseded by the nose-mounted square 2x2
> Y-Z geometry in `sim3d_params.m` and `ACCURACY_AND_HDL_GUIDE.md`.

This guide applies to the moving-source-homing demonstrations built from
`SourceModel3D.m`, `sim3d_params.m`, `run_3d_doa_sim.m`, and
`build_3d_doa_simulink.m`.

## 1. How modulation-specific parameters are selected

Select the waveform near the top of `sim3d_params.m`:

```matlab
P.Source.ModulationType = 'LFM';
```

Later in that file, this call fetches the complete selected profile:

```matlab
waveform = source_modulation_profile(P.Source.ModulationType);
```

`source_modulation_profile.m` contains the requested `switch/case`. For
example, its LFM case is conceptually:

```matlab
case {'LFM','CHIRP'}
    waveform.SweepStartHz = -15e6;
    waveform.SweepStopHz = 15e6;
    waveform.SweepTimeSeconds = 4e-6;
    waveform.BandwidthHz = 30e6;
```

The PM case instead loads `ModulationToneHz`, `PMIndexRad`, and its occupied
bandwidth. Digital cases load symbol/chip rate and bandwidth. Every case returns
a complete fixed interface so `SourceModel3D` remains compatible with the
Simulink MATLAB System block.

There are two supported ways to customize values:

1. Edit the appropriate case in `source_modulation_profile.m` to create a
   reusable waveform profile.
2. Put one-experiment overrides in the clearly marked optional block of
   `sim3d_params.m`, after the profile has been loaded.

Both the MATLAB runner and Simulink builder then read the same selected values.

After changing a source parameter, use one of these commands:

```matlab
% Standalone MATLAB closed loop
run_3d_doa_sim

% Rebuild and run the Simulink closed loop
build_3d_doa_simulink
sim('DOA_3D_Homing')

% Or perform verification, build, and simulation together
START_HERE
```

Always rebuild the Simulink model after changing a nontunable System-object
parameter. `build_3d_doa_simulink` deletes the previously generated model and
creates a new one with the current values.

## 2. Supported modulation names

`P.Source.ModulationType` is case-insensitive. The following names are
implemented directly in `SourceModel3D`.

| ModulationType | Meaning | Principal controls |
|---|---|---|
| `CW` | Unmodulated complex carrier at the search-center frequency | `CenterFreqHz`, `PowerdBm` |
| `BPSK` | Binary phase-shift keying | `ChipRateHz`, `BandwidthHz` |
| `QPSK` | Quadrature phase-shift keying | `ChipRateHz`, `BandwidthHz` |
| `8PSK` | Eight-state PSK | `ChipRateHz`, `BandwidthHz` |
| `QAM16` | Normalized 16-QAM | `ChipRateHz`, `BandwidthHz` |
| `QAM64` | Normalized 64-QAM | `ChipRateHz`, `BandwidthHz` |
| `LFM` or `CHIRP` | Linear-frequency-modulated sweep | `BandwidthHz`, `FrameLength`, `Fs` |
| `NLFM` | Cubic nonlinear-frequency-modulated sweep | `BandwidthHz`, `NLFMShape` |
| `PM` | Sinusoidal phase modulation | `ModulationToneHz`, `PMIndexRad`, `BandwidthHz` |
| `FM` | Sinusoidal frequency modulation | `ModulationToneHz`, `FMDeviationHz`, `BandwidthHz` |
| `AM` | Sinusoidal amplitude modulation | `ModulationToneHz`, `AMDepth`, `BandwidthHz` |
| `FSK` | Binary frequency-shift keying | `ChipRateHz`, `FSKDeviationHz`, `BandwidthHz` |
| `PULSED_LFM` or `LFM_PULSE` | Repeated gated LFM pulses | `BandwidthHz`, `PulseWidthSeconds`, `PRFHz` |
| `NOISE` or `WIDEBAND_NOISE` | Band-limited complex Gaussian waveform | `BandwidthHz` |

An unsupported name generates a clear `DOA3D:ModulationType` error. It is not
silently replaced by another waveform.

## 3. Source parameters

### Geometry and RF power

| Parameter | Default | Use |
|---|---:|---|
| `P.Source.Position` | `[500 300 200]` m | Fixed world-coordinate RF-source position `[X Y Z]` |
| `P.Source.CenterFreqHz` | `4.0e9` Hz | RF center used for wavelength, path loss, array phase, and display |
| `P.Source.BandwidthHz` | `30e6` Hz | Baseband spectral limit and nominal occupied bandwidth |
| `P.Source.PowerdBm` | `40` dBm | Average transmitted power used by the propagation model |
| `P.Source.ModulationType` | `'QAM16'` | Selects the waveform generator |

The model is a complex-baseband simulation. A 4 GHz source is not sampled as a
real 4 GHz sinusoid at 2.048 GS/s. Instead, the complex waveform is centered at
zero baseband frequency, while `CenterFreqHz` supplies the physical RF
wavelength and converts a selected baseband bin back to RF frequency.

### Digital modulation

| Parameter | Default | Use |
|---|---:|---|
| `P.Source.ChipRateHz` | `20e6` symbols/s | Symbol/chip update rate for BPSK, QPSK, 8PSK, QAM, and FSK |

The approximate number of symbols generated in one frame is

```text
ceil(FrameLength * ChipRateHz / Fs)
```

With the defaults, this is

```text
ceil(8192 * 20e6 / 2.048e9) = 80 symbols per frame.
```

The rectangular symbol sequence is subsequently limited to
`+/-BandwidthHz/2` in the frequency domain.

### PM, FM, and AM

| Parameter | Default | Use |
|---|---:|---|
| `P.Source.ModulationToneHz` | `2e6` Hz | Sinusoidal message frequency for PM, FM, and AM |
| `P.Source.PMIndexRad` | `2.5` rad | Peak PM phase deviation |
| `P.Source.FMDeviationHz` | `10e6` Hz | Peak FM frequency deviation |
| `P.Source.AMDepth` | `0.8` | AM depth, automatically limited to the interval `[0,1]` |

For PM, the complex envelope is

```text
s(t) = exp(j * beta_p * sin(2*pi*f_m*t))
```

where `beta_p = PMIndexRad` and `f_m = ModulationToneHz`.

For FM, the phase-modulation index is calculated from

```text
beta_f = FMDeviationHz / ModulationToneHz
s(t) = exp(j * beta_f * sin(2*pi*f_m*t)).
```

For AM, the complex-baseband amplitude is

```text
s(t) = 1 + AMDepth*cos(2*pi*f_m*t).
```

The final signal is normalized to unit average power before path loss and
`PowerdBm` are applied.

### LFM and NLFM

| Parameter | Default | Use |
|---|---:|---|
| `P.Source.SweepStartHz` | `-15e6` Hz | LFM/NLFM starting baseband frequency |
| `P.Source.SweepStopHz` | `15e6` Hz | LFM/NLFM ending baseband frequency |
| `P.Source.SweepTimeSeconds` | `4e-6` s | Duration before the sweep repeats |
| `P.Source.BandwidthHz` | `30e6` Hz | Common final band limit; must contain the sweep |
| `P.Source.NLFMShape` | `2.0` | Strength of the cubic NLFM frequency law; `0` approaches LFM |

For sweep time `T = SweepTimeSeconds`, the implementation uses

```text
f_start = SweepStartHz
k = (SweepStopHz-SweepStartHz)/T
s(t) = exp(j*2*pi*(f_start*t + 0.5*k*t^2)).
```

For NLFM, normalized time is `u = 2t/T - 1`, and instantaneous frequency is

```text
f_i(t) = (B/2) * (u + a*u^3)/(1+a),
```

where the half-span and center are obtained from `SweepStartHz` and
`SweepStopHz`, and `a = NLFMShape`. Phase is obtained by discrete integration
of instantaneous frequency.

This NLFM law is a controllable cubic example, not a specific radar sidelobe-
optimized design. To reproduce a published NLFM law, replace the
`instantaneousFrequency` expression in the `case 'NLFM'` section while keeping
its output between approximately `-BandwidthHz/2` and `+BandwidthHz/2`.

### FSK and pulsed LFM

| Parameter | Default | Use |
|---|---:|---|
| `P.Source.FSKDeviationHz` | `7.5e6` Hz | Binary FSK tones are placed at `+/-FSKDeviationHz` |
| `P.Source.PulseWidthSeconds` | `1e-6` s | Active duration of each pulsed-LFM waveform |
| `P.Source.PRFHz` | `250e3` Hz | Pulse repetition frequency |

Pulsed-LFM duty cycle is

```text
duty cycle = PulseWidthSeconds * PRFHz.
```

With the defaults, it is `1e-6 * 250e3 = 0.25`, or 25 percent. The generated
waveform is normalized to unit average frame power, so `PowerdBm` represents
average transmitted power. Peak on-pulse power is consequently higher when the
duty cycle is lower.

## 4. Ready-to-use waveform examples

### Example A: LFM source

```matlab
% Select this at the top of sim3d_params.m:
P.Source.ModulationType = 'LFM';

% Put these in the OPTIONAL EXPERIMENT OVERRIDES block after profile loading:
P.Source.SweepStartHz = -40e6;
P.Source.SweepStopHz = 40e6;
P.Source.SweepTimeSeconds = 4e-6;
P.Source.BandwidthHz = 80e6;
```

With an 80 MHz sweep, the ideal radar range-resolution expression is

```text
delta_R = c/(2B) = 299792458/(2*80e6) = 1.87 m.
```

The current project uses DOA homing and path-loss range truth; it does not yet
perform matched-filter delay ranging. The equation describes what an added LFM
matched-filter range channel could theoretically resolve.

For a 130 MHz example, use `SweepStartHz=-65e6`, `SweepStopHz=65e6`, and
`BandwidthHz=130e6`. Because total source power is then distributed across
many more 2 MHz PFB bins, increase `PowerdBm` if candidate detection becomes
intermittent. `P.Candidate.BW_MaxHz` is calculated automatically as at least
`1.25*BandwidthHz`.

### Example B: NLFM source

```matlab
P.Source.ModulationType = 'NLFM';
% After profile loading:
P.Source.SweepStartHz = -25e6;
P.Source.SweepStopHz = 25e6;
P.Source.SweepTimeSeconds = 4e-6;
P.Source.BandwidthHz = 50e6;
P.Source.NLFMShape = 3.0;
```

Increasing `NLFMShape` spends more sweep time around the middle of the band and
changes the spectral weighting. Use `0` for an almost linear sweep, then try
`1`, `2`, and `4` while viewing the final PFB spectrum.

### Example C: PM source

```matlab
P.Source.ModulationType = 'PM';
% After profile loading:
P.Source.ModulationToneHz = 2e6;
P.Source.PMIndexRad = 2.5;
P.Source.BandwidthHz = 20e6;
```

A useful PM bandwidth estimate is Carson's-rule form

```text
B approximately 2*(beta_p + 1)*f_m
  = 2*(2.5 + 1)*2 MHz
  = 14 MHz.
```

Therefore a 20 MHz spectral limit retains the principal PM sidebands.

### Example D: FM source

```matlab
P.Source.ModulationType = 'FM';
% After profile loading:
P.Source.ModulationToneHz = 1e6;
P.Source.FMDeviationHz = 8e6;
P.Source.BandwidthHz = 24e6;
```

Carson's rule gives

```text
B approximately 2*(Delta_f + f_m)
  = 2*(8 + 1) MHz
  = 18 MHz.
```

### Example E: pulsed LFM

```matlab
P.Source.ModulationType = 'PULSED_LFM';
% After profile loading:
P.Source.SweepStartHz = -50e6;
P.Source.SweepStopHz = 50e6;
P.Source.BandwidthHz = 100e6;
P.Source.PulseWidthSeconds = 1.5e-6;
P.Source.PRFHz = 200e3;
P.Source.PowerdBm = 43;
```

The pulse period is `1/200 kHz = 5 us`, and the duty cycle is
`1.5 us/5 us = 30 percent`.

### Example F: move the source and change RF power

```matlab
P.Source.Position = [900 -250 350];
P.Source.CenterFreqHz = 3.5e9;
P.Source.PowerdBm = 46;
P.Source.ModulationType = 'QPSK';
P.Source.ChipRateHz = 12e6;
P.Source.BandwidthHz = 20e6;
```

After changing center frequency, verify that the physical baselines remain no
larger than approximately half a wavelength:

```matlab
lambda = P.c/P.Source.CenterFreqHz;
assert(max([P.Antenna.dx P.Antenna.dy P.Antenna.dz]) <= lambda/2)
```

This prevents spatial aliasing over a wide field of view.

## 5. Changing detection and navigation behavior

The source waveform is only one part of the closed loop. If a weaker or wider
source is not selected reliably, adjust these parameters carefully:

```matlab
P.CFAR.Pfa = 1e-3;              % Larger value: more sensitive, more false alarms
P.Candidate.MinSNRdB = 3;       % Lower value: accepts weaker clusters
P.Candidate.BW_MinHz = 0.5e6;   % Minimum accepted occupied bandwidth
P.Candidate.BW_MaxHz = 40e6;    % Must include the intended source bandwidth
P.Source.PowerdBm = 40;         % Higher value raises simulated received SNR
```

For an 80 MHz LFM signal, for example, increase
`P.Candidate.BW_MaxHz` above 80 MHz; otherwise the candidate selector may reject
the correct source even though CFAR detects it.

Navigation controls are independent:

```matlab
P.Platform.Velocity = 25;       % m/s
P.Platform.MaxTurnRate = 20;    % deg/s
P.Platform.MaxClimbRate = 10;   % deg/s
P.Platform.NavFilterAlpha = 0.3;
P.Nav.GuidanceLaw = 'pure_pursuit';
P.Nav.ArrivalRadius = 10;       % m
```

The platform only uses a DOA command when candidate detection is valid. During
an invalid update it holds its present heading and pitch rather than steering
on an untrusted estimate.

## 6. Adding another waveform type

To add a waveform not listed above:

1. Add a case and its default parameters to `source_modulation_profile.m`.
2. Open `SourceModel3D.m` and find the `switch modulation` statement.
3. Add another `case` that returns an `N`-by-1 real or complex baseband vector.
4. Add any required nontunable property near the top of `SourceModel3D`.
5. Pass a new property in both `run_3d_doa_sim.m` and
   `build_3d_doa_simulink.m`.
6. Add the waveform name to `verify_source_waveforms.m`.
7. Re-run `verify_r2024a_setup`, then rebuild the Simulink model.

Example skeleton:

```matlab
case 'MY_WAVEFORM'
    % time is already an N-by-1 vector in seconds.
    phase = ...;
    signal = exp(1j*phase);
```

After the switch, the common code applies the configured bandwidth limit and
normalizes average power. This keeps path loss, noise, and `PowerdBm` handling
consistent across waveform types.

## 7. Common parameter mistakes

- `BandwidthHz` must be below `Fs`; leave transition margin below `Fs`.
- `Candidate.BW_MaxHz` must be at least as large as the waveform that should be
  accepted.
- `CenterFreqHz` changes wavelength and array phase, not the complex-baseband
  sample rate.
- Increasing `Fs` increases integrated thermal noise in `SourceModel3D`.
- The Y-Z planar square resolves signed azimuth/elevation direction cosines but
  has a front/back mirror. V7 uses the known nose-forward hemisphere; use a
  non-coplanar aperture or another cue if mission geometry cannot supply it.
- If source geometry can place the source behind the platform, enlarge
  `P.DOA.AzScanRange` or modify the platform initial heading.
- If MATLAB locked an older System-object definition, restart MATLAB once and
  run `rehash path`; global `clear classes` causes unrelated toolbox warnings.
