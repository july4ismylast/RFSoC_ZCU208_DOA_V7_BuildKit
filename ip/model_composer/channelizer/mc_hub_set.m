function ok = mc_hub_set(block, name, value)
%MC_HUB_SET Write one Hub parameter, by every mechanism this release allows.
%   A real run failed on the first write with
%       mc_bisect failed: Reference block does not have a parameter named
%       'ExportType'
%   The 2023.2 Hub is a link into the vmcUtilities library, so the parameter is
%   mask data on the instance and does not have to answer to set_param by name.
%   Three documented routes are tried, in order, and the value is read back
%   after each one:
%     1. set_param(block, name, value)              -- the normal route
%     2. the mask object: parameter.Value = value   -- bypasses the name lookup
%     3. the mask vector: set_param(block, 'MaskValues', ...)
%   When all three fail the function prints what the block actually offers, and
%   for a popup the list of legal strings, so the next run answers the question
%   instead of raising another one.
arguments
    block (1, :) char
    name (1, :) char
    value (1, :) char
end

ok = false;
value = strtrim(value);
if trySetParam(block, name, value)
    ok = true;
    fprintf('  %s.%s = %s\n', name, value, 'set_param');
    return
end
if tryMaskObject(block, name, value)
    ok = true;
    fprintf('  %s.%s = %s\n', name, value, 'mask object');
    return
end
if tryMaskValues(block, name, value)
    ok = true;
    fprintf('  %s.%s = %s\n', name, value, 'MaskValues');
    return
end
fprintf(2, '  cannot write %s = %s on %s\n', name, value, block);
reportParameters(block, name);
end

% ---------------------------------------------------------------------------
function ok = trySetParam(block, name, value)
try
    set_param(block, name, value);
    ok = sameValue(mc_hub_get(block, name), value);
catch
    ok = false;
end
end

function ok = tryMaskObject(block, name, value)
ok = false;
mask = maskOf(block);
if isempty(mask)
    return
end
parameter = [];
try
    parameter = mask.getParameter(name);
catch
    parameter = [];
end
if isempty(parameter)
    return
end
try
    parameter.Value = value;
    ok = sameValue(mc_hub_get(block, name), value);
catch
    ok = false;
end
end

function ok = tryMaskValues(block, name, value)
ok = false;
[names, values] = maskVector(block);
if isempty(names)
    return
end
index = find(strcmp(names, name), 1);
if isempty(index)
    return
end
values{index} = value;
try
    set_param(block, 'MaskValues', values);
    ok = sameValue(mc_hub_get(block, name), value);
catch
    ok = false;
end
end

function mask = maskOf(block)
mask = [];
try
    mask = get_param(block, 'MaskObject');
catch
    mask = [];
end
if isempty(mask)
    try
        mask = Simulink.Mask.get(block);
    catch
        mask = [];
    end
end
end

function [names, values] = maskVector(block)
names = {};
values = {};
try
    names = get_param(block, 'MaskNames');
catch
    names = {};
end
try
    values = get_param(block, 'MaskValues');
catch
    values = {};
end
if ischar(names)
    names = {names};
end
if ischar(values)
    values = {values};
end
if numel(names) ~= numel(values)
    names = {};
    values = {};
end
end

function ok = sameValue(actual, wanted)
ok = strcmp(strtrim(actual), strtrim(wanted));
end

function reportParameters(block, name)
%REPORTPARAMETERS Say what the block offers, so the next run is decisive.
[names, ~] = maskVector(block);
fprintf(2, '  %s\n', describe(block));
if ~isempty(names)
    fprintf(2, '  mask parameters (%d): %s\n', numel(names), strjoin(names, ', '));
    if ~any(strcmp(names, name))
        fprintf(2, '  "%s" is not among them\n', name);
    end
else
    fprintf(2, '  no mask parameters are visible on this block\n');
    if isempty(get_param(block, 'MaskType'))
        fprintf(2, ['  that means the library link is not resolved: vmcUtilities ' ...
            'is not on the path,\n  so the block has no parameters to write.  ' ...
            'Call mc_require_libraries before\n  the model is opened.\n']);
    end
end
mask = maskOf(block);
if isempty(mask)
    return
end
try
    parameter = mask.getParameter(name);
catch
    parameter = [];
end
if isempty(parameter)
    return
end
try
    fprintf(2, '  %s is a %s\n', name, parameter.Type);
catch
    fprintf(2, '  %s has an unknown type\n', name);
end
try
    options = parameter.TypeOptions;
    if ~isempty(options)
        fprintf(2, '  legal values: %s\n', strjoin(cellstr(options), ' | '));
    end
catch
    fprintf(2, '  legal values: not readable\n');
end
end

function text = describe(block)
text = sprintf('block %s', block);
for parameter = {'BlockType', 'ReferenceBlock', 'SourceBlock', 'SourceType', 'MaskType'}
    try
        text = sprintf('%s, %s=%s', text, parameter{1}, get_param(block, parameter{1}));
    catch
        text = sprintf('%s, %s=<none>', text, parameter{1});
    end
end
end
