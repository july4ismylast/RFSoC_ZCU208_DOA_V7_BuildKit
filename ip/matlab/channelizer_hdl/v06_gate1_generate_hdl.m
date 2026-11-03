function v06_gate1_generate_hdl()
%V06_GATE1_GENERATE_HDL Generate and catalog one SSR-8/1024 channel.
%
% Stage V06 Gate 1 (generation only; no Vivado packaging):
%   * require the Gate-0 probe-v2 PASS report for the same production
%     1024-band / SSR-8 / 12-tap / 100 dB / Normalize=false settings and
%     the same filter structure;
%   * rebuild the Simulink harness from config.mk environment values;
%   * invoke HDL Coder for the one-channel Channelizer_DUT;
%   * record the generated top, its port declarations, object latency,
%     fixed-point output type, generated-file summary and report files.
%
% Reports: systolic uses v06_gate1_hdl_generation.rpt; transposed uses
% v06_gate1_hdl_generation_transposed.rpt and consumes the matching
% transposed Gate-0 report, preserving all systolic baseline evidence.

numBands = env_integer('CHANNELIZER_NUM_BANDS', 1024);
ssr = env_integer('WIDEBAND_SAMPLES_PER_CLOCK', 8);
tapsPerBand = env_integer('V06_TAPS_PER_BAND', ...
    env_integer('CHANNELIZER_TAPS_PER_BAND', 12));
stopbandDb = env_integer('V06_STOPBAND_DB', ...
    env_integer('CHANNELIZER_STOPBAND_DB', 100));
normalizeFlag = env_integer('V06_NORMALIZE', ...
    env_integer('CHANNELIZER_NORMALIZE', 0));
filterStructureChoice = env_choice('V06_FILTER_STRUCTURE', ...
    env_choice('CHANNELIZER_FILTER_STRUCTURE', 'systolic', ...
        {'systolic', 'transposed'}), {'systolic', 'transposed'});
switch filterStructureChoice
    case 'systolic'
        filterStructure = 'Direct form systolic';
        reportSuffix = '';
    case 'transposed'
        filterStructure = 'Direct form transposed';
        reportSuffix = '_transposed';
end
part = strtrim(getenv('PART'));
if isempty(part)
    part = 'xczu48dr-fsvg1517-2-e';
end

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(scriptDir)));
reportDir = fullfile(repoRoot, 'build', 'output');
if ~exist(reportDir, 'dir')
    mkdir(reportDir);
end
reportFile = fullfile(reportDir, ...
    ['v06_gate1_hdl_generation' reportSuffix '.rpt']);
gate0ReportFile = fullfile(reportDir, ...
    ['v06_channelizer_probe' reportSuffix '.rpt']);

fid = fopen(reportFile, 'w');
if fid < 0
    error('V06:Gate1ReportOpenFailed', ...
        'Cannot open Gate-1 report: %s', reportFile);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
log_line = @(varargin) v06_log(fid, sprintf(varargin{:}));

log_line('# V06 Gate 1: one-channel HDL generation, no packaging');
log_line('GATE1_SCRIPT_REVISION=3-filter-structure');
log_line('MATLAB_VERSION=%s', version);
log_line('PART=%s', part);
log_line('NUM_BANDS=%d', numBands);
log_line('SSR_SAMPLES_PER_CYCLE=%d', ssr);
log_line('TAPS_PER_BAND=%d', tapsPerBand);
log_line('STOPBAND_DB=%d', stopbandDb);
log_line('NORMALIZE=%d', normalizeFlag);
log_line('FILTER_STRUCTURE_CHOICE=%s', filterStructureChoice);
log_line('FILTER_STRUCTURE=%s', filterStructure);
log_line('GATE0_REPORT=%s', gate0ReportFile);
log_line('REPORT=%s', reportFile);

try
    if numBands ~= 1024 || ssr ~= 8 || tapsPerBand ~= 12 || ...
            stopbandDb ~= 100 || normalizeFlag ~= 0
        error('V06:Gate1WrongConfiguration', ...
            ['Gate 1 requires the proved production probe settings: ' ...
             '1024 bands, SSR-8, 12 taps/band, 100 dB, Normalize=false.']);
    end
    if ~exist(gate0ReportFile, 'file')
        error('V06:Gate1Gate0ReportMissing', ...
            'Gate-0 probe report is missing: %s', gate0ReportFile);
    end

    gate0Text = fileread(gate0ReportFile);
    if isempty(strfind(gate0Text, 'V06 CHANNELIZER PROBE RESULT=PASS')) %#ok<STREMP>
        error('V06:Gate1Gate0NotPass', ...
            'Gate-0 report does not contain a PASS result.');
    end
    require_report_value(log_line, gate0Text, 'PROBE_VERSION', '2');
    require_report_value(log_line, gate0Text, 'NUM_BANDS', ...
        num2str(numBands));
    require_report_value(log_line, gate0Text, 'SSR_SAMPLES_PER_CYCLE', ...
        num2str(ssr));
    require_report_value(log_line, gate0Text, 'TAPS_PER_BAND', ...
        num2str(tapsPerBand));
    require_report_value(log_line, gate0Text, 'STOPBAND_DB', ...
        num2str(stopbandDb));
    require_report_value(log_line, gate0Text, 'NORMALIZE', ...
        num2str(normalizeFlag));
    require_report_value(log_line, gate0Text, 'FILTER_STRUCTURE', ...
        filterStructure);
    require_report_value(log_line, gate0Text, 'COEFFS_TF_MAX_ABS_DIFF', '0');
    toneBin = report_value(gate0Text, 'TONE_BIN_NOMINAL');
    peakBin = report_value(gate0Text, 'SNAPSHOT_PEAK_INDEX0');
    log_line('GATE0_TONE_BIN_NOMINAL=%s', toneBin);
    log_line('GATE0_SNAPSHOT_PEAK_INDEX0=%s', peakBin);
    if ~strcmp(toneBin, peakBin)
        error('V06:Gate1Gate0PeakMismatch', ...
            'Gate-0 peak bin %s does not match nominal tone bin %s.', ...
            peakBin, toneBin);
    end
    outputType = report_value(gate0Text, 'OUTPUT_TYPE');
    latency = report_value(gate0Text, 'GETLATENCY_CYCLES');
    measuredLatency = report_value(gate0Text, 'MEASURED_LATENCY_CYCLES');
    log_line('GATE0_OUTPUT_TYPE=%s', outputType);
    log_line('GATE0_GETLATENCY_CYCLES=%s', latency);
    log_line('GATE0_MEASURED_LATENCY_CYCLES=%s', measuredLatency);

    latencyCycles = str2double(latency);
    measuredLatencyCycles = str2double(measuredLatency);
    if ~isfinite(latencyCycles) || latencyCycles <= 0 || ...
            latencyCycles ~= round(latencyCycles) || ...
            ~isfinite(measuredLatencyCycles) || ...
            measuredLatencyCycles ~= latencyCycles
        error('V06:Gate1Gate0Latency', ...
            ['Gate-0 latency must be a positive integer and match the ' ...
             'measured first-valid latency: getLatency=%s measured=%s.'], ...
            latency, measuredLatency);
    end
    if strcmp(filterStructureChoice, 'systolic') && latencyCycles ~= 1760
        error('V06:Gate1SystolicLatency', ...
            'Systolic Gate-0 latency is %d, expected the proved 1760.', ...
            latencyCycles);
    end

    outputTypeToken = regexp(outputType, ...
        '^fi signedness=Signed wordLength=(\d+) fractionLength=(-?\d+)$', ...
        'tokens', 'once');
    if isempty(outputTypeToken)
        error('V06:Gate1Gate0OutputType', ...
            'Gate-0 output type is not a signed fixed-point type: %s', ...
            outputType);
    end
    outputWordLength = str2double(outputTypeToken{1});
    outputFractionLength = str2double(outputTypeToken{2});
    log_line('GATE0_OUTPUT_WORD_LENGTH=%d', outputWordLength);
    log_line('GATE0_OUTPUT_FRACTION_LENGTH=%d', outputFractionLength);
    if outputWordLength ~= 26 || outputFractionLength ~= 24
        error('V06:Gate1Gate0OutputType', ...
            ['Gate-0 output type is signed %d/%d; the A/B contract ' ...
             'requires the proved signed 26/24 interface.'], ...
            outputWordLength, outputFractionLength);
    end

    startDatenum = now;
    generationTimer = tic;
    log_line('HDL_GENERATION_STARTED=1');
    generatedTopFile = generate_hdl();
    generationSeconds = toc(generationTimer);
    log_line('HDL_GENERATION_SECONDS=%.3f', generationSeconds);
    log_line('GENERATED_TOP=%s', generatedTopFile);

    if ~exist(generatedTopFile, 'file')
        error('V06:Gate1TopMissing', ...
            'Generated top file does not exist: %s', generatedTopFile);
    end
    topInfo = dir(generatedTopFile);
    if topInfo.datenum < startDatenum - (2 / 86400)
        error('V06:Gate1StaleTop', ...
            'Generated top predates this Gate-1 run: %s', generatedTopFile);
    end
    log_line('GENERATED_TOP_BYTES=%d', topInfo.bytes);

    topText = fileread(generatedTopFile);
    moduleToken = regexp(topText, ...
        '(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\>', ...
        'tokens', 'once');
    if isempty(moduleToken)
        error('V06:Gate1ModuleMissing', ...
            'No Verilog module declaration found in generated top.');
    end
    generatedModule = moduleToken{1};
    log_line('GENERATED_MODULE=%s', generatedModule);
    if ~strcmp(generatedModule, 'Channelizer_DUT')
        error('V06:Gate1ModuleMismatch', ...
            'Generated module is %s, expected Channelizer_DUT.', ...
            generatedModule);
    end

    topLines = cellstr(splitlines(string(topText)));
    log_line('GENERATED_TOP_LINES=%d', numel(topLines));
    portMatches = regexp(topLines, ...
        '^\s*(input|output|inout)\>', 'once');
    isPortLine = ~cellfun(@isempty, portMatches);
    portLines = strtrim(topLines(isPortLine));
    log_line('GENERATED_TOP_PORT_DECLARATIONS=%d', numel(portLines));
    if isempty(portLines)
        error('V06:Gate1NoPorts', ...
            'No input/output declarations found in generated top.');
    end
    maxLoggedPorts = min(numel(portLines), 250);
    for portIndex = 1:maxLoggedPorts
        log_line('TOP_PORT_%03d=%s', portIndex, portLines{portIndex});
    end
    if numel(portLines) > maxLoggedPorts
        log_line('TOP_PORT_LIST_TRUNCATED_AT=%d', maxLoggedPorts);
    end

    expectedInputPattern = ...
        '^input\s+signed\s+\[15:0\]\s+dataIn_(re|im)_[0-7];$';
    expectedOutputPattern = sprintf( ...
        '^output\\s+signed\\s+\\[%d:0\\]\\s+dataOut_(re|im)_[0-7];$', ...
        outputWordLength - 1);
    inputMatches = regexp(portLines, expectedInputPattern, 'once');
    outputMatches = regexp(portLines, expectedOutputPattern, 'once');
    inputDataPortCount = sum(~cellfun(@isempty, inputMatches));
    outputDataPortCount = sum(~cellfun(@isempty, outputMatches));
    log_line('GENERATED_TOP_INPUT_DATA_PORTS_16BIT=%d', ...
        inputDataPortCount);
    log_line('GENERATED_TOP_OUTPUT_DATA_PORTS_%dBIT=%d', ...
        outputWordLength, outputDataPortCount);
    if inputDataPortCount ~= 16 || outputDataPortCount ~= 16
        error('V06:Gate1TopPortWidths', ...
            ['Expected 16 signed 16-bit dataIn ports and 16 signed ' ...
             '%d-bit dataOut ports; found %d and %d.'], ...
            outputWordLength, inputDataPortCount, outputDataPortCount);
    end

    generatedRoot = fileparts(generatedTopFile);
    allFiles = dir(fullfile(generatedRoot, '**', '*'));
    allFiles = allFiles(~[allFiles.isdir]);
    log_line('GENERATED_ROOT=%s', generatedRoot);
    log_line('GENERATED_FILE_COUNT=%d', numel(allFiles));
    log_line('GENERATED_TOTAL_BYTES=%d', sum([allFiles.bytes]));

    extensionsToCount = {'.v', '.sv', '.vhd', '.html', '.htm', '.txt', ...
        '.rpt', '.log', '.xml', '.tcl', '.m', '.do'};
    for extensionIndex = 1:numel(extensionsToCount)
        extension = extensionsToCount{extensionIndex};
        extensionCount = 0;
        for fileIndex = 1:numel(allFiles)
            [~, ~, fileExtension] = fileparts(allFiles(fileIndex).name);
            if strcmpi(fileExtension, extension)
                extensionCount = extensionCount + 1;
            end
        end
        if extensionCount > 0
            log_line('GENERATED_COUNT%s=%d', extension, extensionCount);
        end
    end

    reportCount = 0;
    for fileIndex = 1:numel(allFiles)
        [~, ~, fileExtension] = fileparts(allFiles(fileIndex).name);
        isReportName = ~isempty(regexpi(allFiles(fileIndex).name, ...
            'report|summary|log', 'once'));
        if ismember(lower(fileExtension), ...
                {'.html', '.htm', '.txt', '.rpt', '.log', '.xml'}) || ...
                isReportName
            reportCount = reportCount + 1;
            if reportCount <= 100
                generatedPath = fullfile(allFiles(fileIndex).folder, ...
                    allFiles(fileIndex).name);
                relativePath = strrep(generatedPath, ...
                    [generatedRoot filesep], '');
                log_line('GENERATED_REPORT_FILE=%s', relativePath);
            end
        end
    end
    log_line('GENERATED_REPORT_FILE_COUNT=%d', reportCount);
    log_line('EXPECTED_OBJECT_LATENCY_CYCLES=%s', latency);
    log_line('EXPECTED_OUTPUT_TYPE=%s', outputType);
    log_line('PACKAGING_PERFORMED=0');
    log_line('V06 GATE1 HDL GENERATION RESULT=PASS');
catch exception
    log_line('GATE1_EXCEPTION_ID=%s', exception.identifier);
    log_line('GATE1_EXCEPTION_MESSAGE=%s', exception.message);
    if ~isempty(exception.stack)
        log_line('GATE1_EXCEPTION_AT=%s:%d', ...
            exception.stack(1).file, exception.stack(1).line);
    end
    log_line('PACKAGING_PERFORMED=0');
    log_line('V06 GATE1 HDL GENERATION RESULT=FAIL');
    rethrow(exception);
end
end

function v06_log(fid, line)
fprintf('%s\n', line);
fprintf(fid, '%s\n', line);
end

function require_report_value(log_line, text, key, expectedValue)
actualValue = report_value(text, key);
log_line('GATE0_%s=%s', key, actualValue);
if ~strcmp(actualValue, expectedValue)
    error('V06:Gate1Gate0Mismatch', ...
        'Gate-0 %s is %s, expected %s.', key, actualValue, expectedValue);
end
end

function value = report_value(text, key)
% Parse strictly line-by-line.  Do not use a regexp capture such as
% '(?m)^KEY=(.*)$' here: in MATLAB '.' matches newline characters by
% default, so that expression can capture the remainder of the report
% instead of the one-line value (Gate-1 attempt 1, 2026-11-03).
lines = cellstr(splitlines(string(text)));
prefix = [key '='];
for lineIndex = 1:numel(lines)
    line = lines{lineIndex};
    if strncmp(line, prefix, numel(prefix))
        value = strtrim(line(numel(prefix) + 1:end));
        return;
    end
end
error('V06:Gate1Gate0KeyMissing', ...
    'Gate-0 report does not contain %s.', key);
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
