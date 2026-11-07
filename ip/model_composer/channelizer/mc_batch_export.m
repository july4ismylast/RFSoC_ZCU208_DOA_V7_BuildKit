function mc_batch_export(modelPath)
%MC_BATCH_EXPORT Build the channelizer IP from a model, with no GUI.
%   Runs inside MATLAB R2022b (started by scripts/build_model_composer_ip.sh).
%   Puts the Model Composer and System Generator paths on the MATLAB path, the
%   same ones the Model Composer launcher prints in its environment banner,
%   starts Model Composer only if xlGenerateButton is still missing, then runs
%   the model's System Generator token and installs the generated IP.
%
%   Environment (set by the shell script):
%     MC_ROOT          Model Composer install, e.g. .../Model_Composer/2023.2
%     MC_VIVADO_ROOT   the Vivado 2023.2 that Model Composer uses
%     IP_REPO          where component.xml is installed
arguments
    modelPath (1, :) char
end

if ~isfile(modelPath)
    error('mc_batch_export:model', 'Model not found: %s', modelPath);
end

mcRoot = getenv('MC_ROOT');
vivadoRoot = getenv('MC_VIVADO_ROOT');
assert(isfolder(vivadoRoot), ...
    'MC_VIVADO_ROOT is not a directory: "%s"', vivadoRoot);

paths = { ...
    fullfile(vivadoRoot, 'lib', 'lnx64.o', 'matlab'), ...
    fullfile(vivadoRoot, 'scripts', 'sysgen', 'matlab'), ...
    fullfile(vivadoRoot, 'scripts', 'sysgen', 'matlab', 'plugins', 'compilation')};
if ~isempty(mcRoot)
    paths = [paths, { ...
        fullfile(mcRoot, 'data', 'examples'), ...
        fullfile(mcRoot, 'lib', 'lnx64.o', 'Ubuntu', '22'), ...
        fullfile(mcRoot, 'lib', 'lnx64.o', 'Ubuntu'), ...
        fullfile(mcRoot, 'lib', 'lnx64.o'), ...
        fullfile(mcRoot, 'simulink'), ...
        fullfile(mcRoot, 'simulink', 'aie'), ...
        fullfile(mcRoot, 'simulink', 'hls')}]; %#ok<AGROW>
end
for index = 1:numel(paths)
    if isfolder(paths{index})
        addpath(paths{index});
    else
        fprintf('missing path (skipped): %s\n', paths{index});
    end
end

jar = fullfile(vivadoRoot, 'lib', 'classes', 'sysgen.jar');
if isfile(jar)
    javaaddpath(jar);
else
    fprintf('note: %s not found\n', jar);
end

% Model Composer initialisation is only needed when the plain System Generator
% paths were not enough; xmcStart can try to open the library browser, so do not
% call it needlessly in a batch session.
if exist('xlGenerateButton', 'file') ~= 2 && exist('xmcStart', 'file') == 2
    fprintf('xlGenerateButton is not on the path yet; calling xmcStart\n');
    try
        xmcStart;
    catch problem
        fprintf('xmcStart failed: %s\n', problem.message);
    end
end

if exist('xlGenerateButton', 'file') ~= 2
    error('mc_batch_export:xlGenerateButton', ...
        ['xlGenerateButton is still unavailable, so only the GUI can ' ...
         'initialise Model Composer here. Run: make mc-gui, then in its ' ...
         'Command Window run export_model_composer_ip(''%s''), then ' ...
         'make mc-verify.'], modelPath);
end

export_model_composer_ip(modelPath);
fprintf('MC_EXPORT_OK\n');
end
