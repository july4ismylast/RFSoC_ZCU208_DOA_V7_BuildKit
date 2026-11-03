function build_model()
%BUILD_MODEL Build the one-channel fixed-point HDL Coder harness.
%
% The production V06 values come from config.mk through the environment:
%   CHANNELIZER_NUM_BANDS       (default 1024)
%   WIDEBAND_SAMPLES_PER_CLOCK  (default 8)
%   CHANNELIZER_TAPS_PER_BAND   (default 12; V06_TAPS_PER_BAND override)
%   CHANNELIZER_STOPBAND_DB     (default 100; V06_STOPBAND_DB override)
%   CHANNELIZER_NORMALIZE       (default 0; V06_NORMALIZE override)
%   CHANNELIZER_FILTER_STRUCTURE (default systolic; V06_FILTER_STRUCTURE
%                                may select transposed for Gate-2T only)
%
% The legacy 64-band/four-lane configuration can still be reproduced by
% overriding those environment values, but it is no longer the default
% and is not V06 evidence.

numBands = env_integer('CHANNELIZER_NUM_BANDS', 1024);
samplesPerCycle = env_integer('WIDEBAND_SAMPLES_PER_CLOCK', 8);
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
    case 'transposed'
        filterStructure = 'Direct form transposed';
end

if numBands <= 0 || 2^nextpow2(numBands) ~= numBands
    error('V06:BadBandCount', 'CHANNELIZER_NUM_BANDS must be a power of two.');
end
if samplesPerCycle <= 0 || 2^nextpow2(samplesPerCycle) ~= samplesPerCycle || ...
        samplesPerCycle > numBands
    error('V06:BadSSR', ...
        'WIDEBAND_SAMPLES_PER_CLOCK must be a power of two <= NUM_BANDS.');
end
if tapsPerBand <= 0
    error('V06:BadTapCount', 'Taps per band must be positive.');
end
if ~ismember(normalizeFlag, [0 1])
    error('V06:BadNormalizeFlag', 'CHANNELIZER_NORMALIZE must be 0 or 1.');
end

model='zu48dr_channelizer_ip';
if bdIsLoaded(model), close_system(model,0); end
if exist([model '.slx'],'file'), delete([model '.slx']); end
new_system(model);

% Use the same prototype extraction path as the Gate-0 v2 probe.  Gate 0
% proved coeffs() and tf() are bit-identical for this R2024a design, but
% tf() is the MathWorks HDL-example path and gives an explicit FIR
% denominator check.
referenceChannelizer = dsp.Channelizer( ...
    NumFrequencyBands=numBands, ...
    NumTapsPerBand=tapsPerBand, ...
    StopbandAttenuation=stopbandDb);
[channelizerCoefficients, prototypeDenominator] = tf(referenceChannelizer);
release(referenceChannelizer);
expectedCoefficients = numBands * tapsPerBand;
if numel(channelizerCoefficients) ~= expectedCoefficients
    error('V06:CoefficientCount', ...
        'Prototype has %d coefficients, expected %d.', ...
        numel(channelizerCoefficients), expectedCoefficients);
end
if numel(prototypeDenominator) ~= 1 || double(prototypeDenominator(1)) ~= 1
    error('V06:UnexpectedPrototypeDenominator', ...
        'Prototype tf denominator is not scalar 1.');
end

modelWorkspace = get_param(model,'ModelWorkspace');
assignin(modelWorkspace,'doaChannelizerNumBands',numBands);
assignin(modelWorkspace,'doaChannelizerSamplesPerCycle',samplesPerCycle);
assignin(modelWorkspace,'doaChannelizerTapsPerBand',tapsPerBand);
assignin(modelWorkspace,'doaChannelizerStopbandDb',stopbandDb);
assignin(modelWorkspace,'doaChannelizerNormalize',logical(normalizeFlag));
assignin(modelWorkspace,'doaChannelizerCoefficients',channelizerCoefficients);

add_block('simulink/Sources/In1',[model '/dataIn'],'Position',[30 60 60 80], ...
    'OutDataTypeStr','fixdt(1,16,15)', ...
    'PortDimensions',sprintf('[%d 1]',samplesPerCycle), ...
    'SignalType','complex');
add_block('simulink/Sources/In1',[model '/validIn'],'Position',[30 120 60 140], ...
    'OutDataTypeStr','boolean','PortDimensions','[1 1]');

% HDL Coder requires a model or Subsystem as its DUT. Keep the MATLAB System
% block one level below an explicit atomic subsystem so makehdl can generate a
% stable Channelizer_DUT module and interface.
dut=[model '/Channelizer_DUT'];
add_block('built-in/Subsystem',dut,'Position',[130 45 350 155], ...
    'TreatAsAtomicUnit','on');
add_block('simulink/Sources/In1',[dut '/dataIn'],'Position',[25 35 55 55], ...
    'Port','1');
add_block('simulink/Sources/In1',[dut '/validIn'],'Position',[25 95 55 115], ...
    'Port','2');
core=[dut '/ChannelizerCore'];
add_block('simulink/User-Defined Functions/MATLAB System',core, ...
    'Position',[115 25 305 125]);
set_param(core,'System','ZU48DRChannelizer');
% FilterStructure is constrained to a finite option list, so the
% MATLAB System mask expects the selected option value itself.  R2024a
% does not resolve a model-workspace variable name for this option
% parameter (Gate-1 transposed attempt 1 failed with "Option specified
% is not valid").  Pass the exact validated architecture string;
% build_model is rerun for every Gate-1 generation, so no stale model
% workspace value can change the selected architecture.
set_param(core, ...
    'NumBands','doaChannelizerNumBands', ...
    'Coefficients','doaChannelizerCoefficients', ...
    'FilterStructure',filterStructure, ...
    'NormalizeFFT','doaChannelizerNormalize');
add_block('simulink/Sinks/Out1',[dut '/dataOut'],'Position',[365 35 395 55], ...
    'Port','1');
add_block('simulink/Sinks/Out1',[dut '/validOut'],'Position',[365 95 395 115], ...
    'Port','2');
add_line(dut,'dataIn/1','ChannelizerCore/1');
add_line(dut,'validIn/1','ChannelizerCore/2');
add_line(dut,'ChannelizerCore/1','dataOut/1');
add_line(dut,'ChannelizerCore/2','validOut/1');

add_block('simulink/Sinks/Out1',[model '/dataOut'],'Position',[420 60 450 80]);
add_block('simulink/Sinks/Out1',[model '/validOut'],'Position',[420 120 450 140]);
add_line(model,'dataIn/1','Channelizer_DUT/1');
add_line(model,'validIn/1','Channelizer_DUT/2');
add_line(model,'Channelizer_DUT/1','dataOut/1');
add_line(model,'Channelizer_DUT/2','validOut/1');
set_param(model,'SolverType','Fixed-step','Solver','FixedStepDiscrete','StopTime','256');
set_param(model,'SimulationCommand','update');
save_system(model);
fprintf(['Created fixed-point vector harness %s.slx: %d bands, ' ...
    '%d samples/cycle, %d taps/band, %d coefficients, %d dB, ' ...
    'Normalize=%d, FilterStructure=%s.\n'], model, numBands, ...
    samplesPerCycle, tapsPerBand, numel(channelizerCoefficients), ...
    stopbandDb, normalizeFlag, filterStructure);
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
