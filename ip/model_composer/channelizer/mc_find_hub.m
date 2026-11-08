function hubs = mc_find_hub(model)
%MC_FIND_HUB Locate the generate block: Hub (2023.x) or System Generator token.
%   A saved, masked library block does not always answer to SourceBlock, so try
%   every identity it can have: SourceBlock, ReferenceBlock, SourceType,
%   MaskType, and the block name.
%
%   Two rules, both learned the hard way:
%     - FollowLinks is 'off'.  With 'on', find_system walks into the linked
%       library and returns vmcUtilities/Vitis Model Composer Hub -- the
%       reference block, which cannot be written to.  A real run died with
%       "Reference block does not have a parameter named 'ExportType'" for
%       exactly that reason.
%     - every hit is checked to live in the model.  A path in another model is
%       never a candidate, whatever it is called.
hubs = {};
searches = { ...
    {'SourceType', 'VMC Hub'}, ...
    {'SourceBlock', 'vmcUtilities/Vitis Model Composer Hub'}, ...
    {'ReferenceBlock', 'vmcUtilities/Vitis Model Composer Hub'}, ...
    {'MaskType', 'Vitis Model Composer Hub'}, ...
    {'MaskType', 'Xilinx System Generator'}, ...
    {'Name', 'Vitis Model Composer Hub'}, ...
    {'Name', 'System Generator'}};
for index = 1:numel(searches)
    criteria = searches{index};
    hits = search(model, criteria{1}, criteria{2});
    if ~isempty(hits)
        hubs = hits;
        return
    end
end
% Last resort: any depth-1 block that points at the Hub library, whatever the
% library spells its own name as in this release.
for path = reshape(depthOne(model), 1, [])
    source = '';
    try
        source = get_param(path{1}, 'SourceBlock');
    catch
        source = '';
    end
    if contains(source, 'Hub') || contains(source, 'System Generator')
        hubs{end + 1} = path{1}; %#ok<AGROW>
    end
end
end

% ---------------------------------------------------------------------------
function hits = search(model, parameter, wanted)
hits = {};
try
    found = find_system(model, 'SearchDepth', 1, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'off', parameter, wanted);
catch problem
    fprintf('  hub search by %s failed: %s\n', parameter, problem.message);
    return
end
for index = 1:numel(found)
    if inModel(found{index}, model)
        hits{end + 1} = found{index}; %#ok<AGROW>
    else
        fprintf('  ignoring %s: it is not in %s\n', found{index}, model);
    end
end
end

function paths = depthOne(model)
paths = {};
try
    paths = find_system(model, 'SearchDepth', 1, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'off', 'Type', 'Block');
catch problem
    fprintf('  listing %s failed: %s\n', model, problem.message);
end
end

function ok = inModel(path, model)
ok = strcmp(path, model) || strncmp(path, [model '/'], numel(model) + 1);
end
