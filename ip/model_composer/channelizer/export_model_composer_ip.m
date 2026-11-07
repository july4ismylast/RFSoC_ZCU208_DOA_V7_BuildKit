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
set_param(model, 'SimulationCommand', 'update');

generator = findGenerator(model);
assert(~isempty(generator), ...
    ['No Vitis Model Composer Hub / System Generator token in %s. Add one at ' ...
     'the top level: Library Browser > AMD Toolbox > Utilities > Code ' ...
     'Generation > Vitis Model Composer Hub (or run make mc-scratch to build ' ...
     'a model that already has it).'], model);

if exist('xlGenerateButton', 'file') ~= 2
    error('export_model_composer_ip:xlGenerateButton', ...
        ['xlGenerateButton is not on the MATLAB path, so Model Composer was ' ...
         'not initialised in this session. Run this through make mc (which ' ...
         'adds the Model Composer paths), or through make mc-gui.']);
end

target = setExportTarget(generator{1});
fprintf('generate block: %s\n', generator{1});
fprintf('export target:  %s\n', target);

xlGenerateButton(generator{1});

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
