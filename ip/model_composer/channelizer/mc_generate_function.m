function [name, available] = mc_generate_function()
%MC_GENERATE_FUNCTION Which scripted "generate" entry point exists here.
%   Model Composer 2023.2 replaced the System Generator token with the Hub, and
%   the old scripted entry point (xlGenerateButton) is not always installed with
%   it.  Rather than assume, check the candidates and report the list.
%
%   name      first candidate that exists, or '' when none does
%   available cellstr of "candidate: yes/no" for the log
candidates = {'xlGenerateButton', 'xmcGenerateButton', 'xmcGenerate', ...
    'xmcHubGenerate', 'xmcGenerateIP', 'xmcGenerateCode', 'xlGenerate'};
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
