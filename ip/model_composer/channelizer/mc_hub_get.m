function value = mc_hub_get(block, name)
%MC_HUB_GET Read one Hub parameter, or '' when this release does not have it.
%   Reads go through the same three doors as writes (mc_hub_set): plain
%   get_param, the mask object, then the MaskNames/MaskValues vector.  A Hub saved
%   by another release, or a copy of it, does not answer all three the same way.
arguments
    block (1, :) char
    name (1, :) char
end

value = '';
try
    value = char(get_param(block, name));
    return
catch
    value = '';
end
mask = [];
try
    mask = get_param(block, 'MaskObject');
catch
    mask = [];
end
if ~isempty(mask)
    try
        parameter = mask.getParameter(name);
        value = char(parameter.Value);
        return
    catch
        value = '';
    end
end
try
    names = get_param(block, 'MaskNames');
    values = get_param(block, 'MaskValues');
    if ischar(names)
        names = {names};
    end
    if ischar(values)
        values = {values};
    end
    index = find(strcmp(names, name), 1);
    if ~isempty(index)
        value = char(values{index});
        return
    end
catch
    value = '';
end
end
