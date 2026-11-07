function hubs = mc_find_hub(model)
%MC_FIND_HUB Locate the generate block: Hub (2023.x) or System Generator token.
%   A saved, masked library block does not always answer to SourceBlock, so try
%   every identity it can have: ReferenceBlock, SourceBlock, SourceType,
%   MaskType, and finally the block name.  A live run failed with "No Vitis
%   Model Composer Hub block in channelizer" while the block was clearly there,
%   because only the SourceBlock spelling was checked.
hubs = {};
searches = { ...
    {'SourceBlock', 'vmcUtilities/Vitis Model Composer Hub'}, ...
    {'ReferenceBlock', 'vmcUtilities/Vitis Model Composer Hub'}, ...
    {'SourceType', 'VMC Hub'}, ...
    {'MaskType', 'Vitis Model Composer Hub'}, ...
    {'MaskType', 'Xilinx System Generator'}, ...
    {'Name', 'Vitis Model Composer Hub'}, ...
    {'Name', 'System Generator'}};
for index = 1:numel(searches)
    criteria = searches{index};
    try
        hits = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
            'SearchDepth', 1, criteria{1}, criteria{2});
    catch problem
        fprintf('  hub search by %s failed: %s\n', criteria{1}, problem.message);
        continue;
    end
    if ~isempty(hits)
        hubs = hits;
        return;
    end
end
end
