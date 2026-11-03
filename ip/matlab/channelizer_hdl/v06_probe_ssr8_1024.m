function v06_probe_ssr8_1024()
%V06_PROBE_SSR8_1024 One-channel dsphdl.Channelizer capability probe.
%
% Stage V06 gate 0 (MATLAB only; no HDL is generated):
%   * design the production-size 1024-band prototype (12 taps/band),
%   * construct dsphdl.Channelizer with OutputSize = input size,
%   * stream fixed-point complex samples as 8-sample (SSR-8) vectors,
%   * measure latency/valid behaviour and record output dimensions/type,
%   * verify that one tone produces one dominant channel in a snapshot.
%
% Configuration is taken from the environment exported by config.mk:
%   CHANNELIZER_NUM_BANDS       (default 1024)
%   WIDEBAND_SAMPLES_PER_CLOCK  (default 8)
% Optional probe overrides:
%   V06_TAPS_PER_BAND           (default 12, production reference)
%   V06_STOPBAND_DB             (default 100, production reference)
%   V06_MAX_CYCLES              (default 8192 SSR beats)
%
% Report: <repo>/build/output/v06_channelizer_probe.rpt

numBands = env_integer('CHANNELIZER_NUM_BANDS', 1024);
ssr = env_integer('WIDEBAND_SAMPLES_PER_CLOCK', 8);
tapsPerBand = env_integer('V06_TAPS_PER_BAND', 12);
stopbandDb = env_integer('V06_STOPBAND_DB', 100);
maxCycles = env_integer('V06_MAX_CYCLES', 8192);

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(scriptDir)));
reportDir = fullfile(repoRoot, 'build', 'output');
if ~exist(reportDir, 'dir')
    mkdir(reportDir);
end
reportFile = fullfile(reportDir, 'v06_channelizer_probe.rpt');
fid = fopen(reportFile, 'w');
if fid < 0
    error('V06:ReportOpenFailed', 'Cannot open probe report: %s', reportFile);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

log_line = @(varargin) v06_log(fid, sprintf(varargin{:}));

log_line('# V06 channelizer probe: one channel, dsphdl.Channelizer, MATLAB only');
log_line('MATLAB_VERSION=%s', version);
log_line('NUM_BANDS=%d', numBands);
log_line('SSR_SAMPLES_PER_CYCLE=%d', ssr);
log_line('TAPS_PER_BAND=%d', tapsPerBand);
log_line('STOPBAND_DB=%d', stopbandDb);
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

    % Match the coefficient path in the existing HDL harness/model reference.
    log_line('DESIGNING_PROTOTYPE=1');
    referenceChannelizer = dsp.Channelizer( ...
        NumFrequencyBands=numBands, ...
        NumTapsPerBand=tapsPerBand, ...
        StopbandAttenuation=stopbandDb);
    coefficientStruct = coeffs(referenceChannelizer);
    coefficients = coefficientStruct.Numerator;
    release(referenceChannelizer);
    expectedCoefficients = numBands * tapsPerBand;
    log_line('COEFFICIENT_COUNT=%d', numel(coefficients));
    log_line('COEFFICIENT_EXPECTED=%d', expectedCoefficients);
    if numel(coefficients) ~= expectedCoefficients
        error('V06:CoefficientCount', ...
            'Prototype has %d coefficients, expected %d.', ...
            numel(coefficients), expectedCoefficients);
    end

    channelizer = dsphdl.Channelizer( ...
        NumFrequencyBands=numBands, ...
        FilterCoefficients=coefficients, ...
        FilterStructure='Direct form systolic', ...
        OutputSize='Same as input size', ...
        Normalize=true);
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
    cyclesRun = 0;

    for cycle = 1:maxCycles
        cyclesRun = cycle;
        [dataOut, validOut] = channelizer(inputSamples(:, cycle), true);
        if cycle == 1
            firstOutputSize = size(dataOut);
            firstOutputType = describe_type(dataOut);
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
            if collectedCount >= numBands
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
    if collectedCount < numBands
        error('V06:ShortSnapshot', ...
            'Collected only %d outputs; need one %d-bin snapshot.', ...
            collectedCount, numBands);
    end

    snapshot = collected(1:numBands);
    magnitudes = abs(snapshot);
    energies = magnitudes .^ 2;
    totalEnergy = sum(energies);
    [peakMagnitude, peakIndex] = max(magnitudes);
    sortedEnergies = sort(energies, 'descend');
    top1Fraction = sortedEnergies(1) / totalEnergy;
    top5Fraction = sum(sortedEnergies(1:min(5, end))) / totalEnergy;

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
            ['Tone energy is not concentrated: top1=%.6g top5=%.6g ' ...
             '(required top1>=0.25 and top5>=0.50).'], ...
            top1Fraction, top5Fraction);
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

function description = describe_type(value)
if isfi(value)
    nt = numerictype(value);
    description = sprintf('fi signedness=%s wordLength=%d fractionLength=%d', ...
        nt.Signedness, nt.WordLength, nt.FractionLength);
else
    description = class(value);
end
end
