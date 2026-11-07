function make_channelizer_model(destination)
%MAKE_CHANNELIZER_MODEL Build the channelizer model from scratch, without a GUI.
%   A .slx is a binary nobody can review, so the model lives here as code: this
%   function creates it and saves it as destination (default: channelizer.slx
%   next to this file).
%
%   Shape of the model -- this is what a real run finally proved:
%
%       channelizer.slx
%         System Generator            (the Hub: device, export target)
%         channelizer_dut             (a SUBSYSTEM with the same name the Hub's
%           In1 -> Delay1 -> Out1       SubsystemName field holds)
%           ... four channels ...
%
%   The Hub's `SubsystemName` names a block, and Model Composer exports *that*
%   block.  AMD's working example has a `DDC_DUT` subsystem for exactly this
%   reason.  With the gateways loose at the top level there is no block with that
%   name, and xmcGenerate dies inside vmcGenerate.p with
%   "Index exceeds the number of array elements. Index must not exceed 0." --
%   the empty result of that lookup.
%
%   Two routes, chosen automatically:
%   1. TEMPLATE (preferred): take the Hub from an AMD example (build/mc_examples,
%      fetched by `make mc-example`, or MC_TEMPLATE).  A Hub created by add_block
%      on a fresh model reported "Target hardware is not selected" for every
%      sysgen block no matter which parameters were set.
%   2. FROM SCRATCH: Hub straight from the library; kept for the no-download case.
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
    'sampleHz', 200e6, 'tapDelay', 4, 'subsystemName', 'channelizer_dut', ...
    'modelDir', modelDir, 'part', mc_part_string());
% Model Composer resolves the Hub's netlist and target directories against the
% current working directory unless they are absolute.  A real run of AMD's own
% example died with
%     ERROR-XMC-1002: Failed to create and open file ./netlist/make.sh
% so both directories are made absolute (model folder) and created here.
settings.netlistDir = fullfile(modelDir, 'netlist');
settings.codeDir = fullfile(modelDir, 'code');
makeFolder(settings.netlistDir);
makeFolder(settings.codeDir);

fprintf('looking for the Model Composer libraries\n');
mc_paths();
requireLibrary('vmcUtilities');
requireLibrary('hdlBasic');

if isfile(destination)
    delete(destination);
end

template = findTemplate();
if isempty(template)
    fprintf('route: from scratch (no example model found)\n');
    buildFromScratch(modelName, destination, settings);
else
    fprintf('route: graft onto %s\n', template);
    mc_graft_model(template, destination, settings);
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
function buildFromScratch(modelName, destination, settings)
%BUILDFROMSCRATCH Hub from the library, DUT subsystem, save.
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
new_system(modelName);
cleanup = onCleanup(@() closeQuietly(modelName)); %#ok<NASGU>
setSolver(modelName);

hub = [modelName '/System Generator'];
addFromLibrary('vmcUtilities', 'Vitis Model Composer Hub', hub, [40, 60, 90, 110]);
configureHub(hub, settings);
addDut(modelName, settings);

save_system(modelName, destination);
fprintf('saved %s\n', destination);
reportHub(destination);
printSummary(settings);
end

% ---------------------------------------------------------------------------
function subsys = addDut(modelName, settings)
%ADDDUT The subsystem the Hub exports: four gateway/delay/gateway channels.
%   Its name must equal the Hub's SubsystemName; that is the block Model Composer
%   generates an IP for.
subsys = [modelName '/' settings.subsystemName];
deleteIfPresent(subsys);
height = 100 + 60 * settings.channels;
add_block('built-in/Subsystem', subsys, 'Position', [320, 60, 620, height]);

for channel = 1:settings.channels
    row = 30 + 60 * (channel - 1);
    inBlock = sprintf('%s/In%d', subsys, channel);
    delayBlock = sprintf('%s/Delay%d', subsys, channel);
    outBlock = sprintf('%s/Out%d', subsys, channel);

    addFromLibrary('hdlBasic', 'Gateway In', inBlock, [40, row, 90, row + 20]);
    addFromLibrary('hdlBasic', 'Delay', delayBlock, [160, row, 190, row + 20]);
    addFromLibrary('hdlBasic', 'Gateway Out', outBlock, [250, row, 300, row + 20]);

    applyParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    applyPopup(inBlock, 'arith_type', 'Signed');
    applyParam(inBlock, 'n_bits', num2str(settings.bits));
    applyParam(inBlock, 'bin_pt', num2str(settings.binaryPoint));
    applyPopup(inBlock, 'quantization', 'Truncate');
    applyPopup(inBlock, 'overflow', 'Wrap');
    applyParam(inBlock, 'period', '1');

    applyParam(delayBlock, 'latency', num2str(settings.tapDelay));

    try
        add_line(subsys, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel), ...
            'autorouting', 'on');
        add_line(subsys, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel), ...
            'autorouting', 'on');
    catch problem
        fprintf('  note: could not wire channel %d: %s\n', channel, problem.message);
    end
end
fprintf('DUT subsystem: %s\n', subsys);
end

% ---------------------------------------------------------------------------
function configureHub(hub, settings)
%CONFIGUREHUB Everything the Hub needs before it will generate anything.
applyPopup(hub, 'ExportType', 'IP Catalog');
applyParam(hub, 'IpVendor', 'doa.v7');
applyParam(hub, 'IpLibrary', 'model_composer');
applyParam(hub, 'IpVersion', '1.0');
applyParam(hub, 'IpHWLanguage', 'Verilog');
% A real Generate presses these first: the example Hub ships with
% CodeGeneration off and a relative TargetDirectory, and xmcGenerate reads them.
applyPopup(hub, 'CodeGeneration', 'on');
applyParam(hub, 'TargetDirectory', settings.codeDir);
applyParam(hub, 'directory', settings.netlistDir);
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
% The subsystem that gets exported.  Empty here is what made xmcGenerate index an
% empty lookup, together with not having a block of that name in the model.
applyParam(hub, 'SubsystemName', settings.subsystemName);
applyParam(hub, 'IpName', settings.subsystemName);
applyParam(hub, 'IPInfoJsonString', sprintf(['{"HDLSubsystem":{' ...
    '"SubsystemName":"%s","IPName":"%s",' ...
    '"IPLibrary":"model_composer","IPVendor":"doa.v7","IPVersion":"1.0"}}'], ...
    settings.subsystemName, settings.subsystemName));
end

function makeFolder(path)
%MAKEFOLDER Create the netlist/target folder so the engine can write into it.
if ~isfolder(path)
    try
        mkdir(path);
    catch problem
        fprintf('  note: could not create %s: %s\n', path, problem.message);
    end
end
end

function printSummary(settings)
fprintf('  %d channels, %d.%d signed fixed point, %g MHz, %d-clock delay each\n', ...
    settings.channels, settings.bits - settings.binaryPoint, settings.binaryPoint, ...
    settings.sampleHz / 1e6, settings.tapDelay);
fprintf('  device: %s, exported subsystem: %s\n', settings.part.full, ...
    settings.subsystemName);
end

function setSolver(modelName)
%SETSOLVER Fixed-step discrete, one step per sample: what Model Composer needs.
try
    set_param(modelName, 'Solver', 'FixedStepDiscrete', 'FixedStep', '1', ...
        'StopTime', '16', 'SaveTime', 'off', 'SaveOutput', 'off');
catch problem
    fprintf('  note: could not set the solver: %s\n', problem.message);
end
end

function deleteIfPresent(block)
try
    if getSimulinkBlockHandle(block) ~= -1
        delete_block(block);
    end
catch problem
    fprintf('  note: could not clear %s: %s\n', block, problem.message);
end
end

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
printHubSetting(hubs{1}, 'SubsystemName');
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
