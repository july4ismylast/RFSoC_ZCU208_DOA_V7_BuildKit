function info = mc_paths(verbose)
%MC_PATHS Make the Model Composer and System Generator paths available.
%   Works in two very different sessions:
%
%     - a Model Composer GUI, where the launcher has already added everything
%       and the environment variables are usually EMPTY (that is not an error);
%     - a `matlab -batch` session, where nothing is set up and the installation
%       roots must be found.
%
%   So the roots come from, in order: the environment (MC_ROOT,
%   MC_VIVADO_ROOT, XILINX_VIVADO), then from what is already on the MATLAB
%   path (a segment containing Model_Composer/<version> or Vivado/<version>),
%   then from `which('xlGenerateButton')`.  An unknown root is a warning, never
%   a failure: in the GUI the paths are already there and nothing needs adding.
%
%   Returns a struct with mcRoot, vivadoRoot, found (name/file/folder),
%   libraries (cellstr) and xlGenerateButton (logical).
arguments
    verbose (1, 1) logical = true
end

info = struct();
info.found = struct('name', {}, 'file', {}, 'folder', {});
info.libraries = {};
info.xlGenerateButton = false;

info.mcRoot = firstNonEmpty({getenv('MC_ROOT'), rootOnPath('Model_Composer')});
info.vivadoRoot = firstNonEmpty({getenv('MC_VIVADO_ROOT'), getenv('XILINX_VIVADO'), ...
    rootOnPath('Vivado'), rootFromFunction('xlGenerateButton')});
if isempty(info.vivadoRoot) && ~isempty(info.mcRoot)
    info.vivadoRoot = siblingVivado(info.mcRoot);
end

if verbose
    fprintf('Model Composer root:  %s\n', printable(info.mcRoot));
    fprintf('Vivado root:          %s\n', printable(info.vivadoRoot));
end

if ~isempty(info.vivadoRoot) && isfolder(info.vivadoRoot)
    info = addVivadoPaths(info, verbose);
end
if ~isempty(info.mcRoot) && isfolder(info.mcRoot)
    info = addModelComposerPaths(info, verbose);
end

for index = 1:numel(info.found)
    info.libraries{end + 1} = info.found(index).name; %#ok<AGROW>
    if verbose
        fprintf('library %-14s %s\n', info.found(index).name, info.found(index).file);
    end
end

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
    if isempty(info.mcRoot) && isempty(info.vivadoRoot)
        fprintf(['note: no Model Composer / Vivado root found from the environment ' ...
                 'or the path; assuming this session is already set up\n']);
    end
end
end

% ---------------------------------------------------------------------------
function text = printable(value)
if isempty(value)
    text = '(not found -- using the paths this session already has)';
else
    text = value;
end
end

function text = ternary(condition, yesText, noText)
if condition
    text = yesText;
else
    text = noText;
end
end

function value = firstNonEmpty(candidates)
value = '';
for index = 1:numel(candidates)
    if ~isempty(candidates{index})
        value = candidates{index};
        return;
    end
end
end

function root = rootOnPath(name)
%ROOTONPATH Find <prefix>/<name>/<version> among the folders already on the path.
root = '';
segments = strsplit(path, pathsep);
for index = 1:numel(segments)
    parts = strsplit(segments{index}, filesep);
    hit = find(strcmp(parts, name), 1);
    if isempty(hit) || numel(parts) <= hit + 1
        continue;
    end
    candidate = strjoin(parts(1:hit + 1), filesep);
    if isfolder(candidate)
        root = candidate;
        return;
    end
end
end

function root = rootFromFunction(functionName)
%ROOTFROMFUNCTION Derive the install root from where a function lives.
%   .../Vivado/2023.2/scripts/sysgen/matlab/xlGenerateButton.p -> .../Vivado/2023.2
root = '';
location = which(functionName);
if isempty(location)
    return;
end
folder = fileparts(location);
for levels = 3:4
    candidate = folder;
    for step = 1:levels
        candidate = fileparts(candidate);
    end
    if isfolder(fullfile(candidate, 'scripts', 'sysgen'))
        root = candidate;
        return;
    end
end
end

function root = siblingVivado(mcRoot)
%SIBLINGVIVADO .../X20232/Model_Composer/2023.2 -> .../X20232/Vivado/2023.2
root = '';
version = regexp(mcRoot, '([^/\\]+)[/\\]?$', 'tokens', 'once');
if isempty(version)
    return;
end
base = fileparts(fileparts(mcRoot));
candidate = fullfile(base, 'Vivado', version{1});
if isfolder(candidate)
    root = candidate;
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
    fprintf('Vivado paths added:   %d\n', numel(added));
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
for name = wantedLibraries()
    if any(strcmp(info.libraries, name{1}))
        continue;
    end
    hit = guessLibrary(info.mcRoot, name{1});
    if isempty(hit)
        continue;
    end
    addpath(hit.folder);
    info.found(end + 1) = struct('name', name{1}, 'file', hit.file, ...
        'folder', hit.folder); %#ok<AGROW>
    info.libraries{end + 1} = name{1}; %#ok<AGROW>
end

missing = setdiff(wantedLibraries(), info.libraries, 'stable');
if isempty(missing)
    return;
end
if verbose
    fprintf('scanning %s for %d libraries (one pass)\n', info.mcRoot, numel(missing));
end
% Model Composer keeps some libraries as .slx and older ones as .mdl.
listing = [dir(fullfile(info.mcRoot, '**', '*.slx')); ...
           dir(fullfile(info.mcRoot, '**', '*.mdl'))];
for index = 1:numel(missing)
    match = [];
    for extension = {'.slx', '.mdl'}
        hit = find(strcmp({listing.name}, [missing{index} extension{1}]), 1);
        if ~isempty(hit)
            match = hit;
            break;
        end
    end
    if isempty(match)
        continue;
    end
    folder = listing(match).folder;
    addpath(folder);
    info.found(end + 1) = struct('name', missing{index}, ...
        'file', fullfile(folder, listing(match).name), 'folder', folder); %#ok<AGROW>
    info.libraries{end + 1} = missing{index}; %#ok<AGROW>
end
writeCache(info);
end

% ---------------------------------------------------------------------------
function wanted = wantedLibraries()
wanted = {'vmcUtilities', 'hdlBasic', 'hdlSSR', 'hdlUtilities'};
end

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

function added = addFolders(candidates)
added = {};
for index = 1:numel(candidates)
    if isfolder(candidates{index})
        addpath(candidates{index});
        added{end + 1} = candidates{index}; %#ok<AGROW>
    end
end
end

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
