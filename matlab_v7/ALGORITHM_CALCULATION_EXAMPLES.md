# Algorithm and Calculation Examples

> **V7 note:** The initial geometry/path-loss/PFB calculations remain useful,
> but later X/Y/Z and grid-MUSIC examples are historical. V7 uses the square
> 2x2 WPI/ML/GN equations in `REALISTIC_DOA_ENGINEERING_GUIDE.md`.

This document works through the principal calculations using the default
values in `sim3d_params.m`.

## 1. Initial 3D geometry

```text
source   = [500 300 200] m
receiver = [0 0 50] m
delta    = [500 300 150] m.
```

Range:

```text
R = sqrt(500^2 + 300^2 + 150^2)
  = sqrt(362500)
  = 602.0797 m.
```

World/body azimuth at zero initial yaw:

```text
az = atan2(300,500) = 30.9638 deg.
```

Elevation at zero initial pitch:

```text
horizontal range = sqrt(500^2 + 300^2) = 583.0952 m
el = atan2(150,583.0952) = 14.4264 deg.
```

If platform yaw were 10 degrees, pitch 3 degrees and roll 0 degrees, V7 rotates
the world unit vector with the complete transpose DCM. The result is approximately

```text
body az = 20.72 deg
body el = 11.62 deg.
```

For nonzero roll the result is not obtained by subtracting Euler angles; use
`body_to_navigation_dcm.m` exactly as the source, truth monitor and EKF do.

## 2. Wavelength and spatial sampling

At 4 GHz:

```text
lambda = c/fc
       = 299792458/4e9
       = 0.0749481 m.
```

The default X/Y/Z baselines are 0.025 m:

```text
d/lambda = 0.025/0.0749481 = 0.3336 wavelengths.
```

This is below half a wavelength and therefore avoids ordinary grating-lobe
ambiguity over the intended field of view.

At a new center frequency, the conservative baseline check is:

```matlab
lambda = P.c/P.Source.CenterFreqHz;
maxSpacing = max([P.Antenna.dx P.Antenna.dy P.Antenna.dz]);
fprintf('Maximum spacing = %.3f wavelengths\n',maxSpacing/lambda)
```

## 3. Direction cosines, delay, and phase

For the initial direction:

```text
u_x = 500/602.0797 = 0.830455
u_y = 300/602.0797 = 0.498273
u_z = 150/602.0797 = 0.249136.
```

For a 25 mm X baseline:

```text
tau_x = d_x*u_x/c
      = 0.025*0.830455/299792458
      = 6.92525e-11 s = 69.2525 ps.
```

The steering phase is

```text
phi_x = -2*pi*fc*tau_x
      = -1.74050 rad
      = -99.7236 deg.
```

The Y and Z baselines similarly give

```text
phi_y = -59.8341 deg
phi_z = -29.9171 deg.
```

The reference element has zero relative delay. These three independent phases
allow the non-coplanar four-channel receiver to estimate signed elevation.

## 4. Free-space path loss and received power

The one-metre free-space loss is

```text
FSPL_1m = 20*log10(4*pi/lambda)
        = 44.4890 dB.
```

With path-loss exponent `n=2` and range `R=602.0797 m`:

```text
PL = FSPL_1m + 10*n*log10(R)
   = 44.4890 + 20*log10(602.0797)
   = 100.0821 dB.
```

For source power 40 dBm:

```text
P_rx = 40 - 100.0821 = -60.0821 dBm
     = 9.814e-10 W approximately.
```

Changing path-loss exponent to 2.5 would change the range-dependent term to
`25*log10(R)`, substantially reducing long-range SNR.

## 5. Integrated thermal noise and SNR

The source model uses

```text
P_n = k_B*T*Fs*F,
```

where `T=290 K` and `F=10^(NF_dB/10)`. For `Fs=2.048e9 Hz` and `NF=3 dB`:

```text
P_n = 1.380649e-23 * 290 * 2.048e9 * 10^(3/10)
    = 1.6361e-11 W
    = -77.8619 dBm.
```

The approximate frame-wide SNR is

```text
SNR = -60.0821 - (-77.8619) = 17.7798 dB.
```

The displayed `Peak SNR` is a spectral value: maximum PFB-bin dB minus global
median-bin dB. A wide waveform distributes power across several bins, so it is
not numerically identical to frame-wide SNR.

## 6. Frame, PFB, and DOA snapshot dimensions

Frame duration:

```text
T_frame = FrameLength/Fs
        = 8192/2.048e9
        = 4 us.
```

PFB channel spacing:

```text
Delta_f = Fs/NumBands
        = 2.048e9/1024
        = 2 MHz.
```

PFB time rows under critical decimation:

```text
8192/1024 = 8 rows per frame.
```

DOA snapshot count:

```text
8192/SnapshotStride = 8192/32 = 256 snapshots.
```

The frequency-axis expression makes MATLAB index 513 the zero-offset bin:

```text
frequencyHz = ((0:1023)-512)*2 MHz.
```

A baseband source at `+30 MHz` is 15 bins above zero and appears near MATLAB
index `513+15 = 528`. Its displayed RF frequency is

```text
4.000 GHz + 0.030 GHz = 4.030 GHz.
```

## 7. Spectrum smoothing

With `AverageAlpha=0.25`, a bin whose previous state was 4 units and whose
current power is 12 units becomes

```text
P_new = 0.75*4 + 0.25*12 = 6 units.
```

The next frame with the same current power gives

```text
P_new = 0.75*6 + 0.25*12 = 7.5 units.
```

Smaller alpha gives a smoother but slower spectrum. Larger alpha follows fast
changes but has more variance.

## 8. CA-CFAR threshold

The default has 24 training cells on each side:

```text
N = 2*24 = 48.
```

For `Pfa=1e-3`:

```text
alpha = N*(Pfa^(-1/N)-1)
      = 48*((1e-3)^(-1/48)-1)
      = 7.4295.
```

This is an 8.7096 dB multiplier. If the mean training-cell power around a cell
is `2e-12 W`, threshold is

```text
T = 7.4295*2e-12 = 1.4859e-11 W.
```

A cell at `2.0e-11 W` is detected; a cell at `1.0e-11 W` is not.

Increasing `Pfa` lowers the multiplier and increases both sensitivity and
false alarms. Decreasing `Pfa` does the opposite.

## 9. Cluster center, bandwidth, and selection

Suppose bins at offsets 8, 10, and 12 MHz form a three-bin cluster with powers
1, 3, and 2 units. The power-weighted center is

```text
fc = (8*1 + 10*3 + 12*2)/(1+3+2)
   = 62/6
   = 10.333 MHz.
```

At 2 MHz/bin, bandwidth is

```text
BW = 3*2 MHz = 6 MHz.
```

If peak is `-50 dB` and global noise is `-70 dB`, candidate SNR is 20 dB. Its
selection score is

```text
score = 20 - 0.05*abs(6-30)
      = 18.8.
```

The 30 MHz term is a soft preference, not a hard requirement. Hard acceptance
comes from `BW_MinHz`, `BW_MaxHz`, and `MinCandidateSNRdB`.

## 10. MUSIC covariance and pseudospectrum

Let `X` contain `Ns=256` rows of simultaneous antenna samples and four columns.
The project uses

```text
R = X^T*conj(X)/256.
```

For a noise-free single source, `X = s*a^T`, therefore

```text
X^T*conj(X) = a*(s^T*conj(s))*a^H,
```

so the dominant eigenvector follows steering vector `a`. This matches
`SourceModel3D` and the MUSIC scan. The alternative `X^H*X` would follow
`conj(a)` for this storage convention and mirror direction.

After eigenvalue sorting, the three smallest-eigenvalue vectors form `E_n`.
For each grid direction:

```text
P(az,el) = 1/abs(a^H*E_n*E_n^H*a).
```

The result is normalized so its largest value is 0 dB.

## 11. DOA component and total error

Suppose truth is

```text
[az el] = [30.9638 14.4264] deg
```

and MUSIC returns

```text
[az el] = [32 14] deg.
```

Then

```text
azimuth error   = +1.0362 deg
elevation error = -0.4264 deg.
```

The exact unit-vector separation is about

```text
angular error = 1.0913 deg.
```

It is not generally equal to `sqrt(azError^2+elError^2)`, especially at high
elevation, because azimuth arcs shrink by `cos(elevation)`.

Azimuth wrapping example:

```text
truth = +179 deg, estimate = -179 deg
raw difference = -358 deg
wrapped error = +2 deg.
```

## 12. Navigation filter and rate limiting

With filtered azimuth 31 degrees, new measured azimuth 28 degrees, and
`alpha=0.3`:

```text
innovation = wrap180(28-31) = -3 deg
new filtered azimuth = 31 + 0.3*(-3) = 30.1 deg.
```

At the first default update, the pure-pursuit command is approximately
`30.96 deg` azimuth and `14.43 deg` elevation. With `Dt=0.1 s`:

```text
unlimited yaw rate = 30.96/0.1 = 309.6 deg/s
limited yaw rate   = 20 deg/s
yaw change         = 2 deg.

unlimited pitch rate = 14.43/0.1 = 144.3 deg/s
limited pitch rate   = 10 deg/s
pitch change          = 1 deg.
```

At yaw 2 degrees, pitch 1 degree, and velocity 25 m/s:

```text
velocity approximately [24.9810 0.8724 0.4363] m/s
displacement in 0.1 s [2.4981 0.0872 0.0436] m.
```

## 13. Arrival and minimum ideal travel time

The straight-line distance from initial receiver to the edge of the 10 m
arrival sphere is approximately

```text
602.08 - 10 = 592.08 m.
```

At 25 m/s, the ideal lower-bound travel time is

```text
592.08/25 = 23.68 s.
```

The closed-loop result is expected to be close to 24 seconds when detections
are stable. Turning, filtering, estimation error, and invalid detections can
increase it.

## 14. LFM, NLFM, and PM examples

For default `B=30 MHz` and frame duration `T=4 us`, LFM slope is

```text
k = B/T = 30e6/4e-6 = 7.5e12 Hz/s.
```

Ideal LFM range resolution, if matched-filter ranging is later added, is

```text
c/(2B) = 299792458/(60e6) = 4.9965 m.
```

For PM with `beta=2.5` and `f_m=2 MHz`, the Carson-style bandwidth estimate is

```text
B approximately 2*(beta+1)*f_m = 14 MHz.
```

For NLFM with shape `a=2` at normalized time `u=0.5`:

```text
f_i = (B/2)*(u+a*u^3)/(1+a)
    = 15 MHz*(0.5+2*0.125)/3
    = 3.75 MHz.
```

The corresponding LFM instantaneous frequency at `u=0.5` would be `7.5 MHz`,
showing how the cubic law changes sweep dwell distribution.
