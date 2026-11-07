function mc_api_listing()
%MC_API_LISTING List the Model Composer automation entry points that exist.
%   xmcGenerate is protected, and its sibling API (used to save or load Hub
%   settings as JSON, which `help xmcGenerate` references) cannot be guessed:
%   printing the file names under the install shows what is actually there.
root = getenv('MC_ROOT');
if isempty(root)
    fprintf(2, '  MC_ROOT is unset, cannot list the API\n');
    return;
end
folders = {fullfile(root, 'simulink'), fullfile(root, 'bin'), ...
    fullfile(root, 'lib'), fullfile(root, 'mlib')};
for index = 1:numel(folders)
    folder = folders{index};
    if ~isfolder(folder)
        continue;
    end
    entries = dir(fullfile(folder, 'x*.p'));
    names = {entries.name};
    interesting = names(startsWith(names, 'xmc') | startsWith(names, 'xl'));
    if isempty(interesting)
        continue;
    end
    fprintf('  %s:\n', folder);
    for one = 1:numel(interesting)
        fprintf('    %s\n', interesting{one});
    end
end
end
