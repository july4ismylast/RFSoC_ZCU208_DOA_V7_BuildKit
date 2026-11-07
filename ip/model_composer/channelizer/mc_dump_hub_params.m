function mc_dump_hub_params(hub)
%MC_DUMP_HUB_PARAMS Every Hub mask parameter, flagging the empty ones.
%   A generator that dies inside an array index usually read an empty parameter.
%   Reading all of them costs nothing and shows which.
arguments
    hub (1, :) char
end
try
    mask = get_param(hub, 'MaskObject');
    parameters = mask.Parameters;
catch problem
    fprintf(2, '  cannot list the mask of %s: %s\n', hub, problem.message);
    return;
end
empty = {};
fprintf('  Hub parameters (%d):\n', numel(parameters));
for index = 1:numel(parameters)
    name = parameters(index).Name;
    try
        value = get_param(hub, name);
    catch problem
        value = sprintf('<%s>', problem.message);
    end
    text = printable(value);
    if isempty(text)
        empty{end + 1} = name; %#ok<AGROW>
        fprintf('    EMPTY  %s\n', name);
    elseif numel(text) > 60
        fprintf('    %-24s = %s...\n', name, text(1:60));
    else
        fprintf('    %-24s = %s\n', name, text);
    end
end
if isempty(empty)
    fprintf('  no empty Hub parameter\n');
else
    fprintf('  empty Hub parameters: %s\n', strjoin(empty, ', '));
end
end

function text = printable(value)
if isempty(value)
    text = '';
elseif ischar(value)
    text = strtrim(value);
elseif isstring(value)
    text = strtrim(char(value));
elseif iscell(value)
    text = strjoin(cellfun(@printable, value, 'UniformOutput', false), ' | ');
elseif isstruct(value)
    text = '<struct>';
elseif isa(value, 'function_handle')
    text = '<handle>';
else
    text = mat2str(value);
end
end
