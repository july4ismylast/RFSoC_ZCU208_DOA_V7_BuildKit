function info = mc_paths(verbose)
%MC_PATHS Put the Model Composer and System Generator libraries on the path.
%   A plain `matlab -batch` session knows nothing about Model Composer: the
%   block libraries (vmcUtilities, hdlBasic, ...) are .slx files inside the Model
%   Composer installation, and only the GUI launcher adds their folders.  This
%   function finds them from MC_ROOT / MC_VIVADO_ROOT (set by scripts/mc_env.sh)
%   and adds the folders, so that
%       add_block('vmcUtilities/Vitis Model Composer Hub', ...)
%   resolves in a batch session.
%
%   A recursive scan of a Model Composer install takes a minute, so the folder
%   list is cached in $MC_LIBS_CACHE (build/mc_libs.txt) and reused while
%   MC_ROOT stays the same.
%
%   Returns a struct with mcRoot, vivadoRoot, found (name/file/folder),
%   libraries (cellstr) and xlGenerateButton (logical).
arguments
    verbose (1, 1) logical = true
end

info = struct();
info.mcRoot = getenv('MC_ROOT');
info.vivadoRoot = getenv('MC_VIVADO_ROOT');
info.found = struct('name', {}, 'file', {}, 'folder', {});
info.libraries = {};
info.xlGenerateButton = false;

if isempty(info.vivadoRoot) || ~isfolder(info.vivadoRoot)
    error('mc_paths:vivado', ...
        ['MC_VIVADO_ROOT is not a directory: "%s". Run this through ' ...
         'make mc / make mc-scratch / make mc-libs.'], info.vivadoRoot);
end

info = addVivadoPaths(info, verbose);
if ~isempty(info.mcRoot) && isfolder(info.mcRoot)
    info = addModelComposerPaths(info, verbose);
end

for index = 1:numel(info.found)
    info.libraries{end + 1} = info.found(index).name; %#ok<AGROW>
    if verbose
        fprintf('library %-14s %s\n', info.found(index).name, info.found(index).file);
    end
end

% Model Composer's own initialiser registers the libraries and defines
% xlGenerateButton.  In batch it may refuse, so never let it abort the run.
if exist('xmcStart', 'file') == 2 && exist('xlGenerateButton', 'file') ~= 2
    try
        xmcStart;
    catch problem
        if verbose
            fprintf('xmcStart did not complete: %s\n', problem.message);
        end
    end
end
info.xlGenerateButton = exist('xlGenerateButton', 'file') == 2;
if verbose
    fprintf('xlGenerateButton: %s\n', ternary(info.xlGenerateButton, 'yes', 'no'));
end
end

% ---------------------------------------------------------------------------
function text = ternary(condition, yesText, noText)
if condition
    text = yesText;
else
    text = noText;
end
end

% ---------------------------------------------------------------------------
function info = addVivadoPaths(info, verbose)
vivadoPaths = { ...
    fullfile(info.vivadoRoot, 'lib', 'lnx64.o', 'matlab'), ...
    fullfile(info.vivadoRoot, 'scripts', 'sysgen', 'matlab'), ...
    fullfile(info.vivadoRoot, 'scripts', 'sysgen', 'matlab', 'plugins', 'compilation')};
added = addFolders(vivadoPaths);
if verbose
    fprintf('Vivado paths added: %d\n', numel(added));
end
jar = fullfile(info.vivadoRoot, 'lib', 'classes', 'sysgen.jar');
if isfile(jar)
    javaaddpath(jar);
end
end

% ---------------------------------------------------------------------------
function info = addModelComposerPaths(info, verbose)
mcPaths = { ...
    fullfile(info.mcRoot, 'simulink'), ...
    fullfile(info.mcRoot, 'simulink', 'lib'), ...
    fullfile(info.mcRoot, 'simulink', 'hdl'), ...
    fullfile(info.mcRoot, 'simulink', 'aie'), ...
    fullfile(info.mcRoot, 'lib', 'lnx64.o', 'Ubuntu', '22'), ...
    fullfile(info.mcRoot, 'lib', 'lnx64.o', 'Ubuntu'), ...
    fullfile(info.mcRoot, 'lib', 'lnx64.o'), ...
    fullfile(info.mcRoot, 'data', 'examples')};
addFolders(mcPaths);

info = readCache(info, verbose);
missing = setdiff(wantedLibraries(), info.libraries, 'stable');
for index = 1:numel(missing)
    hit = guessLibrary(info.mcRoot, missing{index});
    if isempty(hit)
        continue;
    end
    addpath(hit.folder);
    info.found(end + 1) = struct('name', missing{index}, 'file', hit.file, ...
        'folder', hit.folder); %#ok<AGROW>
    info.libraries{end + 1} = missing{index}; %#ok<AGROW>
end

missing = setdiff(wantedLibraries(), info.libraries, 'stable');
if isempty(missing)
    return;
end
if verbose
    fprintf('scanning %s for %d libraries (one pass)\n', info.mcRoot, numel(missing));
end
% Model Composer keeps some libraries as .slx and older ones as .mdl, so look
% for both rather than assuming which this release uses.
listing = [dir(fullfile(info.mcRoot, '**', '*.slx')); ...
           dir(fullfile(info.mcRoot, '**', '*.mdl'))];
for index = 1:numel(missing)
    match = [];
    for extension = {'.slx', '.mdl'}
        fileName = [missing{index} extension{1}];
        hit = find(strcmp({listing.name}, fileName), 1);
        if ~isempty(hit)
            match = hit;
            break;
        end
    end
    if isempty(match)
        continue;
    end
    fileName = listing(match).name;
    folder = listing(match).folder;
    addpath(folder);
    info.found(end + 1) = struct('name', missing{index}, ...
        'file', fullfile(folder, fileName), 'folder', folder); %#ok<AGROW>
    info.libraries{end + 1} = missing{index}; %#ok<AGROW>
end
writeCache(info);
end

% ---------------------------------------------------------------------------
function wanted = wantedLibraries()
wanted = {'vmcUtilities', 'hdlBasic', 'hdlSSR', 'hdlUtilities'};
end

% ---------------------------------------------------------------------------
function hit = guessLibrary(root, name)
%GUESSLIBRARY The few places a Model Composer library actually lives.
hit = struct('file', '', 'folder', '');
fileName = [name '.slx'];
candidates = { ...
    fullfile(root, 'simulink', fileName), ...
    fullfile(root, 'simulink', 'lib', fileName), ...
    fullfile(root, 'simulink', 'hdl', fileName), ...
    fullfile(root, fileName)};
for index = 1:numel(candidates)
    if isfile(candidates{index})
        hit.file = candidates{index};
        hit.folder = fileparts(candidates{index});
        return;
    end
end
end

% ---------------------------------------------------------------------------
function added = addFolders(candidates)
added = {};
for index = 1:numel(candidates)
    if isfolder(candidates{index})
        addpath(candidates{index});
        added{end + 1} = candidates{index}; %#ok<AGROW>
    end
end
end

% ---------------------------------------------------------------------------
function info = readCache(info, verbose)
%READCACHE Reuse the folder list from the previous run.
cacheFile = getenv('MC_LIBS_CACHE');
if isempty(cacheFile) || ~isfile(cacheFile) || isempty(info.mcRoot)
    return;
end
lines = readlines(cacheFile);
folders = {};
for index = 1:numel(lines)
    parts = split(lines(index), sprintf('\t'));
    if numel(parts) < 2 || ~strcmp(parts(1), info.mcRoot) || ~isfolder(parts(2))
        continue;
    end
    folders{end + 1} = parts(2); %#ok<AGROW>
end
if isempty(folders)
    return;
end
for index = 1:numel(folders)
    addpath(folders{index});
    listing = dir(fullfile(folders{index}, '*.slx'));
    for one = 1:numel(listing)
        info.found(end + 1) = struct('name', erase(listing(one).name, '.slx'), ...
            'file', fullfile(folders{index}, listing(one).name), ...
            'folder', folders{index}); %#ok<AGROW>
        info.libraries{end + 1} = info.found(end).name; %#ok<AGROW>
    end
end
if verbose && ~isempty(info.found)
    fprintf('library folders reused from %s (%d)\n', cacheFile, numel(folders));
end
end

% ---------------------------------------------------------------------------
function writeCache(info)
%WRITECACHE Remember the folders so the next run does not rescan.
cacheFile = getenv('MC_LIBS_CACHE');
if isempty(cacheFile) || isempty(info.mcRoot) || isempty(info.found)
    return;
end
folders = unique({info.found.folder});
try
    mkdir(fileparts(cacheFile));
    handle = fopen(cacheFile, 'w');
    if handle < 0
        return;
    end
    for index = 1:numel(folders)
        fprintf(handle, '%s\t%s\n', info.mcRoot, folders{index});
    end
    fclose(handle);
catch problem
    fprintf('note: could not write %s: %s\n', cacheFile, problem.message);
end
end
