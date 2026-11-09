function mc_example_ip()
%MC_EXAMPLE_IP Build AMD's own example to IP, and write down everything about it.
%   Not our design -- the point is evidence:
%
%     * does Model Composer produce an IP Catalog component at all in this
%       install, with our ExportType setting, for our part?
%     * what does a model that DOES generate look like, in full: every Hub
%       parameter, every block, the model callbacks and workspace?
%
%   The second part is written to docs/progress/model_composer_example_report.md,
%   so it is committed and readable instead of being described in a message.
%
%   Output: build/ip_repo/ssr_example_ddc/  (component.xml plus its files)
here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(here)));
if isempty(getenv('IP_REPO'))
    setenv('IP_REPO', fullfile(repoRoot, 'build', 'ip_repo'));
end

% Before any model is opened: the Hub is a link into vmcUtilities, and with that
% library off the path the block has no parameters at all.
mc_require_libraries(true);

example = findExample(repoRoot);
if isempty(example)
    error(['no AMD example found. Run: make mc-example   (downloads ' ...
        'build/mc_examples/SSRDDC.slx)']);
end

work = fullfile(repoRoot, 'build', 'mc_example_ip');
if ~isfolder(work)
    mkdir(work);
end
modelFile = fullfile(work, 'SSRDDC.slx');
copyfile(example, modelFile);
[~, modelName] = fileparts(modelFile);
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end

originalFolder = pwd;
cd(work);
restoreFolder = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
for created = {fullfile(work, 'netlist'), fullfile(work, 'netlist', 'ip'), ...
        fullfile(work, 'code')}
    if ~isfolder(created{1})
        mkdir(created{1});
    end
end

open_system(modelFile);
mc_resolve_links(modelName);
hubs = mc_find_hub(modelName);
if isempty(hubs)
    error('no Hub block in the example');
end
hub = hubs{1};

setHubPaths(hub, work);
fprintf('export target before: %s\n', get_param(hub, 'ExportType'));
set_param(hub, 'ExportType', 'IP Catalog', 'CodeGeneration', 'on');
fprintf('export target after:  %s\n', get_param(hub, 'ExportType'));

writeReport(repoRoot, modelName, hub);

fprintf('\n--- generating AMD''s example with IP Catalog ---\n');
first = tryGenerate(modelName, work, 'ssr_example_ddc');

part = getenv('MC_PART');
if isempty(part)
    part = 'xczu48dr-fsvg1517-2-e';
end
pieces = strsplit(part, '-');
fprintf('\n--- retargeting the example to %s and generating again ---\n', part);
try
    set_param(hub, 'ProjDevice', part, 'ProjDevicePart', part, ...
        'part', pieces{1}, 'package', pieces{2}, 'speed', ['-' pieces{3} '-' pieces{4}], ...
        'xilinxfamily', 'zynquplus');
catch problem
    fprintf(2, '  note: could not retarget: %s\n', problem.message);
end
second = tryGenerate(modelName, work, 'ssr_example_ddc_zcu208');

fprintf('\n--- summary ---\n');
fprintf('  example with its own device: %s\n', first);
fprintf('  example retargeted to %s: %s\n', part, second);
if strcmp(second, 'generated')
    fprintf(['  Model Composer CAN produce an IP Catalog component for this part;\n' ...
        '  our model''s failure is therefore structural, not a setting.\n']);
else
    fprintf(['  IP Catalog export did not finish for this part; the report in\n' ...
        '  docs/progress/model_composer_example_report.md has the settings.\n']);
end
fprintf('MC_EXAMPLE_IP_DONE\n');
end

% ---------------------------------------------------------------------------
function example = findExample(repoRoot)
example = '';
fromEnv = getenv('MC_TEMPLATE');
if ~isempty(fromEnv) && isfile(fromEnv)
    example = fromEnv;
    return;
end
candidates = dir(fullfile(repoRoot, 'build', 'mc_examples', '*.slx'));
if ~isempty(candidates)
    example = fullfile(candidates(1).folder, candidates(1).name);
end
end

function setHubPaths(hub, work)
%SETHUBPATHS Absolute netlist/target folders, as every other builder here does.
set_param(hub, 'directory', fullfile(work, 'netlist'));
set_param(hub, 'TargetDirectory', fullfile(work, 'code'));
fprintf('Hub.directory = %s\n', get_param(hub, 'directory'));
fprintf('Hub.TargetDirectory = %s\n', get_param(hub, 'TargetDirectory'));
end

function verdict = tryGenerate(modelName, work, label)
%TRYGENERATE One generation attempt, its artifact copied into the IP repo.
verdict = 'failed';
baseline = now;
try
    xmcGenerate(modelName, 'closeProgressWindow', 1);
    fprintf('  xmcGenerate returned\n');
catch problem
    fprintf(2, '  xmcGenerate failed: %s\n', problem.message);
    mc_report_error(problem, 'example generation');
    return;
end
component = waitForComponent(work, baseline, 600);
if isempty(component)
    fprintf(2, '  no component.xml appeared under %s\n', work);
    return;
end
destination = fullfile(getenv('IP_REPO'), label);
if isfolder(destination)
    rmdir(destination, 's');
end
copyfile(component.folder, destination);
fprintf('  installed IP at %s\n', destination);
verdict = 'generated';
end

function component = waitForComponent(folder, baseline, timeoutSeconds)
component = [];
started = tic;
while true
    candidates = dir(fullfile(folder, '**', 'component.xml'));
    preferred = candidates(contains({candidates.folder}, '_ip'));
    if ~isempty(preferred)
        component = preferred(1);
        break;
    end
    fresh = candidates([candidates.datenum] > baseline);
    if ~isempty(fresh)
        component = fresh(1);
        break;
    end
    if toc(started) > timeoutSeconds
        return;
    end
    pause(5);
end
fprintf('  found %s\n', fullfile(component.folder, component.name));
end

% ---------------------------------------------------------------------------
function writeReport(repoRoot, modelName, hub)
%WRITEREPORT Everything about a model that does generate, for the record.
folder = fullfile(repoRoot, 'docs', 'progress');
if ~isfolder(folder)
    mkdir(folder);
end
file = fullfile(folder, 'model_composer_example_report.md');
handle = fopen(file, 'w');
if handle < 0
    fprintf(2, '  note: cannot write %s\n', file);
    return;
end
cleanup = onCleanup(@() fclose(handle)); %#ok<NASGU>

fprintf(handle, '# AMD example, as Model Composer sees it\n\n');
fprintf(handle, 'Generated by `make mc-example-ip` on this machine, from\n');
fprintf(handle, '`build/mc_examples/SSRDDC.slx`. Values are read at run time, not written by hand.\n\n');

fprintf(handle, '## Model callbacks\n\n| callback | value |\n|---|---|\n');
for name = {'PreLoadFcn', 'PostLoadFcn', 'InitFcn', 'StartFcn', 'StopFcn', 'CloseFcn'}
    value = readParam(modelName, name{1});
    fprintf(handle, '| %s | `%s` |\n', name{1}, oneline(value));
end
fprintf(handle, '\n## Model configuration\n\n| parameter | value |\n|---|---|\n');
for name = {'Solver', 'FixedStep', 'StopTime', 'SampleTimeConstraint', ...
        'EnableMultiTasking', 'SimulationMode', 'StartTime'}
    fprintf(handle, '| %s | `%s` |\n', name{1}, oneline(readParam(modelName, name{1})));
end

fprintf(handle, '\n## Hub parameters\n\n| parameter | value |\n|---|---|\n');
try
    parameters = get_param(hub, 'MaskObject').Parameters;
    for index = 1:numel(parameters)
        name = parameters(index).Name;
        fprintf(handle, '| %s | `%s` |\n', name, oneline(readParam(hub, name)));
    end
catch problem
    fprintf(handle, '\n(cannot list the Hub mask: %s)\n', problem.message);
end

fprintf(handle, '\n## Blocks\n\n| path | type | mask type | source block | sample time |\n');
fprintf(handle, '|---|---|---|---|---|\n');
blocks = find_system(modelName, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
    'Type', 'Block');
for index = 1:numel(blocks)
    path = blocks{index};
    fprintf(handle, '| %s | %s | %s | %s | %s |\n', path, ...
        oneline(readParam(path, 'BlockType')), ...
        oneline(readParam(path, 'MaskType')), ...
        oneline(readParam(path, 'SourceBlock')), ...
        oneline(readParam(path, 'SampleTime')));
end

fprintf(handle, '\n## Model workspace variables\n\n');
try
    workspace = get_param(modelName, 'ModelWorkspace');
    names = workspace.whos;
    if isempty(names)
        fprintf(handle, '(none)\n');
    else
        for index = 1:numel(names)
            fprintf(handle, '- `%s` (%s)\n', names(index).name, names(index).class);
        end
    end
catch problem
    fprintf(handle, '(cannot read the workspace: %s)\n', problem.message);
end

fprintf(handle, '\n## Line count\n\n%d lines in `%s`.\n', ...
    numel(find_system(modelName, 'FindAll', 'on', 'Type', 'line')), modelName);
fprintf('\nreport written: %s\n', file);
end

function value = readParam(block, parameter)
%READPARAM Read one parameter, returning "" when it does not exist.
try
    raw = get_param(block, parameter);
    if ischar(raw)
        value = raw;
    elseif isstring(raw)
        value = char(raw);
    elseif isempty(raw)
        value = '';
    else
        value = mat2str(raw);
    end
catch problem
    value = sprintf('<%s>', problem.message);
end
end

function text = oneline(value)
%ONELINE Markdown-safe single line.
if isempty(value)
    text = '';
    return;
end
text = strrep(char(value), sprintf('\n'), ' ');
text = strrep(text, '|', '\\|');
if numel(text) > 120
    text = [text(1:120) '...'];
end
end
