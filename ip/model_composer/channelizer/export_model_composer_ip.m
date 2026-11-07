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

generator = findGenerator(model);
assert(~isempty(generator), ...
    ['No Vitis Model Composer Hub / System Generator token in %s. Add one at ' ...
     'the top level: Library Browser > AMD Toolbox > Utilities > Code ' ...
     'Generation > Vitis Model Composer Hub (or run make mc-scratch to build ' ...
     'a model that already has it).'], model);

target = setExportTarget(generator{1});
fprintf('generate block: %s\n', generator{1});
fprintf('export target:  %s\n', target);

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
feval(name, generator{1});

ipRepo = getenv('IP_REPO');
assert(~isempty(ipRepo), 'IP_REPO is not set; run this through make mc');
destination = fullfile(ipRepo, 'model_composer_channelizer');
components = dir(fullfile(folder, '**', 'component.xml'));
assert(~isempty(components), ...
    'Model Composer completed but no component.xml was found under %s', folder);
[~, newest] = max([components.datenum]);
source = components(newest).folder;
if isfolder(destination)
    rmdir(destination, 's');
end
copyfile(source, destination);
fprintf('Installed Model Composer IP at %s\n', destination);
end

function found = findGenerator(model)
%FINDGENERATOR Locate the Hub or the legacy System Generator token.
found = {};
hub = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
    'SourceBlock', 'vmcUtilities/Vitis Model Composer Hub');
if ~isempty(hub)
    found = hub;
    return;
end
hub = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
    'SourceType', 'VMC Hub');
if ~isempty(hub)
    found = hub;
    return;
end
found = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
    'MaskType', 'Xilinx System Generator');
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
hubs = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
    'SourceBlock', 'vmcUtilities/Vitis Model Composer Hub');
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
