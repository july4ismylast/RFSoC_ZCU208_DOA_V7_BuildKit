function mc_graft_model(template, destination, settings)
%MC_GRAFT_MODEL Build the model on top of AMD's working example.
%   AMD's example reaches the HDL compiler in this install (`vmcGenerateCode/
%   generateHDLCode` -> XilinxCompiler), while a model assembled from a copied Hub
%   dies earlier inside vmcGenerate.p with an index error.  So the example becomes
%   the base model: keep its Hub and its DUT subsystem, replace the subsystem's
%   contents with our four channels, delete everything else, retarget the device.
%
%   Nothing of AMD's design survives the replacement; what is kept is the model
%   machinery that the engine expects (Hub instance, subsystem, model callbacks).
arguments
    template (1, :) char
    destination (1, :) char
    settings struct
end
[~, modelName] = fileparts(destination);
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
mc_require_libraries(false);
copyfile(template, destination);
open_system(destination);   % runs the model's PreLoadFcn: clk, Tclk, ...
cleanup = onCleanup(@() closeQuietly(modelName)); %#ok<NASGU>

hubs = mc_find_hub(modelName);
if isempty(hubs)
    error('mc_graft_model:hub', 'no Hub block in the base model %s', template);
end
hub = hubs{1};
fprintf('base model: %s\n', template);
fprintf('base Hub:   %s\n', hub);

dut = findDut(modelName, hub);
fprintf('base DUT:   %s\n', dut);
dut = emptySubsystem(dut);
addChannels(dut, settings);

% Everything else at the top level belonged to AMD's design.
blocks = find_system(modelName, 'SearchDepth', 1, 'Type', 'Block');
for index = 1:numel(blocks)
    path = blocks{index};
    if strcmp(path, hub) || strcmp(path, dut)
        continue;
    end
    try
        delete_block(path);
    catch problem
        fprintf('  note: could not delete %s: %s\n', path, problem.message);
    end
end

% The example's StopFcn uses a variable its StartFcn defines; a programmatic
% generation runs the model with sim and tripped over it.
try
    set_param(modelName, 'StopFcn', '');
catch problem
    fprintf('  note: could not clear StopFcn: %s\n', problem.message);
end

parts = strsplit(dut, '/');
settings.subsystemName = parts{end};
configureHub(hub, settings, settings.subsystemName);
save_system(modelName);
fprintf('saved %s\n', destination);
reportHub(destination, settings.subsystemName);
end

% ---------------------------------------------------------------------------
function dut = findDut(modelName, hub)
%FINDDUT The subsystem the Hub exports.
wanted = '';
text = mc_hub_get(hub, 'IPInfoJsonString');
if ~isempty(text)
    try
        information = jsondecode(text);
        wanted = information.HDLSubsystem.SubsystemName;
    catch
        wanted = '';
    end
end
candidates = {};
if ~isempty(wanted)
    candidates{end + 1} = [modelName '/' wanted];
end
candidates{end + 1} = [modelName '/DDC_DUT'];
subsystems = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'SubSystem');
candidates = [candidates, subsystems(:)'];
for index = 1:numel(candidates)
    if getSimulinkBlockHandle(candidates{index}) ~= -1
        dut = candidates{index};
        return;
    end
end
error('mc_graft_model:dut', 'no subsystem to fill in %s', modelName);
end

function block = emptySubsystem(block)
%EMPTYSUBSYSTEM Keep the name, remove everything inside, keep it editable.
%   A real run could not delete the example's blocks one by one
%   ("Invalid Simulink object name") and then could not add ours either: the
%   subsystem is a library-linked instance, whose contents cannot be edited or
%   extended in place.  So: detach the link, empty it with the supported API, and
%   if anything is still there, recreate the subsystem under the same name -- the
%   name is what the Hub's IPInfoJsonString refers to.
detachLink(block);
try
    Simulink.SubSystem.deleteContents(block);
catch problem
    fprintf('  note: deleteContents failed: %s\n', problem.message);
end
remaining = find_system(block, 'SearchDepth', 1, 'Type', 'Block');
if isempty(remaining)
    fprintf('  emptied %s\n', block);
    return;
end
fprintf('  %d block(s) left in %s; recreating the subsystem\n', numel(remaining), block);
position = [320, 60, 660, 100 + 60 * 4];
delete_block(block);
add_block('built-in/Subsystem', block, 'Position', position);
fprintf('  recreated %s\n', block);
end

function detachLink(block)
%DETACHLINK Library-linked subsystems refuse block deletion and addition.
try
    status = get_param(block, 'LinkStatus');
catch problem
    fprintf('  note: no link status on %s: %s\n', block, problem.message);
    return;
end
if strcmp(status, 'none')
    return;
end
try
    set_param(block, 'LinkStatus', 'none');
    fprintf('  detached library link from %s (was %s)\n', block, status);
catch problem
    fprintf('  note: could not detach the link (%s): %s\n', status, problem.message);
end
end

function addChannels(subsys, settings)
%ADDCHANNELS Four gateway/delay/gateway paths inside the exported subsystem.
% The exported subsystem needs real Inport and Outport blocks.  AMD's DDC_DUT
% has three Inports and two Outports; a subsystem made only of gateways has none,
% and the engine walks that port list -- an empty list is the index error this
% builder has been chasing.
for channel = 1:settings.channels
    row = 30 + 60 * (channel - 1);
    inPort = sprintf('%s/InPort%d', subsys, channel);
    inBlock = sprintf('%s/In%d', subsys, channel);
    delayBlock = sprintf('%s/Delay%d', subsys, channel);
    outBlock = sprintf('%s/Out%d', subsys, channel);
    outPort = sprintf('%s/OutPort%d', subsys, channel);

    addOrReplace('built-in/Inport', inPort, [10, row + 3, 30, row + 17]);
    addOrReplace('hdlBasic/Gateway In', inBlock, [45, row, 95, row + 20]);
    addOrReplace('hdlBasic/Delay', delayBlock, [130, row, 160, row + 20]);
    addOrReplace('hdlBasic/Gateway Out', outBlock, [195, row, 245, row + 20]);
    addOrReplace('built-in/Outport', outPort, [275, row + 3, 295, row + 17]);

    setParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    setParam(inBlock, 'arith_type', 'Signed  (2''s comp)');
    setParam(inBlock, 'n_bits', num2str(settings.bits));
    setParam(inBlock, 'bin_pt', num2str(settings.binaryPoint));
    setParam(inBlock, 'quantization', 'Truncate');
    setParam(inBlock, 'overflow', 'Wrap');
    setParam(inBlock, 'period', '1');
    setParam(delayBlock, 'latency', num2str(settings.tapDelay));

    wire(subsys, sprintf('InPort%d/1', channel), sprintf('In%d/1', channel), channel);
    wire(subsys, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel), channel);
    wire(subsys, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel), channel);
    wire(subsys, sprintf('Out%d/1', channel), sprintf('OutPort%d/1', channel), channel);
end
fprintf('design: %d channels inside %s\n', settings.channels, subsys);
end

function wire(subsys, source, destination, channel)
%WIRE One connection inside the subsystem, reported by channel.
try
    add_line(subsys, source, destination, 'autorouting', 'on');
catch problem
    fprintf('  note: could not wire %s -> %s (channel %d): %s\n', ...
        source, destination, channel, problem.message);
end
end

function addOrReplace(source, path, position)
%ADDORREPLACE Add a block, replacing one that is already at that path.
try
    add_block(source, path, 'Position', position);
catch problem
    if getSimulinkBlockHandle(path) == -1
        rethrow(problem);
    end
    delete_block(path);
    add_block(source, path, 'Position', position);
end
end

function setParam(block, parameter, value)
%SETPARAM Write one parameter, printing whether it took.
try
    set_param(block, parameter, value);
    fprintf('  %s.%s = %s\n', lastPart(block), parameter, value);
catch problem
    fprintf('  skipped %s.%s = %s (%s)\n', lastPart(block), parameter, value, ...
        problem.message);
end
end

function name = lastPart(path)
parts = strsplit(path, '/');
name = parts{end};
end

function configureHub(hub, settings, subsystemName)
%CONFIGUREHUB Everything the Hub needs before it will generate anything.
mc_hub_set(hub, 'ExportType', 'IP Catalog');
mc_hub_set(hub, 'IpVendor', 'doa.v7');
mc_hub_set(hub, 'IpLibrary', 'model_composer');
mc_hub_set(hub, 'IpVersion', '1.0');
mc_hub_set(hub, 'IpHWLanguage', 'Verilog');
mc_hub_set(hub, 'CodeGeneration', 'on');
mc_hub_set(hub, 'TargetDirectory', settings.codeDir);
mc_hub_set(hub, 'directory', settings.netlistDir);
mc_hub_set(hub, 'ProjDevice', settings.part.full);
mc_hub_set(hub, 'ProjDevicePart', settings.part.full);
mc_hub_set(hub, 'part', settings.part.device);
mc_hub_set(hub, 'package', settings.part.package);
mc_hub_set(hub, 'speed', settings.part.speed);
mc_hub_set(hub, 'xilinxfamily', settings.part.family);
mc_hub_set(hub, 'ClockFrequency', num2str(settings.sampleHz / 1e6));
mc_hub_set(hub, 'SamplePeriod', '-1');
% Our gateways run at Simulink period 1 and a 200 MHz clock.  Inheriting the
% example's expressions ((1e+9)/clk, 1/clk) produced
%   'Simulink system period' ... smaller than required for the rates in the design
% in the engine's own log, so both are written explicitly.
mc_hub_set(hub, 'sysclk_period', num2str(1e9 / settings.sampleHz));
mc_hub_set(hub, 'simulink_period', '1');
% The exported block is named in IPInfoJsonString only: a 2023.2 Hub has no
% SubsystemName and no IpName parameter, so writes to those were skipped.
mc_hub_set(hub, 'IPInfoJsonString', sprintf(['{"HDLSubsystem":{' ...
    '"SubsystemName":"%s","IPName":"%s",' ...
    '"IPLibrary":"model_composer","IPVendor":"doa.v7","IPVersion":"1.0"}}'], ...
    subsystemName, subsystemName));
end

function reportHub(destination, subsystemName)
%REPORTHUB Show what actually got saved.
[~, savedName] = fileparts(destination);
hubs = mc_find_hub(savedName);
if isempty(hubs)
    fprintf('  (no Hub found in %s)\n', savedName);
    return;
end
fprintf('  Hub in %s: %s\n', savedName, hubs{1});
for parameter = {'ExportType', 'ProjDevice', 'part', 'IPInfoJsonString'}
    fprintf('  Hub.%s = %s\n', parameter{1}, mc_hub_get(hubs{1}, parameter{1}));
end
fprintf('  exported subsystem: %s/%s\n', savedName, subsystemName);
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
