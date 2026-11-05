function v06_probe_ssr8_1024()
%V06_PROBE_SSR8_1024 One-channel dsphdl.Channelizer capability probe.
%
% Stage V06 gate 0 (MATLAB only; no HDL is generated):
%   * design the production-size 1024-band prototype (12 taps/band),
%   * construct dsphdl.Channelizer with OutputSize = input size,
%   * stream fixed-point complex samples as 8-sample (SSR-8) vectors,
%   * measure latency/valid behaviour and record output dimensions/type,
%   * verify that one tone produces one dominant channel in the last of
%     several collected snapshots.
%
% Probe v2 follows the 2026-11-03 attempt-1 result: construction, SSR-8
% streaming and latency passed, but Normalize=true left the tone at only
% about two output LSBs and the tone-concentration assertion failed.  The
% v2 default therefore uses Normalize=false (the setting used in the
% MathWorks dsp-vs-dsphdl comparison example), coefficients from tf()
% (the MathWorks HDL example path), and records coefficient/output LSB
% statistics so a failure identifies the scaling point instead of merely
% repeating the same assertion.
%
% Configuration is taken from the environment exported by config.mk:
%   CHANNELIZER_NUM_BANDS       (default 1024)
%   WIDEBAND_SAMPLES_PER_CLOCK  (default 8)
% Optional probe overrides:
%   V06_TAPS_PER_BAND           (default 12, production reference)
%   V06_STOPBAND_DB             (default 100, production reference)
%   V06_MAX_CYCLES              (default 8192 SSR beats)
%   V06_NORMALIZE               (default 0; set 1 to reproduce attempt 1)
%   V06_COEFF_SOURCE            (default tf; alternative: coeffs)
%   V06_FILTER_STRUCTURE        (default CHANNELIZER_FILTER_STRUCTURE,
%                                now transposed; probe target forces systolic baseline)
%   V06_FILTER_OUTPUT_FULL_PRECISION (default 0; diagnostic only)
%   V06_SNAPSHOTS_TO_COLLECT    (default 4; assertion uses the last one)
%
% Reports: systolic uses <repo>/build/output/v06_channelizer_probe.rpt;
% transposed uses v06_channelizer_probe_transposed.rpt so the proved
% Gate-0 baseline evidence is not overwritten.

numBands = env_integer('CHANNELIZER_NUM_BANDS', 1024);
ssr = env_integer('WIDEBAND_SAMPLES_PER_CLOCK', 8);
tapsPerBand = env_integer('V06_TAPS_PER_BAND', 12);
stopbandDb = env_integer('V06_STOPBAND_DB', 100);
maxCycles = env_integer('V06_MAX_CYCLES', 8192);
normalizeFlag = env_integer('V06_NORMALIZE', 0);
filterOutputFullPrecision = ...
    env_integer('V06_FILTER_OUTPUT_FULL_PRECISION', 0);
snapshotsToCollect = env_integer('V06_SNAPSHOTS_TO_COLLECT', 4);
coeffSource = env_choice('V06_COEFF_SOURCE', 'tf', {'tf', 'coeffs'});
filterStructureChoice = env_choice('V06_FILTER_STRUCTURE', ...
    env_choice('CHANNELIZER_FILTER_STRUCTURE', 'transposed', ...
        {'systolic', 'transposed'}), {'systolic', 'transposed'});
switch filterStructureChoice
    case 'systolic'
        filterStructure = 'Direct form systolic';
        reportSuffix = '';
    case 'transposed'
        filterStructure = 'Direct form transposed';
        reportSuffix = '_transposed';
end

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(scriptDir)));
reportDir = fullfile(repoRoot, 'build', 'output');
if ~exist(reportDir, 'dir')
    mkdir(reportDir);
end
reportFile = fullfile(reportDir, ...
    ['v06_channelizer_probe' reportSuffix '.rpt']);
fid = fopen(reportFile, 'w');
if fid < 0
    error('V06:ReportOpenFailed', 'Cannot open probe report: %s', reportFile);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

log_line = @(varargin) v06_log(fid, sprintf(varargin{:}));

log_line('# V06 channelizer probe: one channel, dsphdl.Channelizer, MATLAB only');
log_line('PROBE_VERSION=2');
log_line('MATLAB_VERSION=%s', version);
log_line('NUM_BANDS=%d', numBands);
log_line('SSR_SAMPLES_PER_CYCLE=%d', ssr);
log_line('TAPS_PER_BAND=%d', tapsPerBand);
log_line('STOPBAND_DB=%d', stopbandDb);
log_line('NORMALIZE=%d', normalizeFlag);
log_line('COEFF_SOURCE=%s', coeffSource);
log_line('FILTER_STRUCTURE_CHOICE=%s', filterStructureChoice);
log_line('FILTER_STRUCTURE=%s', filterStructure);
log_line('FILTER_OUTPUT_FULL_PRECISION=%d', filterOutputFullPrecision);
log_line('SNAPSHOTS_TO_COLLECT=%d', snapshotsToCollect);
log_line('REPORT=%s', reportFile);

try
    if exist('dsphdl.Channelizer', 'class') ~= 8
        error('V06:MissingDSPHDL', ...
            'dsphdl.Channelizer is not available; DSP HDL Toolbox is required.');
    end
    if numBands <= 0 || 2^nextpow2(numBands) ~= numBands
        error('V06:BadBandCount', 'NUM_BANDS must be a positive power of two.');
    end
    if ssr <= 0 || 2^nextpow2(ssr) ~= ssr || ssr > numBands
        error('V06:BadSSR', ...
            'SSR must be a power of two not greater than NUM_BANDS.');
    end
    if ~ismember(normalizeFlag, [0 1]) || ...
            ~ismember(filterOutputFullPrecision, [0 1])
        error('V06:BadFlag', ...
            'V06_NORMALIZE and V06_FILTER_OUTPUT_FULL_PRECISION must be 0 or 1.');
    end
    if snapshotsToCollect <= 0
        error('V06:BadSnapshotCount', ...
            'V06_SNAPSHOTS_TO_COLLECT must be positive.');
    end
    targetOutputs = numBands * snapshotsToCollect;
    if targetOutputs > ssr * maxCycles
        error('V06:SnapshotTargetTooLarge', ...
            ['Cannot collect %d outputs in %d SSR cycles; ' ...
             'increase V06_MAX_CYCLES.'], targetOutputs, maxCycles);
    end

    % Compare both documented coefficient extraction paths.  coeffs() is
    % the path in the legacy harness; tf() is the path used by the
    % MathWorks HDL example and by matlab_v7/design_pfb_coefficients.m.
    % Recording max/sum and their difference makes any release-specific
    % scaling or ordering difference visible in the report.
    log_line('DESIGNING_PROTOTYPE=1');
    referenceChannelizer = dsp.Channelizer( ...
        NumFrequencyBands=numBands, ...
        NumTapsPerBand=tapsPerBand, ...
        StopbandAttenuation=stopbandDb);
    coefficientStruct = coeffs(referenceChannelizer);
    coeffsNumerator = coefficientStruct.Numerator;
    [tfNumerator, tfDenominator] = tf(referenceChannelizer);
    release(referenceChannelizer);
    expectedCoefficients = numBands * tapsPerBand;
    log_coefficient_stats(log_line, 'COEFFS', coeffsNumerator);
    log_coefficient_stats(log_line, 'TF', tfNumerator);
    log_line('TF_DENOMINATOR_COUNT=%d', numel(tfDenominator));
    if numel(coeffsNumerator) == numel(tfNumerator)
        log_line('COEFFS_TF_MAX_ABS_DIFF=%.12g', ...
            max(abs(double(coeffsNumerator(:)) - double(tfNumerator(:)))));
    else
        log_line('COEFFS_TF_MAX_ABS_DIFF=incompatible_counts');
    end
    switch coeffSource
        case 'tf'
            coefficients = tfNumerator;
        case 'coeffs'
            coefficients = coeffsNumerator;
    end
    log_line('COEFFICIENT_COUNT=%d', numel(coefficients));
    log_line('COEFFICIENT_EXPECTED=%d', expectedCoefficients);
    if numel(coefficients) ~= expectedCoefficients
        error('V06:CoefficientCount', ...
            'Prototype has %d coefficients, expected %d.', ...
            numel(coefficients), expectedCoefficients);
    end
    if numel(tfDenominator) ~= 1 || double(tfDenominator(1)) ~= 1
        error('V06:UnexpectedPrototypeDenominator', ...
            'Prototype tf denominator is not scalar 1.');
    end

    constructorArgs = { ...
        'NumFrequencyBands', numBands, ...
        'FilterCoefficients', coefficients, ...
        'FilterStructure', filterStructure, ...
        'OutputSize', 'Same as input size', ...
        'Normalize', logical(normalizeFlag)};
    if filterOutputFullPrecision
        constructorArgs = [constructorArgs, ...
            {'FilterOutputDataType', 'Full precision'}]; %#ok<AGROW>
    end
    channelizer = dsphdl.Channelizer(constructorArgs{:});
    log_line('DSPHDL_CONSTRUCT=PASS');

    try
        reportedLatency = getLatency(channelizer, numBands, ssr, true);
        log_line('GETLATENCY_CYCLES=%d', reportedLatency);
    catch latencyException
        log_line('GETLATENCY_CYCLES=unavailable (%s)', ...
            latencyException.identifier);
    end

    % Deterministic fixed-point complex tone.  The RFDC streams are
    % signed 16-bit words; the existing harness represents them as
    % fixdt(1,16,15).  f=0.1875 cycles/sample is exactly bin 192/1024
    % under a natural FFT frequency grid.  The probe only asserts that
    % one channel dominates; exact bin ordering is a later V06 gate.
    toneBin = round(0.1875 * numBands);
    toneFrequency = toneBin / numBands;
    sampleIndex = 0:(ssr * maxCycles - 1);
    tone = 0.25 * exp(1j * 2 * pi * toneFrequency * sampleIndex);
    inputType = numerictype(1, 16, 15);
    inputSamples = fi(reshape(tone, ssr, maxCycles), inputType);
    log_line('TONE_BIN_NOMINAL=%d', toneBin);
    log_line('INPUT_TYPE=%s', describe_type(inputSamples));

    collected = complex(zeros(ssr * maxCycles, 1));
    collectedCount = 0;
    validBeatCount = 0;
    firstValidCycle = 0;
    firstOutputSize = [];
    firstOutputType = '<none>';
    outputFractionLength = NaN;
    cyclesRun = 0;

    for cycle = 1:maxCycles
        cyclesRun = cycle;
        [dataOut, validOut] = channelizer(inputSamples(:, cycle), true);
        if cycle == 1
            firstOutputSize = size(dataOut);
            firstOutputType = describe_type(dataOut);
            if isfi(dataOut)
                outputFractionLength = numerictype(dataOut).FractionLength;
            end
            log_line('OUTPUT_SIZE=[%d %d]', ...
                firstOutputSize(1), firstOutputSize(2));
            log_line('OUTPUT_TYPE=%s', firstOutputType);
            if ~isequal(firstOutputSize, [ssr 1])
                error('V06:OutputSize', ...
                    'Output size is [%d %d], expected [%d 1].', ...
                    firstOutputSize(1), firstOutputSize(2), ssr);
            end
        end
        if any(validOut(:))
            if firstValidCycle == 0
                firstValidCycle = cycle;
            end
            validBeatCount = validBeatCount + 1;
            values = double(dataOut(:));
            collected(collectedCount + (1:numel(values))) = values;
            collectedCount = collectedCount + numel(values);
            if collectedCount >= targetOutputs
                break;
            end
        end
    end
    release(channelizer);

    log_line('CYCLES_RUN=%d', cyclesRun);
    log_line('FIRST_VALID_CYCLE=%d', firstValidCycle);
    log_line('MEASURED_LATENCY_CYCLES=%d', ...
        max(firstValidCycle - 1, 0));
    log_line('VALID_BEATS=%d', validBeatCount);
    log_line('COLLECTED_OUTPUTS=%d', collectedCount);

    if firstValidCycle == 0
        error('V06:NoValidOutput', ...
            'No valid output within %d SSR cycles.', maxCycles);
    end
    if collectedCount < targetOutputs
        error('V06:ShortSnapshot', ...
            'Collected only %d outputs; need %d (%d snapshots).', ...
            collectedCount, targetOutputs, snapshotsToCollect);
    end

    snapshots = reshape(collected(1:targetOutputs), ...
        numBands, snapshotsToCollect);
    if isfinite(outputFractionLength)
        outputLsb = 2^(-outputFractionLength);
    else
        outputLsb = NaN;
    end
    log_line('OUTPUT_LSB=%.12g', outputLsb);

    top1Fraction = NaN;
    top5Fraction = NaN;
    totalEnergy = NaN;
    for snapshotIndex = 1:snapshotsToCollect
        metrics = snapshot_metrics(snapshots(:, snapshotIndex));
        log_line('SNAPSHOT_%d_PEAK_INDEX0=%d', ...
            snapshotIndex, metrics.peakIndex - 1);
        log_line('SNAPSHOT_%d_PEAK_MAGNITUDE=%.12g', ...
            snapshotIndex, metrics.peakMagnitude);
        log_line('SNAPSHOT_%d_RMS_MAGNITUDE=%.12g', ...
            snapshotIndex, metrics.rmsMagnitude);
        log_line('SNAPSHOT_%d_PEAK_MAGNITUDE_LSB=%.12g', ...
            snapshotIndex, metrics.peakMagnitude / outputLsb);
        log_line('SNAPSHOT_%d_RMS_MAGNITUDE_LSB=%.12g', ...
            snapshotIndex, metrics.rmsMagnitude / outputLsb);
        log_line('SNAPSHOT_%d_TOP1_ENERGY_FRACTION=%.12g', ...
            snapshotIndex, metrics.top1Fraction);
        log_line('SNAPSHOT_%d_TOP5_ENERGY_FRACTION=%.12g', ...
            snapshotIndex, metrics.top5Fraction);
        if snapshotIndex == snapshotsToCollect
            peakIndex = metrics.peakIndex;
            peakMagnitude = metrics.peakMagnitude;
            totalEnergy = metrics.totalEnergy;
            top1Fraction = metrics.top1Fraction;
            top5Fraction = metrics.top5Fraction;
        end
    end

    % Keep the attempt-1 metric names for the asserted (last) snapshot so
    % reports remain directly comparable.
    log_line('SNAPSHOT_PEAK_INDEX0=%d', peakIndex - 1);
    log_line('SNAPSHOT_PEAK_MAGNITUDE=%.12g', peakMagnitude);
    log_line('SNAPSHOT_TOTAL_ENERGY=%.12g', totalEnergy);
    log_line('TOP1_ENERGY_FRACTION=%.12g', top1Fraction);
    log_line('TOP5_ENERGY_FRACTION=%.12g', top5Fraction);

    if ~isfinite(totalEnergy) || totalEnergy <= 0
        error('V06:BadOutputEnergy', 'Snapshot energy is not positive/finite.');
    end
    if top1Fraction < 0.25 || top5Fraction < 0.50
        error('V06:ToneNotConcentrated', ...
            ['Last-snapshot tone energy is not concentrated: ' ...
             'top1=%.6g top5=%.6g peakLSB=%.6g normalize=%d ' ...
             'coeffSource=%s (required top1>=0.25 and top5>=0.50).'], ...
            top1Fraction, top5Fraction, peakMagnitude / outputLsb, ...
            normalizeFlag, coeffSource);
    end

    log_line('V06 CHANNELIZER PROBE RESULT=PASS');
catch exception
    log_line('PROBE_EXCEPTION_ID=%s', exception.identifier);
    log_line('PROBE_EXCEPTION_MESSAGE=%s', exception.message);
    if ~isempty(exception.stack)
        log_line('PROBE_EXCEPTION_AT=%s:%d', ...
            exception.stack(1).file, exception.stack(1).line);
    end
    log_line('V06 CHANNELIZER PROBE RESULT=FAIL');
    rethrow(exception);
end
end

function v06_log(fid, line)
fprintf('%s\n', line);
fprintf(fid, '%s\n', line);
end

function log_coefficient_stats(log_line, prefix, coefficients)
values = double(coefficients(:));
log_line('%s_COUNT=%d', prefix, numel(values));
log_line('%s_MAX_ABS=%.12g', prefix, max(abs(values)));
log_line('%s_SUM=%.12g', prefix, sum(values));
log_line('%s_SUM_ABS=%.12g', prefix, sum(abs(values)));
end

function metrics = snapshot_metrics(snapshot)
magnitudes = abs(snapshot(:));
energies = magnitudes .^ 2;
metrics.totalEnergy = sum(energies);
[metrics.peakMagnitude, metrics.peakIndex] = max(magnitudes);
metrics.rmsMagnitude = sqrt(mean(energies));
sortedEnergies = sort(energies, 'descend');
if metrics.totalEnergy > 0
    metrics.top1Fraction = sortedEnergies(1) / metrics.totalEnergy;
    metrics.top5Fraction = ...
        sum(sortedEnergies(1:min(5, end))) / metrics.totalEnergy;
else
    metrics.top1Fraction = NaN;
    metrics.top5Fraction = NaN;
end
end

function value = env_integer(name, defaultValue)
text = getenv(name);
if isempty(text)
    value = defaultValue;
    return;
end
value = str2double(text);
if ~isfinite(value) || value ~= round(value)
    error('V06:BadEnvironment', '%s must be an integer, got "%s".', name, text);
end
value = round(value);
end

function value = env_choice(name, defaultValue, allowedValues)
text = lower(strtrim(getenv(name)));
if isempty(text)
    value = defaultValue;
    return;
end
if ~ismember(text, allowedValues)
    error('V06:BadEnvironment', '%s must be one of {%s}, got "%s".', ...
        name, strjoin(allowedValues, ', '), text);
end
value = text;
end

function description = describe_type(value)
if isfi(value)
    nt = numerictype(value);
    description = sprintf('fi signedness=%s wordLength=%d fractionLength=%d', ...
        nt.Signedness, nt.WordLength, nt.FractionLength);
else
    description = class(value);
end
end
