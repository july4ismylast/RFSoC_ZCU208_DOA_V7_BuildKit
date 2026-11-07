function [name, available] = mc_generate_function()
%MC_GENERATE_FUNCTION Which scripted "generate" entry point exists here.
%   Model Composer 2023.2 replaced the System Generator token with the Hub.  On
%   a real install this session saw:
%
%       xlGenerateButton: yes      (deprecated; its own warning says
%                                   "use the Vitis Model Composer hub block and
%                                   xmcGenerate API")
%       xmcGenerate:      yes      <- the supported one
%       everything else:  no
%
%   so the supported API is tried FIRST and the deprecated button only as a
%   last resort.
%
%   name      first candidate that exists, or '' when none does
%   available cellstr of "candidate: yes/no" for the log
candidates = {'xmcGenerate', 'xmcGenerateIP', 'xmcGenerateCode', ...
    'xmcHubGenerate', 'xlGenerate', 'xlGenerateButton'};
name = '';
available = {};
for index = 1:numel(candidates)
    exists = exist(candidates{index}, 'file') ~= 0; %#ok<EXIST>
    available{end + 1} = sprintf('%s: %s', candidates{index}, ternary(exists, 'yes', 'no')); %#ok<AGROW>
    if exists && isempty(name)
        name = candidates{index};
    end
end
end

function text = ternary(condition, yesText, noText)
if condition
    text = yesText;
else
    text = noText;
end
end
