function verify_phase_interferometry_2x2()
%VERIFY_PHASE_INTERFEROMETRY_2X2 Time-domain verification of the V07 estimator.
%
% Complements scripts/phase_interf_verify.py (which starts from ideal spectra).
% This check goes through the real receiver chain that the FPGA sees:
%
%   frequency-domain emitter  ->  IFFT  ->  16-bit quantisation
%      ->  raised-cosine window  ->  FFT  ->  PhaseInterferometryEstimator
%
% and it also reproduces the hardware fixed point (Q3.17 calibrated integers,
% int64 accumulators, integer CORDIC) with FixedPointMode = true.
%
% Cases
%   1  CORDIC bit-exactness vs atan2 (MATLAB twin of the HDL)
%   2  narrowband 50 MHz: coherent WPI vs the diagnostic phase-slope fit
%   3  wideband 2 GHz: same comparison (the slope estimator stays worse)
%   4  hardware fixed point must match the float reference
%   5  geometry: 50 mm spacing at 3.75 GHz is ambiguous, 25 mm is not
%
% Expected outcome: cases 1-4 pass; case 5 passes by *failing* to estimate with
% 50 mm, which is the whole point of the V07 geometry decision.
%
% See also PhaseInterferometryEstimator, phase_from_cordic_q13,
% V07_PHASE_INTERFEROMETRY.md.

fprintf('\n=== V07 2x2 PHASE-INTERFEROMETRY VERIFICATION ===\n');

rngState = rng;
cleanup = onCleanup(@() rng(rngState));
rng(20261106,'twister');

settings.SampleRateHz = 2e9;
settings.CenterFrequencyHz = 3e9;
settings.Nfft = 16384;
settings.Trials = 24;
settings.Azimuth_deg = 12.5;
settings.Elevation_deg = -8.3;
settings.NarrowbandHz = 50e6;
settings.WidebandHz = 2e9;
settings.PerBinSnr_dB = 20;

failures = 0;

% ---------------------------------------------------------------- case 1 ----
fprintf('\nCASE 1  integer CORDIC vs atan2 (HDL twin)\n');
worstLsb = 0;
for k = 1:4000
    phi = -pi + 2*pi*k/4000;
    magnitude = 2^(mod(k,20));
    y = round(sin(phi)*magnitude);
    x = round(cos(phi)*magnitude);
    got = double(phase_from_cordic_q13(y,x))/8192;
    lsb = abs(got - atan2(y,x))*8192;
    worstLsb = max(worstLsb, lsb);
end
fprintf('  worst error %.2f LSB of Q3.13 (limit 2)\n', worstLsb);
if worstLsb > 2
    fprintf('  FAIL integer CORDIC\n');
    failures = failures + 1;
else
    fprintf('  PASS integer CORDIC within 2 LSB\n');
end

% ---------------------------------------------------------------- case 2 ----
fprintf('\nCASE 2  narrowband 50 MHz emitter at 3.500 GHz, d = 25 mm, %g dB/bin\n', ...
    settings.PerBinSnr_dB);
positions = array2x2(0.025);
[errorWpi, errorSlope] = runMonteCarlo(settings, positions, ...
    settings.NarrowbandHz, 500e6, 10*settings.Trials, false);
fprintf('  coherent WPI            RMSE %.3f deg\n', errorWpi);
fprintf('  phase-slope diagnostic  RMSE %.3f deg\n', errorSlope);
if errorWpi < 0.5
    fprintf('  PASS WPI meets the 0.5 deg target\n');
else
    fprintf('  FAIL WPI missed the 0.5 deg target\n');
    failures = failures + 1;
end
if errorSlope > 5*errorWpi
    fprintf('  PASS slope fit is far worse, as V07 predicts\n');
else
    fprintf('  FAIL slope-fit behaviour is not as predicted\n');
    failures = failures + 1;
end

% ---------------------------------------------------------------- case 3 ----
fprintf('\nCASE 3  wideband 2 GHz emitter, d = 25 mm\n');
[errorWpiWide, errorSlopeWide] = runMonteCarlo(settings, positions, ...
    settings.WidebandHz, 0, round(settings.Trials/2), false);
fprintf('  coherent WPI            RMSE %.3f deg\n', errorWpiWide);
fprintf('  phase-slope diagnostic  RMSE %.3f deg\n', errorSlopeWide);
if errorWpiWide < 0.5 && errorSlopeWide > errorWpiWide
    fprintf('  PASS bandwidth alone does not beat coherent phase\n');
else
    fprintf('  FAIL wideband comparison is not as predicted\n');
    failures = failures + 1;
end

% ---------------------------------------------------------------- case 4 ----
fprintf('\nCASE 4  hardware fixed point vs floating reference\n');
[errorFixed] = runMonteCarlo(settings, positions, settings.NarrowbandHz, ...
    500e6, round(settings.Trials/2), true);
fprintf('  fixed-point WPI         RMSE %.3f deg (float %.3f deg)\n', ...
    errorFixed, errorWpi);
if abs(errorFixed - errorWpi) < 0.15
    fprintf('  PASS fixed point reproduces the float reference\n');
else
    fprintf('  FAIL fixed point diverges from the float reference\n');
    failures = failures + 1;
end

% ---------------------------------------------------------------- case 5 ----
fprintf('\nCASE 5  geometry ambiguity at 3.750 GHz, azimuth 55 deg\n');
[errorWide, ~] = runMonteCarlo(settings, array2x2(0.050), settings.NarrowbandHz, ...
    750e6, round(settings.Trials/2), false, 55, 0);
[errorNarrow, ~] = runMonteCarlo(settings, array2x2(0.025), settings.NarrowbandHz, ...
    750e6, round(settings.Trials/2), false, 55, 0);
fprintf('  50 mm spacing           RMSE %.1f deg\n', errorWide);
fprintf('  25 mm spacing           RMSE %.3f deg\n', errorNarrow);
if errorWide > 10 && errorNarrow < 1
    fprintf('  PASS 50 mm is ambiguous where 25 mm is not\n');
else
    fprintf('  FAIL geometry expectation not reproduced\n');
    failures = failures + 1;
end

% --------------------------------------------------------------- summary ----
fprintf('\n');
if failures == 0
    fprintf('V07 PHASE INTERFEROMETRY RESULT=PASS\n');
else
    fprintf('V07 PHASE INTERFEROMETRY RESULT=FAIL (%d check(s))\n', failures);
end
end

% =============================================================================
function positions = array2x2(spacing)
half = spacing/2;
positions = [0 -half -half; 0 half -half; 0 -half half; 0 half half];
end

% =============================================================================
function [errorMean, errorSlope] = runMonteCarlo(settings, positions, ...
        occupiedHz, offsetHz, trials, fixedPoint, azimuth_deg, elevation_deg)
if nargin < 7, azimuth_deg = settings.Azimuth_deg; end
if nargin < 8, elevation_deg = settings.Elevation_deg; end

estimator = PhaseInterferometryEstimator( ...
    'SampleRateHz', settings.SampleRateHz, ...
    'CenterFrequencyHz', settings.CenterFrequencyHz, ...
    'ArrayPositions', positions, ...
    'FixedPointMode', fixedPoint, ...
    'EnableSlopeDiagnostic', true, ...
    'MaxEmitters', 1);
cleanup = onCleanup(@() release(estimator));

errors = nan(trials,2);
for trial = 1:trials
    spectra = simulateSpectra(settings, positions, occupiedHz, offsetHz, ...
        azimuth_deg, elevation_deg);
    detections = estimator(spectra);
    if isempty(detections) || ~isfinite(detections(1).Azimuth_deg)
        errors(trial,:) = [180 180];
        continue;
    end
    errors(trial,1) = hypot(detections(1).Azimuth_deg - azimuth_deg, ...
                            detections(1).Elevation_deg - elevation_deg);
    if isfinite(detections(1).SlopeAzimuth_deg)
        errors(trial,2) = hypot(detections(1).SlopeAzimuth_deg - azimuth_deg, ...
                                detections(1).SlopeElevation_deg - elevation_deg);
    end
end
errorMean = sqrt(mean(errors(:,1).^2));
errorSlope = sqrt(mean(errors(isfinite(errors(:,2)),2).^2));
if ~isfinite(errorSlope), errorSlope = NaN; end
end

% =============================================================================
function spectra = simulateSpectra(settings, positions, occupiedHz, offsetHz, ...
        azimuth_deg, elevation_deg)
% Time-domain chain: emitter spectrum -> IFFT -> 16-bit -> window -> FFT.
n = settings.Nfft;
binHz = settings.SampleRateHz/n;
baseband = ((0:n-1).' - n/2) * binHz;
rfHz = settings.CenterFrequencyHz + baseband;

mask = abs(baseband - offsetHz) <= occupiedHz/2;
numberOccupied = sum(mask);
signal = zeros(n,1);
signal(mask) = sqrt(1/numberOccupied) * ...
    (randn(numberOccupied,1) + 1j*randn(numberOccupied,1))/sqrt(2);

snrLinear = 10^(settings.PerBinSnr_dB/10);
noiseSigma = sqrt(1/(snrLinear*numberOccupied));

direction = [cosd(elevation_deg)*cosd(azimuth_deg); ...
             cosd(elevation_deg)*sind(azimuth_deg); ...
             sind(elevation_deg)];

waves = zeros(n,4);
for channel = 1:4
    steering = exp(-1j*2*pi*rfHz*(positions(channel,:)*direction)/299792458);
    frequencyDomain = steering.*signal + noiseSigma* ...
        (randn(n,1) + 1j*randn(n,1))/sqrt(2);
    % ifft on the fftshift'ed axis, scaled so the time signal keeps unit power
    waves(:,channel) = ifft(ifftshift(frequencyDomain))*sqrt(n);
end

% one common 16-bit scale, so inter-channel amplitude relations survive
scale = 12000/max(abs(waves(:,1)));
quantised = min(32767, max(-32768, round(waves*scale)));

window = 0.5 - 0.5*cos(2*pi*(0:n-1).'/max(n-1,1));   % raised cosine, no toolbox
spectra = zeros(n,4);
for channel = 1:4
    spectra(:,channel) = fftshift(fft(double(quantised(:,channel)).*window));
end
end
