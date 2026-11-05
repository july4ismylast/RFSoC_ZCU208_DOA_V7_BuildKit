function v06_gate4_generate_rtl_golden()
% Generate bit-exact SSR-8 input/output vectors for Gate-4C XSim checking.
numBands = 1024;
ssr = 8;
tapsPerBand = 12;
stopbandDb = 100;
inputType = numerictype(1, 16, 15);
outputWordLength = 26;
outputFractionLength = 24;
inputBeats = numBands / ssr;
flushCycles = 512;

scriptDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(scriptDir)));
buildDir = strtrim(getenv('BUILD'));
if isempty(buildDir)
    buildDir = fullfile(repoRoot, 'build');
end
goldenDir = fullfile(buildDir, 'v06_gate4_axis_wrapper_rtl_sim');
if ~exist(goldenDir, 'dir')
    mkdir(goldenDir);
end
reportFile = fullfile(buildDir, 'output', 'v06_gate4_rtl_golden.rpt');
if ~exist(fileparts(reportFile), 'dir')
    mkdir(fileparts(reportFile));
end
fid = fopen(reportFile, 'w');
if fid < 0
    error('V06:Gate4GoldenReport', 'Cannot write report %s', reportFile);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
log_line = @(varargin) golden_log(fid, sprintf(varargin{:}));

try
    log_line('MATLAB_VERSION=%s', version);
    log_line('NUM_BANDS=%d', numBands);
    log_line('SSR=%d', ssr);
    log_line('INPUT_BEATS=%d', inputBeats);
    log_line('INPUT_WORD_LENGTH=%d', inputType.WordLength);
    log_line('INPUT_FRACTION_LENGTH=%d', inputType.FractionLength);
    log_line('OUTPUT_WORD_LENGTH=%d', outputWordLength);
    log_line('OUTPUT_FRACTION_LENGTH=%d', outputFractionLength);
    log_line('FILTER_STRUCTURE=Direct form transposed');
    log_line('NORMALIZE=0');

    designChannelizer = dsp.Channelizer( ...
        NumFrequencyBands=numBands, ...
        NumTapsPerBand=tapsPerBand, ...
        StopbandAttenuation=stopbandDb);
    [coefficients, denominator] = tf(designChannelizer);
    release(designChannelizer);
    if numel(coefficients) ~= numBands * tapsPerBand || ...
            numel(denominator) ~= 1 || double(denominator(1)) ~= 1
        error('V06:Gate4GoldenCoefficients', ...
            'Unexpected prototype coefficient count/denominator.');
    end

    toneBins = [1 18 35 68 133 198 255 320 ...
        447 511 514 645 770 900 1000 1023];
    tonePhases = mod(0.731 * (0:15).^2 + 0.193 * (0:15), 2*pi);
    toneAmplitudes = 0.82 + 0.03 * (0:15);
    n = (0:(numBands - 1)).';
    unscaled = exp(1j * (2*pi*n*(toneBins/numBands) + tonePhases)) * ...
        toneAmplitudes.';
    waveform = unscaled * (0.70 / max(abs(unscaled)));
    inputSamples = fi(waveform, inputType);
    inputMatrix = reshape(inputSamples, ssr, inputBeats);

    inputFile = fullfile(goldenDir, 'input.mem');
    inputFid = fopen(inputFile, 'w');
    if inputFid < 0
        error('V06:Gate4GoldenInput', 'Cannot write %s', inputFile);
    end
    inputCleanup = onCleanup(@() fclose(inputFid)); %#ok<NASGU>
    for beat = 1:inputBeats
        fprintf(inputFid, '%s\n', pack_input_beat(inputMatrix(:, beat)));
    end
    clear inputCleanup;

    dut = ZU48DRChannelizer();
    dut.NumBands = numBands;
    dut.Coefficients = coefficients;
    dut.FilterStructure = 'Direct form transposed';
    dut.NormalizeFFT = false;
    expected = cell(1, inputBeats);
    outputCount = 0;
    zeroInput = fi(complex(zeros(ssr, 1)), inputType);
    for cycle = 1:(inputBeats + flushCycles)
        if cycle <= inputBeats
            inputBeat = inputMatrix(:, cycle);
            validIn = true;
        else
            inputBeat = zeroInput;
            validIn = false;
        end
        [dataOut, validOut] = dut(inputBeat, validIn);
        if isfi(dataOut)
            outType = numerictype(dataOut);
            if outType.WordLength ~= outputWordLength || ...
                    outType.FractionLength ~= outputFractionLength || ...
                    ~strcmp(outType.Signedness, 'Signed')
                error('V06:Gate4GoldenOutputType', ...
                    'Unexpected output type: %s', describe_type(dataOut));
            end
        else
            error('V06:Gate4GoldenOutputType', ...
                'Channelizer output is not fixed point.');
        end
        if any(validOut(:))
            outputCount = outputCount + 1;
            if outputCount > inputBeats
                error('V06:Gate4GoldenTooManyOutputs', ...
                    'Reference generated more than %d output beats.', inputBeats);
            end
            expected{outputCount} = dataOut(:);
        end
    end
    release(dut);
    if outputCount ~= inputBeats
        error('V06:Gate4GoldenOutputCount', ...
            'Reference generated %d output beats; expected %d.', ...
            outputCount, inputBeats);
    end

    expectedFile = fullfile(goldenDir, 'expected.mem');
    expectedFid = fopen(expectedFile, 'w');
    if expectedFid < 0
        error('V06:Gate4GoldenExpected', 'Cannot write %s', expectedFile);
    end
    expectedCleanup = onCleanup(@() fclose(expectedFid)); %#ok<NASGU>
    for beat = 1:outputCount
        fprintf(expectedFid, '%s\n', pack_output_beat(expected{beat}));
    end
    clear expectedCleanup;

    log_line('INPUT_FILE=%s', inputFile);
    log_line('EXPECTED_FILE=%s', expectedFile);
    log_line('OUTPUT_BEATS=%d', outputCount);
    log_line('FLUSH_CYCLES=%d', flushCycles);
    log_line('V06 GATE4 RTL GOLDEN RESULT=PASS');
catch exception
    log_line('ERROR_ID=%s', exception.identifier);
    log_line('ERROR=%s', exception.message);
    log_line('V06 GATE4 RTL GOLDEN RESULT=FAIL');
    rethrow(exception);
end
end

function text = pack_input_beat(values)
text = '';
for lane = 8:-1:1
    iBits = unsigned_bits(double(storedInteger(real(values(lane)))), 16);
    qBits = unsigned_bits(double(storedInteger(imag(values(lane)))), 16);
    laneWord = bitshift(uint64(qBits), 16) + uint64(iBits);
    text = [text upper(dec2hex(laneWord, 8))]; %#ok<AGROW>
end
end

function text = pack_output_beat(values)
text = '';
for lane = 8:-1:1
    iBits = unsigned_bits(double(storedInteger(real(values(lane)))), 26);
    qBits = unsigned_bits(double(storedInteger(imag(values(lane)))), 26);
    laneWord = bitshift(uint64(qBits), 26) + uint64(iBits);
    text = [text upper(dec2hex(laneWord, 13))]; %#ok<AGROW>
end
end

function value = unsigned_bits(signedValue, width)
value = uint64(mod(signedValue, 2^width));
end

function text = describe_type(value)
nt = numerictype(value);
text = sprintf('s%d_En%d', nt.WordLength, nt.FractionLength);
end

function golden_log(fid, message)
fprintf('%s\n', message);
fprintf(fid, '%s\n', message);
end
