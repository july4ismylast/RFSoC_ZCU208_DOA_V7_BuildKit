function make_channelizer_model(destination)
%MAKE_CHANNELIZER_MODEL Build the channelizer model from scratch, without a GUI.
%   A .slx is a binary that nobody can review, so the model lives here as code:
%   this function creates the model with new_system/add_block/add_line and saves
%   it as destination (default: channelizer.slx next to this file).
%
%   Two facts drove this file, both from real runs on the ZCU208 host:
%     - a batch session has none of the Model Composer library folders, so
%       mc_paths() finds and adds them first;
%     - the Hub refuses to run until a target device is selected, so the device
%       parameters (ProjDevice, part, package, speed, xilinxfamily) and the
%       IPInfoJsonString are set here, from MC_PART (the same PART the rest of
%       the build uses).
%
%   Popup parameters are not guessed: applyPopup reads the block's own mask
%   definition and picks the option that matches, printing the allowed list when
%   nothing matches.  A parameter that does not exist is reported and skipped.
arguments
    destination (1, :) char = ''
end

here = fileparts(mfilename('fullpath'));
if isempty(destination)
    destination = fullfile(here, 'channelizer.slx');
end
[modelDir, modelName] = fileparts(destination);
if isempty(modelDir)
    modelDir = here;
    destination = fullfile(modelDir, [modelName '.slx']);
end

channels = 4;
bits = 16;
binaryPoint = 14;
sampleHz = 200e6;
tapDelay = 4;
part = partString();

fprintf('looking for the Model Composer libraries\n');
info = mc_paths(); %#ok<NASGU>
requireLibrary('vmcUtilities');
requireLibrary('hdlBasic');

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if isfile(destination)
    delete(destination);
end

new_system(modelName);
cleanup = onCleanup(@() discardIfOpen(modelName)); %#ok<NASGU>
set_param(modelName, 'Solver', 'FixedStepDiscrete', ...
    'FixedStep', '1', 'StopTime', '16', 'SaveTime', 'off', 'SaveOutput', 'off');

% ---------------------------------------------------------------- the Hub ---
hub = [modelName '/Vitis Model Composer Hub'];
addFromLibrary('vmcUtilities', 'Vitis Model Composer Hub', hub, [40, 60, 90, 110]);
configureHub(hub, part, sampleHz);

% ------------------------------------------------------------ the channels ---
for channel = 1:channels
    row = 150 + 60 * (channel - 1);
    inBlock = sprintf('%s/In%d', modelName, channel);
    delayBlock = sprintf('%s/Delay%d', modelName, channel);
    outBlock = sprintf('%s/Out%d', modelName, channel);

    addFromLibrary('hdlBasic', 'Gateway In', inBlock, [40, row, 90, row + 20]);
    applyParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    applyPopup(inBlock, 'arith_type', 'Signed');
    applyParam(inBlock, 'n_bits', num2str(bits));
    applyParam(inBlock, 'bin_pt', num2str(binaryPoint));
    applyPopup(inBlock, 'quantization', 'Truncate');
    applyPopup(inBlock, 'overflow', 'Wrap');
    applyParam(inBlock, 'period', '1');

    addFromLibrary('hdlBasic', 'Delay', delayBlock, [160, row, 190, row + 20]);
    applyParam(delayBlock, 'latency', num2str(tapDelay));

    addFromLibrary('hdlBasic', 'Gateway Out', outBlock, [270, row, 320, row + 20]);
    applyPopup(outBlock, 'gui_display_data_type', 'Inherit');

    add_line(modelName, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel), ...
        'autorouting', 'on');
    add_line(modelName, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel), ...
        'autorouting', 'on');
end

% ------------------------------------------------------------------- save ----
save_system(modelName, destination);
fprintf('\nmodel created: %s\n', destination);
fprintf('  %d channels, %d.%d signed fixed point, %g MHz, %d-clock delay each\n', ...
    channels, bits - binaryPoint, binaryPoint, sampleHz / 1e6, tapDelay);
fprintf('  device: %s\n', part.full);
printHubSetting(hub, 'ExportType');
printHubSetting(hub, 'ProjDevice');
printHubSetting(hub, 'part');
close_system(modelName, 0);
fprintf('MC_MODEL_CREATED %s\n', destination);
end

% ---------------------------------------------------------------------------
function configureHub(hub, part, sampleHz)
%CONFIGUREHUB Everything the Hub needs before it will generate anything.
%   Parameter names and the need for a selected device come from a real 2023.2
%   model (Xilinx/Vitis_Model_Composer, branch 2023.2, SSRDDC.slx): ExportType,
%   IpVendor, IpLibrary, IpVersion, IpHWLanguage, ProjDevice, ProjDevicePart,
%   part, package, speed, xilinxfamily, ClockFrequency, SamplePeriod and
%   IPInfoJsonString.
applyPopup(hub, 'ExportType', 'IP Catalog');
applyParam(hub, 'IpVendor', 'doa.v7');
applyParam(hub, 'IpLibrary', 'model_composer');
applyParam(hub, 'IpVersion', '1.0');
applyParam(hub, 'IpHWLanguage', 'Verilog');
applyParam(hub, 'ProjDevice', part.full);
applyParam(hub, 'ProjDevicePart', part.full);
applyParam(hub, 'part', part.device);
applyParam(hub, 'package', part.package);
applyParam(hub, 'speed', part.speed);
applyParam(hub, 'xilinxfamily', part.family);
applyParam(hub, 'ClockFrequency', num2str(sampleHz / 1e6));
applyParam(hub, 'SamplePeriod', '-1');
applyParam(hub, 'sysclk_period', num2str(1e9 / sampleHz));
applyParam(hub, 'simulink_period', '1');
ipInfo = sprintf(['{"HDLSubsystem":{"SubsystemName":"channelizer_dut",' ...
    '"IPName":"channelizer_dut","IPLibrary":"model_composer",' ...
    '"IPVendor":"doa.v7","IPVersion":"1.0"}}']);
applyParam(hub, 'IPInfoJsonString', ipInfo);
end

% ---------------------------------------------------------------------------
function part = partString()
%PARTSTRING Device from MC_PART (the shell passes config.mk's PART), parsed.
full = getenv('MC_PART');
if isempty(full)
    full = 'xczu48dr-fsvg1517-2-e';
end
pieces = strsplit(full, '-');
part = struct('full', full, 'device', pieces{1}, 'package', '', 'speed', '', ...
    'family', 'zynquplus');
if numel(pieces) >= 2
    part.package = pieces{2};
end
if numel(pieces) >= 4
    part.speed = ['-' pieces{3} '-' pieces{4}];
end
if contains(part.device, 'zu')
    part.family = 'zynquplus';
elseif contains(part.device, 'ku')
    part.family = 'kintexuplus';
elseif contains(part.device, 'vu')
    part.family = 'virtexuplus';
end
end

% ---------------------------------------------------------------------------
function requireLibrary(name)
%REQUIRELIBRARY Load one Model Composer library, or explain what is missing.
try
    load_system(name);
    fprintf('library loaded: %s\n', name);
    return;
catch problem
    reason = problem.message;
end
fprintf('\nERROR: the Model Composer library "%s" could not be loaded.\n', name);
fprintf('  loaded error: %s\n', reason);
fprintf('  MC_ROOT:   %s\n', printablePath(getenv('MC_ROOT')));
fprintf('  MC_VIVADO_ROOT: %s\n', printablePath(getenv('MC_VIVADO_ROOT')));
fprintf(['  Diagnose with: make mc-libs, or run mc_paths() here and read the\n' ...
         '  library list it prints.  In a Model Composer GUI the libraries are\n' ...
         '  already loaded, so this failure means the model was built in a bare\n' ...
         '  MATLAB session without Model Composer on the path.\n']);
error('make_channelizer_model:library', 'library %s is not loadable', name);
end

function text = printablePath(value)
if isempty(value)
    text = '(unset)';
else
    text = value;
end
end

function addFromLibrary(library, blockName, path, position)
%ADDFROMLIBRARY Add one block, listing the library contents if the name is wrong.
try
    add_block([library '/' blockName], path, 'Position', position);
catch problem
    fprintf('\nERROR: add_block(''%s/%s'') failed: %s\n', library, blockName, problem.message);
    listLibrary(library);
    error('make_channelizer_model:block', 'cannot add %s/%s', library, blockName);
end
end

function listLibrary(library)
%LISTLIBRARY Print the top-level blocks of a library, so the right name is visible.
try
    load_system(library);
    blocks = find_system(library, 'SearchDepth', 1, 'Type', 'Block');
catch problem
    fprintf('  (cannot list %s: %s)\n', library, problem.message);
    return;
end
fprintf('  blocks available in %s (%d):\n', library, numel(blocks));
for index = 1:min(numel(blocks), 40)
    fprintf('    %s\n', blocks{index});
end
if numel(blocks) > 40
    fprintf('    ... %d more\n', numel(blocks) - 40);
end
end

function discardIfOpen(modelName)
%DISCARDIFOPEN Leave no half-built model behind when this function fails.
try
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
catch problem
    fprintf('note: could not close %s: %s\n', modelName, problem.message);
end
end

function printHubSetting(hub, parameter)
%PRINTHUBSETTING Show what the Hub actually holds now, not what we tried to set.
try
    fprintf('  Hub.%s = %s\n', parameter, get_param(hub, parameter));
catch problem
    fprintf('  Hub.%s = <%s>\n', parameter, problem.message);
end
end

function applyParam(block, parameter, value)
%APPLYPARAM Write one block parameter, printing whether it took.
try
    set_param(block, parameter, value);
    fprintf('  %s.%s = %s\n', shortName(block), parameter, value);
catch problem
    fprintf('  skipped %s.%s = %s (%s)\n', shortName(block), parameter, value, ...
        problem.message);
end
end

function applyPopup(block, parameter, wanted)
%APPLYPOPUP Choose a popup value from the block's own mask definition.
%   "Invalid setting ... for parameter 'arith_type'" means the string is not one
%   of the options this release offers; the options are readable, so read them.
options = popupOptions(block, parameter);
if isempty(options)
    applyParam(block, parameter, wanted);
    return;
end
match = find(contains(lower(options), lower(wanted)), 1);
if isempty(match)
    fprintf('  skipped %s.%s: no option matching "%s" (options: %s)\n', ...
        shortName(block), parameter, wanted, strjoin(options, ' | '));
    return;
end
applyParam(block, parameter, options{match});
end

function options = popupOptions(block, parameter)
%POPUPOPTIONS The allowed strings of a mask popup parameter.
options = {};
try
    mask = get_param(block, 'MaskObject');
    parameters = mask.Parameters;
    for index = 1:numel(parameters)
        if strcmp(parameters(index).Name, parameter)
            options = parameters(index).TypeOptions;
            return;
        end
    end
catch problem
    fprintf('  note: cannot read the mask of %s: %s\n', shortName(block), problem.message);
end
end

function name = shortName(block)
%SHORTNAME Last path element of a block path.
parts = strsplit(block, '/');
name = parts{end};
end
