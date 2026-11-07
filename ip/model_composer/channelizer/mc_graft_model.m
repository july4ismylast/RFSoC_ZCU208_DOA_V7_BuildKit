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
clearContents(dut);
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
try
    wanted = get_param(hub, 'SubsystemName');
catch problem
    fprintf('  note: the Hub has no SubsystemName: %s\n', problem.message);
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

function clearContents(block)
%CLEARCONTENTS Delete every block inside a subsystem, keeping the subsystem.
inner = find_system(block, 'SearchDepth', 1, 'Type', 'Block');
for index = 1:numel(inner)
    try
        delete_block(inner{index});
    catch problem
        fprintf('  note: could not delete %s: %s\n', inner{index}, problem.message);
    end
end
end

function addChannels(subsys, settings)
%ADDCHANNELS Four gateway/delay/gateway paths inside the exported subsystem.
for channel = 1:settings.channels
    row = 30 + 60 * (channel - 1);
    inBlock = sprintf('%s/In%d', subsys, channel);
    delayBlock = sprintf('%s/Delay%d', subsys, channel);
    outBlock = sprintf('%s/Out%d', subsys, channel);

    add_block(['hdlBasic/Gateway In'], inBlock, 'Position', [40, row, 90, row + 20]);
    add_block(['hdlBasic/Delay'], delayBlock, 'Position', [160, row, 190, row + 20]);
    add_block(['hdlBasic/Gateway Out'], outBlock, 'Position', [250, row, 300, row + 20]);

    setParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    setParam(inBlock, 'arith_type', 'Signed  (2''s comp)');
    setParam(inBlock, 'n_bits', num2str(settings.bits));
    setParam(inBlock, 'bin_pt', num2str(settings.binaryPoint));
    setParam(inBlock, 'quantization', 'Truncate');
    setParam(inBlock, 'overflow', 'Wrap');
    setParam(inBlock, 'period', '1');
    setParam(delayBlock, 'latency', num2str(settings.tapDelay));

    try
        add_line(subsys, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel), ...
            'autorouting', 'on');
        add_line(subsys, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel), ...
            'autorouting', 'on');
    catch problem
        fprintf('  note: could not wire channel %d: %s\n', channel, problem.message);
    end
end
fprintf('design: %d channels inside %s\n', settings.channels, subsys);
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
setParam(hub, 'ExportType', 'IP Catalog');
setParam(hub, 'IpVendor', 'doa.v7');
setParam(hub, 'IpLibrary', 'model_composer');
setParam(hub, 'IpVersion', '1.0');
setParam(hub, 'IpHWLanguage', 'Verilog');
setParam(hub, 'CodeGeneration', 'on');
setParam(hub, 'TargetDirectory', settings.codeDir);
setParam(hub, 'directory', settings.netlistDir);
setParam(hub, 'ProjDevice', settings.part.full);
setParam(hub, 'ProjDevicePart', settings.part.full);
setParam(hub, 'part', settings.part.device);
setParam(hub, 'package', settings.part.package);
setParam(hub, 'speed', settings.part.speed);
setParam(hub, 'xilinxfamily', settings.part.family);
setParam(hub, 'ClockFrequency', num2str(settings.sampleHz / 1e6));
setParam(hub, 'SamplePeriod', '-1');
setParam(hub, 'SubsystemName', subsystemName);
setParam(hub, 'IpName', subsystemName);
setParam(hub, 'IPInfoJsonString', sprintf(['{"HDLSubsystem":{' ...
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
for parameter = {'ExportType', 'ProjDevice', 'part', 'SubsystemName'}
    name = parameter{1};
    try
        fprintf('  Hub.%s = %s\n', name, get_param(hubs{1}, name));
    catch problem
        fprintf('  Hub.%s = <%s>\n', name, problem.message);
    end
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
