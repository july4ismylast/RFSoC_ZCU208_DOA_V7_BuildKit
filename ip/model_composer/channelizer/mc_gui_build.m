function mc_gui_build(destination, rebuild)
%MC_GUI_BUILD Build the model and export its IP inside a Model Composer GUI.
%   The one-line fallback when a batch session cannot see the Model Composer
%   libraries: open the GUI (make mc-gui), then in its Command Window type
%       mc_gui_build
%
%   The model is GENERATED from make_channelizer_model.m, so a copy left on disk
%   by an earlier, half-configured run is stale by definition: rebuild defaults
%   to true.  Pass false to export an existing model untouched.
%
%   Anything that fails is printed with all of its causes, because MATLAB
%   otherwise reports only "Error due to multiple causes".
arguments
    destination (1, :) char = ''
    rebuild (1, 1) logical = true
end

here = fileparts(mfilename('fullpath'));
addpath(here);
if isempty(getenv('IP_REPO'))
    repoRoot = fileparts(fileparts(fileparts(here)));
    setenv('IP_REPO', fullfile(repoRoot, 'build', 'ip_repo'));
    fprintf('IP_REPO was unset; using %s\n', getenv('IP_REPO'));
end
if isempty(destination)
    destination = fullfile(here, 'channelizer.slx');
end

if isfile(destination) && ~rebuild
    fprintf('using the existing model: %s\n', destination);
else
    if isfile(destination)
        fprintf('rebuilding (the model is generated, not edited): %s\n', destination);
        delete(destination);
    else
        fprintf('creating the model: %s\n', destination);
    end
    try
        make_channelizer_model(destination);
    catch problem
        mc_report_error(problem, 'make_channelizer_model');
        rethrow(problem);
    end
end

try
    export_model_composer_ip(destination);
catch problem
    mc_report_error(problem, 'export_model_composer_ip');
    printLogHint(destination);
    rethrow(problem);
end
fprintf('\nMC_GUI_BUILD_DONE %s\n', fullfile(getenv('IP_REPO'), 'model_composer_channelizer'));
end

function printLogHint(destination)
%PRINTLOGHINT Point at the log Vitis Model Composer writes next to the model.
folder = fileparts(destination);
candidates = {'model_composer_hdl.log', 'sysgen.log'};
for index = 1:numel(candidates)
    logFile = fullfile(folder, candidates{index});
    if isfile(logFile)
        fprintf(2, 'Model Composer log: %s\n', logFile);
        return;
    end
end
fprintf(2, 'No Model Composer log next to the model yet (%s).\n', folder);
end
