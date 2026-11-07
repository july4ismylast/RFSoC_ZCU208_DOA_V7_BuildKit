function mc_gui_build(destination)
%MC_GUI_BUILD Build the model and export its IP inside a Model Composer GUI.
%   The one-line fallback when a batch session cannot see the Model Composer
%   libraries: open the GUI (make mc-gui), then in its Command Window type
%       mc_gui_build
%   which creates channelizer.slx (if it does not exist), exports the IP Catalog
%   IP, and installs component.xml in $IP_REPO.
%
%   Everything here is the same code the batch path runs -- make_channelizer_model
%   and export_model_composer_ip -- so the two routes cannot drift apart.
arguments
    destination (1, :) char = ''
end

here = fileparts(mfilename('fullpath'));
addpath(here);
if isempty(destination)
    destination = fullfile(here, 'channelizer.slx');
end

if ~isfile(destination)
    fprintf('creating the model: %s\n', destination);
    make_channelizer_model(destination);
else
    fprintf('using the existing model: %s\n', destination);
end

export_model_composer_ip(destination);
fprintf('\nMC_GUI_BUILD_DONE %s\n', fullfile(getenv('IP_REPO'), 'model_composer_channelizer'));
end
