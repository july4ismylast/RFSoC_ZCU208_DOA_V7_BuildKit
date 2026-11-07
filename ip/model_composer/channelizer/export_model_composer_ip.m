function export_model_composer_ip(modelPath)
%EXPORT_MODEL_COMPOSER_IP Validate a Model Composer model and export its IP.
%   Works with both shapes of the Model Composer "generate" block:
%     - 2023.x: vmcUtilities/Vitis Model Composer Hub  (SourceType "VMC Hub")
%     - older : the System Generator token          (MaskType "Xilinx System
%               Generator"), still what many tutorials show
%   so a model copied from any of them can be exported here.
%
%   It sets the Hub's export target to IP Catalog when it can, runs the token,
%   then copies the newest component.xml into $(IP_REPO)/model_composer_channelizer.
arguments
    modelPath (1, :) char
end

assert(isfile(modelPath), 'Model Composer model not found: %s', modelPath);
[folder, model] = fileparts(modelPath);
addpath(folder);
% Run generation from the model's own folder.  Model Composer resolves its netlist
% directory against the working directory, and a real run of AMD's own example died
% with "ERROR-XMC-1002: Failed to create and open file ./netlist/ip/Makefile".
originalFolder = pwd;
cd(folder);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
for created = {fullfile(folder, 'netlist'), fullfile(folder, 'netlist', 'ip'), ...
        fullfile(folder, 'code')}
    if ~isfolder(created{1})
        mkdir(created{1});
    end
end
fprintf('working folder: %s\n', pwd);
load_system(model);
% The Hub rejects the update until a device is selected, and MATLAB then reports
% only "Error due to multiple causes"; print the causes and the Hub's device
% settings so the log says which block and which parameter.
try
    set_param(model, 'SimulationCommand', 'update');
catch problem
    mc_report_error(problem, 'model update');
    printHubDevice(model);
    rethrow(problem);
end

generator = mc_find_hub(model);
assert(~isempty(generator), ...
    ['No Vitis Model Composer Hub / System Generator token in %s. Add one at ' ...
     'the top level: Library Browser > AMD Toolbox > Utilities > Code ' ...
     'Generation > Vitis Model Composer Hub (or run make mc-scratch to build ' ...
     'a model that already has it).'], model);

target = setExportTarget(generator{1});
fprintf('generate block: %s\n', generator{1});
fprintf('export target:  %s\n', target);

checkSubsystemName(model, generator{1});
makeDirParametersAbsolute(generator{1}, folder);
groundUnconnectedInputs(generator{1}, model);

[name, available] = mc_generate_function();
fprintf('generate entry: %s\n', available{:});
if isempty(name)
    error('export_model_composer_ip:generate', ...
        ['No scripted generate function exists in this session, so the build ' ...
         'cannot be started from the command line: click Generate in the ' ...
         'Vitis Model Composer Hub block (Hardware Selection tab filled in), ' ...
         'then run `make mc-verify`.  Checked: %s.  Run mc_probe_generate() ' ...
         'to list what this installation does provide.'], strjoin(available, ', '));
end
baseline = now;
mc_call_generator(name, model, generator{1}, folder);

% Generation may be asynchronous in the GUI; wait for the artefact rather than
% assuming the call returned after the work.
started = tic;
component = waitForComponent(folder, model, baseline, 900);

ipRepo = getenv('IP_REPO');
assert(~isempty(ipRepo), 'IP_REPO is not set; run this through make mc');
destination = fullfile(ipRepo, 'model_composer_channelizer');
assert(~isempty(component), ...
    ['Model Composer completed but wrote no new component.xml under %s. ' ...
     'The Hub log next to the model says why: %s'], folder, ...
    fullfile(folder, 'model_composer_hdl.log'));
source = component.folder;
if isfolder(destination)
    rmdir(destination, 's');
end
copyfile(source, destination);
fprintf('Installed Model Composer IP at %s\n', destination);
end

function target = setExportTarget(block)
%SETEXPORTTARGET Ask the Hub for an IP Catalog export.
%   The popup strings have changed between releases ("IP Catalog", "IP catalog",
%   "IPCatalog"), so try each and read the value back instead of assuming.
target = '<unknown>';
candidates = {'IP Catalog', 'IP catalog', 'IPCatalog'};
for index = 1:numel(candidates)
    try
        set_param(block, 'ExportType', candidates{index});
        target = candidates{index};
        break;
    catch problem
        fprintf('ExportType "%s" rejected: %s\n', candidates{index}, problem.message);
    end
end
try
    readBack = get_param(block, 'ExportType');
    if ~isempty(readBack)
        target = readBack;
    end
catch problem
    fprintf('could not read ExportType back: %s\n', problem.message);
end
end

function printHubDevice(model)
%PRINTHUBDEVICE Show what the Hub believes the target device is.
hubs = mc_find_hub(model);
parameters = {'ExportType', 'ProjDevice', 'ProjDevicePart', 'part', 'package', ...
    'speed', 'xilinxfamily', 'ClockFrequency'};
for index = 1:numel(hubs)
    fprintf(2, 'Hub %s:\n', hubs{index});
    for one = 1:numel(parameters)
        try
            fprintf(2, '  %-14s = %s\n', parameters{one}, get_param(hubs{index}, parameters{one}));
        catch problem
            fprintf(2, '  %-14s = <%s>\n', parameters{one}, problem.message);
        end
    end
end
if isempty(hubs)
    fprintf(2, 'No Vitis Model Composer Hub block in %s.\n', model);
end
end

function component = waitForComponent(folder, model, baseline, timeoutSeconds)
%WAITFORCOMPONENT Poll for a component.xml this run wrote.
%   Model Composer writes <model>_ip/component.xml.  A copy left by an earlier
%   run must not be mistaken for the new IP: <model>_ip wins, otherwise only a
%   file modified after baseline counts.
component = [];
started = tic;
lastReport = 0;
while true
    candidates = dir(fullfile(folder, '**', 'component.xml'));
    % Model Composer writes <subsystem>_ip/, where <subsystem> is the Hub's
    % SubsystemName (channelizer_dut), not the model name -- so match the suffix.
    preferred = candidates(contains({candidates.folder}, '_ip'));
    if ~isempty(preferred)
        component = preferred(1);
        break;
    end
    fresh = candidates([candidates.datenum] > baseline);
    if ~isempty(fresh)
        component = fresh(1);
        break;
    end
    elapsed = toc(started);
    if elapsed > timeoutSeconds
        fprintf(2, 'no new component.xml after %d s under %s\n', round(elapsed), folder);
        return;
    end
    if elapsed - lastReport > 30
        fprintf('  waiting for component.xml (%d s)\n', round(elapsed));
        lastReport = elapsed;
    end
    pause(5);
end
fprintf('found %s\n', fullfile(component.folder, component.name));
end

function checkSubsystemName(model, hub)
%CHECKSUBSYSTEMNAME The Hub exports a block, and names it; does that block exist?
%   The documented failure mode is silent: xmcGenerate dies inside vmcGenerate.p
%   with "Index exceeds the number of array elements" when the lookup for the
%   subsystem named by SubsystemName comes back empty.  Saying so here turns that
%   into a sentence.
try
    wanted = get_param(hub, 'SubsystemName');
catch problem
    fprintf('  note: this Hub has no SubsystemName: %s\n', problem.message);
    return;
end
if isempty(wanted)
    error('export_model_composer_ip:subsystem', ...
        ['Hub.SubsystemName is empty, so there is nothing to export.  Set it to ' ...
         'the name of the subsystem holding the design (this build uses ' ...
         'channelizer_dut): run make mc-scratch to rebuild the model.']);
end
if getSimulinkBlockHandle([model '/' wanted]) == -1
    error('export_model_composer_ip:subsystem', ...
        ['Hub.SubsystemName is "%s" but %s has no block of that name, so Model ' ...
         'Composer has nothing to export (xmcGenerate reports this as an index ' ...
         'error).  Run make mc-scratch to rebuild the model with the subsystem.'], ...
        wanted, model);
end
fprintf('exported subsystem: %s/%s\n', model, wanted);
end

function makeDirParametersAbsolute(hub, folder)
%MAKEDIRPARAMETERSABSOLUTE Model Composer writes make.sh into ./netlist.
%   The Hub stores its netlist and target directories, and a relative value is
%   resolved against the MATLAB working directory.  AMD's own example failed with
%       ERROR-XMC-1002: Failed to create and open file ./netlist/make.sh
%   because that folder did not exist where it looked.  Both are pinned to the
%   model folder here (absolute) and created.
parameters = {'directory', 'TargetDirectory'};
for index = 1:numel(parameters)
    name = parameters{index};
    try
        value = get_param(hub, name);
    catch problem
        fprintf('  note: this Hub has no %s: %s\n', name, problem.message);
        continue;
    end
    [~, ~, extension] = fileparts(char(value));
    absolute = char(value);
    if isempty(absolute) || ~isAbsolute(absolute)
        absolute = fullfile(folder, 'netlist');
        if strcmp(name, 'TargetDirectory')
            absolute = fullfile(folder, 'code');
        end
    end
    try
        set_param(hub, name, absolute);
    catch problem
        fprintf('  note: could not set %s: %s\n', name, problem.message);
        continue;
    end
    if ~isfolder(absolute)
        mkdir(absolute);
    end
    fprintf('  Hub.%s = %s (created)\n', name, absolute);
end
end

function yes = isAbsolute(path)
%ISABSOLUTE True for a path that starts at the filesystem root.
yes = ~isempty(path) && (path(1) == '/' || (numel(path) > 1 && path(2) == ':'));
end

function groundUnconnectedInputs(hub, model)
%GROUNDUNCONNECTEDINPUTS Give every Hub input a signal.
%   The example's Hub has two data inputs, driven by blocks of AMD's design; the
%   graft deletes those blocks, leaving the ports unconnected.  Whatever the engine
%   walks when it looks for sources then comes back empty -- the same empty array
%   that produces the index error.  Constants cost nothing and remove the
%   possibility.
ports = get_param(hub, 'PortHandles');
for index = 1:numel(ports.Inport)
    line = get_param(ports.Inport(index), 'Line');
    if line ~= -1
        continue;
    end
    path = sprintf('%s/HubInput%d', model, index);
    if getSimulinkBlockHandle(path) == -1
        add_block('built-in/Constant', path, 'Position', ...
            [20, 220 + 40 * index, 60, 240 + 40 * index]);
        try
            set_param(path, 'Value', '0', 'SampleTime', '1', ...
                'OutDataTypeStr', 'double');
        catch problem
            fprintf('  note: could not set %s: %s\n', path, problem.message);
        end
    end
    try
        add_line(model, sprintf('HubInput%d/1', index), ...
            sprintf('%s/%d', hub, index), 'autorouting', 'on');
    catch problem
        fprintf('  note: could not drive Hub input %d: %s\n', index, problem.message);
    end
end
fprintf('Hub inputs: %d, each driven\n', numel(ports.Inport));
end
