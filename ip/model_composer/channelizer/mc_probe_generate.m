function mc_probe_generate()
%MC_PROBE_GENERATE Report everything that could start a build in this session.
%   Run it in the window where generation is supposed to happen:
%       make mc-eval CODE="mc_probe_generate"
%   It prints the roots, the library files, every candidate scripted entry point
%   (yes/no), and any file whose name contains "enerate" in the Model Composer
%   and Vivado System Generator folders.  That list tells us the function to
%   call instead of guessing again.
info = mc_paths();

fprintf('\n=== scripted entry points\n');
[~, available] = mc_generate_function();
for index = 1:numel(available)
    fprintf('  %s\n', available{index});
end

fprintf('\n=== mask parameters of the Hub (this release)\n');
models = find_system('SearchDepth', 1, 'Type', 'BlockDiagram');
for index = 1:numel(models)
    hubs = mc_find_hub(models{index});
    if isempty(hubs)
        continue;
    end
    fprintf('  model %s\n', models{index});
    for one = 1:numel(hubs)
        mask = get_param(hubs{one}, 'MaskObject');
        for parameter = mask.Parameters
            value = get_param(hubs{one}, parameter.Name);
            fprintf('    %-24s = %s\n', parameter.Name, shortValue(value));
        end
    end
end

fprintf('\n=== files with "enerate" in the name\n');
for root = {info.mcRoot, info.vivadoRoot}
    if isempty(root{1}) || ~isfolder(root{1})
        continue;
    end
    listing = dir(fullfile(root{1}, '**', '*enerate*'));
    fprintf('  %s: %d\n', root{1}, numel(listing));
    for index = 1:min(numel(listing), 25)
        fprintf('    %s\n', fullfile(listing(index).folder, listing(index).name));
    end
end
end

function text = shortValue(value)
if ischar(value) && numel(value) > 60
    text = [value(1:60) '...'];
else
    text = value;
end
end
