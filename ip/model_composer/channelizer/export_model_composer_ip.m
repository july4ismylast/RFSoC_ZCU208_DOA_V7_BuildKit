function export_model_composer_ip(modelPath)
%EXPORT_MODEL_COMPOSER_IP Validate and export a user-owned Model Composer model.
arguments
    modelPath (1,:) char
end
assert(isfile(modelPath),'Model Composer model not found: %s',modelPath);
[folder,model]=fileparts(modelPath);
addpath(folder); load_system(model);
set_param(model,'SimulationCommand','update');
tokens=find_system(model,'LookUnderMasks','all','FollowLinks','on', ...
    'MaskType','Xilinx System Generator');
assert(~isempty(tokens),['No System Generator token was found. Configure the ' ...
    'token for IP Catalog compilation before running this stage.']);
assert(exist('xlGenerateButton','file')==2, ...
    'Model Composer/System Generator command xlGenerateButton is unavailable.');
xlGenerateButton(tokens{1});
ipRepo=getenv('IP_REPO'); destination=fullfile(ipRepo,'model_composer_channelizer');
components=dir(fullfile(folder,'**','component.xml'));
assert(~isempty(components),'Model Composer completed but no component.xml was found.');
[~,newest]=max([components.datenum]); source=components(newest).folder;
if isfolder(destination), rmdir(destination,'s'); end
copyfile(source,destination);
fprintf('Installed Model Composer IP at %s\n',destination);
end
