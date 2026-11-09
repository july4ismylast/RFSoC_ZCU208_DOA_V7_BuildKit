function count = mc_resolve_links(modelName, verbose)
%MC_RESOLVE_LINKS Resolve the library links of a model that was opened too early.
%   A link that could not be resolved when a model is opened stays unresolved:
%   the masked block keeps no parameters, and every write to it is refused with
%   "Reference block does not have a parameter named ...".  Putting the library on
%   the path afterwards is not enough -- each link must be told to resolve again.
%
%   This walks the model's blocks that are still unresolved, loads the library
%   each one points into, and asks Simulink to resolve the link.  It is used right
%   after open_system, and it is also the answer when a library is missing from
%   mc_require_libraries' list of names: whatever the model links to, not a
%   hard-coded guess, decides what has to be loaded.
arguments
    modelName (1, :) char
    verbose (1, 1) logical = true
end

count = 0;
unresolved = find_system(modelName, 'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
    'LinkStatus', 'unresolved');
if isempty(unresolved)
    return
end
if verbose
    fprintf('  %d unresolved library link(s) in %s\n', numel(unresolved), modelName);
end
for index = 1:numel(unresolved)
    block = unresolved{index};
    source = '';
    try
        source = get_param(block, 'SourceBlock');
    catch
        source = '';
    end
    library = strtok(source, '/');
    if ~isempty(library)
        try
            load_system(library);
        catch problem
            if verbose
                fprintf('  %s: cannot load %s (%s)\n', block, library, problem.message);
            end
        end
    end
    try
        set_param(block, 'LinkStatus', 'resolve');
        count = count + 1;
        if verbose
            fprintf('  %s: link resolved\n', block);
        end
    catch problem
        if verbose
            fprintf('  %s: still unresolved (%s)\n', block, problem.message);
        end
    end
end
end
