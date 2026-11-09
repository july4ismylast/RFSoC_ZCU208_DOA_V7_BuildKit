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

info = mc_paths();
if ~info.xlGenerateButton
    error('mc_batch_export:xlGenerateButton', ...
        ['xlGenerateButton is unavailable after adding the Model Composer ' ...
         'paths, so only the GUI can initialise Model Composer here. Run: ' ...
         'make mc-gui, then in its Command Window run ' ...
         'export_model_composer_ip(''%s''), then make mc-verify.  ' ...
         'make mc-libs prints what mc_paths found.'], modelPath);
end

export_model_composer_ip(modelPath);
fprintf('MC_EXPORT_OK\n');
end
