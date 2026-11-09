function options = mc_hub_options(hub)
%MC_HUB_OPTIONS Print the allowed strings of every popup Hub parameter.
%   Guessing popup values is what produced "Invalid setting for parameter
%   'arith_type'" earlier, so the options are read from the mask and printed.
%   `options` is a struct: field names are the parameters, values are cellstr.
arguments
    hub (1, :) char
end
options = struct();
try
    parameters = get_param(hub, 'MaskObject').Parameters;
catch problem
    fprintf(2, '  cannot read the mask of %s: %s\n', hub, problem.message);
    return;
end
fprintf('  Hub popup options:\n');
for index = 1:numel(parameters)
    name = parameters(index).Name;
    choices = parameters(index).TypeOptions;
    if isempty(choices)
        continue;
    end
    options.(name) = choices;
    fprintf('    %-22s : %s\n', name, strjoin(choices, ' | '));
end
end
