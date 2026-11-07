function make_channelizer_model(destination)
%MAKE_CHANNELIZER_MODEL Build the channelizer model from scratch, without a GUI.
%   A .slx is a binary that nobody can review, so the model lives here as code:
%   this function creates the model and saves it as destination (default:
%   channelizer.slx next to this file).
%
%   Two routes, chosen automatically:
%
%   1. TEMPLATE (preferred).  If a Model Composer example is available
%      (build/mc_examples/*.slx, fetched by `make mc-example`, or MC_TEMPLATE),
%      the Hub block is taken from that model: a Hub created by AMD's own
%      example is initialised -- its S-function already knows the hardware
%      selection machinery -- whereas a Hub made with add_block on a fresh model
%      reported "Target hardware is not selected" for every sysgen block even
%      with ProjDevice, part, package and speed all set.  Everything except the
%      Hub is deleted, our four channels are added, and the device is re-pointed
%      at this board.
%
%   2. FROM SCRATCH.  With no template, the Hub is added from the library and
%      configured the same way.  That route is kept because it needs no
%      download, but it is the one that hit the hardware error.
%
%   In both routes the device comes from MC_PART (config.mk's PART), popup
%   parameters are read from the block's own mask definition, and a parameter
%   that does not exist is reported and skipped instead of aborting.
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

settings = struct('channels', 4, 'bits', 16, 'binaryPoint', 14, ...
    'sampleHz', 200e6, 'tapDelay', 4, 'part', partString());

fprintf('looking for the Model Composer libraries\n');
mc_paths();
requireLibrary('vmcUtilities');
requireLibrary('hdlBasic');

if isfile(destination)
    delete(destination);
end

template = findTemplate();
if isempty(template)
    fprintf('route: from scratch (no template model found)\n');
    buildFromScratch(modelName, destination, settings);
else
    fprintf('route: template %s\n', template);
    buildFromTemplate(template, destination, settings);
end

if ~isfile(destination)
    error('make_channelizer_model:save', 'the model was not written to %s', destination);
end
fprintf('MC_MODEL_CREATED %s\n', destination);
end

% ---------------------------------------------------------------------------
function template = findTemplate()
%FINDTEMPLATE A Model Composer example to take the Hub block from.
template = '';
fromEnv = getenv('MC_TEMPLATE');
if ~isempty(fromEnv) && isfile(fromEnv)
    template = fromEnv;
    return;
end
here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(here)));
candidates = dir(fullfile(repoRoot, 'build', 'mc_examples', '*.slx'));
if ~isempty(candidates)
    template = fullfile(candidates(1).folder, candidates(1).name);
end
end

% ---------------------------------------------------------------------------
function buildFromTemplate(template, destination, settings)
%BUILDFROMTEMPLATE Keep the template's Hub, replace everything else.
[~, templateName] = fileparts(template);
if bdIsLoaded(templateName)
    close_system(templateName, 0);
end
load_system(template);
cleanup = onCleanup(@() closeQuietly(templateName)); %#ok<NASGU>

hubs = mc_find_hub(templateName);
if isempty(hubs)
    error('make_channelizer_model:hub', 'no Hub block in the template %s', template);
end
hub = hubs{1};
fprintf('template Hub: %s\n', hub);

% Remove everything except the Hub (and the annotations that go with it).
blocks = find_system(templateName, 'SearchDepth', 1, 'Type', 'Block');
for index = 1:numel(blocks)
    if strcmp(blocks{index}, hub)
        continue;
    end
    try
        delete_block(blocks{index});
    catch problem
        fprintf('  note: could not delete %s: %s\n', blocks{index}, problem.message);
    end
end
try
    annotations = find_system(templateName, 'SearchDepth', 1, ...
        'FindAll', 'on', 'Type', 'annotation');
    for index = 1:numel(annotations)
        delete(annotations(index));
    end
catch problem
    fprintf('  note: annotations left in place: %s\n', problem.message);
end

% The template's PreLoadFcn defines variables its own design needed (clk, Tclk,
% filter coefficients); ours does not, and a missing variable would abort the
% update.
try
    set_param(templateName, 'PreLoadFcn', '', 'InitFcn', '', 'StartFcn', '');
catch problem
    fprintf('  note: could not clear the model callbacks: %s\n', problem.message);
end

addChannels(templateName, settings, false);
configureHub(hub, settings);

if bdIsLoaded(destinationName(destination))
    close_system(destinationName(destination), 0);
end
save_system(templateName, destination);
fprintf('saved %s\n', destination);
% save_system renames the model, so the Hub's old path no longer resolves; look
% it up again before reporting what it holds.
reportHub(destination);
printSummary(settings);
end

% ---------------------------------------------------------------------------
function buildFromScratch(modelName, destination, settings)
%BUILDFROMSCRATCH Hub from the library, channels, save.
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
new_system(modelName);
cleanup = onCleanup(@() closeQuietly(modelName)); %#ok<NASGU>
set_param(modelName, 'Solver', 'FixedStepDiscrete', ...
    'FixedStep', '1', 'StopTime', '16', 'SaveTime', 'off', 'SaveOutput', 'off');

hub = [modelName '/Vitis Model Composer Hub'];
addFromLibrary('vmcUtilities', 'Vitis Model Composer Hub', hub, [40, 60, 90, 110]);
configureHub(hub, settings);
addChannels(modelName, settings, true);

save_system(modelName, destination);
fprintf('saved %s\n', destination);
reportHub(destination);
printSummary(settings);
end

% ---------------------------------------------------------------------------
function addChannels(modelName, settings, addToExisting)
%ADDCHANNELS Four gateway/delay/gateway paths: the part the Hub turns into IP.
for channel = 1:settings.channels
    row = 150 + 60 * (channel - 1);
    inBlock = sprintf('%s/In%d', modelName, channel);
    delayBlock = sprintf('%s/Delay%d', modelName, channel);
    outBlock = sprintf('%s/Out%d', modelName, channel);

    if addToExisting
        addFromLibrary('hdlBasic', 'Gateway In', inBlock, [40, row, 90, row + 20]);
        addFromLibrary('hdlBasic', 'Delay', delayBlock, [160, row, 190, row + 20]);
        addFromLibrary('hdlBasic', 'Gateway Out', outBlock, [270, row, 320, row + 20]);
    else
        copyFromLibrary('hdlBasic', 'Gateway In', inBlock, [40, row, 90, row + 20]);
        copyFromLibrary('hdlBasic', 'Delay', delayBlock, [160, row, 190, row + 20]);
        copyFromLibrary('hdlBasic', 'Gateway Out', outBlock, [270, row, 320, row + 20]);
    end

    applyParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    applyPopup(inBlock, 'arith_type', 'Signed');
    applyParam(inBlock, 'n_bits', num2str(settings.bits));
    applyParam(inBlock, 'bin_pt', num2str(settings.binaryPoint));
    applyPopup(inBlock, 'quantization', 'Truncate');
    applyPopup(inBlock, 'overflow', 'Wrap');
    applyParam(inBlock, 'period', '1');

    applyParam(delayBlock, 'latency', num2str(settings.tapDelay));

    try
        add_line(modelName, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel), ...
            'autorouting', 'on');
        add_line(modelName, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel), ...
            'autorouting', 'on');
    catch problem
        fprintf('  note: could not wire channel %d: %s\n', channel, problem.message);
    end
end
end

% ---------------------------------------------------------------------------
function name = destinationName(destination)
[~, name] = fileparts(destination);
end

function closeQuietly(modelName)
try
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
catch problem
    fprintf('note: could not close %s: %s\n', modelName, problem.message);
end
end

function configureHub(hub, settings)
%CONFIGUREHUB Everything the Hub needs before it will generate anything.
applyPopup(hub, 'ExportType', 'IP Catalog');
applyParam(hub, 'IpVendor', 'doa.v7');
applyParam(hub, 'IpLibrary', 'model_composer');
applyParam(hub, 'IpVersion', '1.0');
applyParam(hub, 'IpHWLanguage', 'Verilog');
% A real Generate presses these two first: the example Hub ships with
% CodeGeneration off and a relative TargetDirectory, and xmcGenerate reads them.
applyPopup(hub, 'CodeGeneration', 'on');
applyParam(hub, 'TargetDirectory', './code');
applyParam(hub, 'ProjDevice', settings.part.full);
applyParam(hub, 'ProjDevicePart', settings.part.full);
applyParam(hub, 'part', settings.part.device);
applyParam(hub, 'package', settings.part.package);
applyParam(hub, 'speed', settings.part.speed);
applyParam(hub, 'xilinxfamily', settings.part.family);
applyParam(hub, 'ClockFrequency', num2str(settings.sampleHz / 1e6));
applyParam(hub, 'SamplePeriod', '-1');
applyParam(hub, 'sysclk_period', num2str(1e9 / settings.sampleHz));
applyParam(hub, 'simulink_period', '1');
applyParam(hub, 'IPInfoJsonString', sprintf(['{"HDLSubsystem":{' ...
    '"SubsystemName":"channelizer_dut","IPName":"channelizer_dut",' ...
    '"IPLibrary":"model_composer","IPVendor":"doa.v7","IPVersion":"1.0"}}']));
end

function printSummary(settings)
fprintf('  %d channels, %d.%d signed fixed point, %g MHz, %d-clock delay each\n', ...
    settings.channels, settings.bits - settings.binaryPoint, settings.binaryPoint, ...
    settings.sampleHz / 1e6, settings.tapDelay);
fprintf('  device: %s\n', settings.part.full);
end

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
if contains(part.device, 'ku')
    part.family = 'kintexuplus';
elseif contains(part.device, 'vu')
    part.family = 'virtexuplus';
end
end

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
fprintf('  MC_ROOT:        %s\n', printablePath(getenv('MC_ROOT')));
fprintf('  MC_VIVADO_ROOT: %s\n', printablePath(getenv('MC_VIVADO_ROOT')));
fprintf('  Diagnose with: make mc-libs\n');
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

function copyFromLibrary(library, blockName, path, position)
%COPYFROMLIBRARY Same as addFromLibrary, used when the model already exists.
addFromLibrary(library, blockName, path, position);
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

function reportHub(destination)
%REPORTHUB Print the device settings of the Hub in the saved model.
[~, savedName] = fileparts(destination);
hubs = mc_find_hub(savedName);
if isempty(hubs)
    fprintf('  (no Hub found in %s)\n', savedName);
    return;
end
fprintf('  Hub in %s: %s\n', savedName, hubs{1});
printHubSetting(hubs{1}, 'ExportType');
printHubSetting(hubs{1}, 'ProjDevice');
printHubSetting(hubs{1}, 'part');
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
