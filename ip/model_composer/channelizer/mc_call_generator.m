function mc_call_generator(name, model, hub, folder)
%MC_CALL_GENERATOR Start generation, using the GUI's own code paths as well.
%   `help xmcGenerate` documents xmcGenerate('MyModel'), and that call dies inside
%   the protected vmcGenerate.p with
%
%       Index exceeds the number of array elements. Index must not exceed 0.
%
%   whatever the device, platform, block name or arguments.  The install does
%   ship the GUI's own entry points -- xmcGenerateButtonPressed, xmcGenerateCallback,
%   xmcHubInit, xmcApplyButtonClick -- so those are tried too; a model built from
%   code has never had its Hub dialog opened, and the dialog is where the Hub
%   builds the state the engine reads.
%
%   When everything fails it reads Model Composer's own log (which previous rounds
%   printed the path of but never opened) and then runs AMD's unmodified example
%   through the same call, which separates a toolchain fault from a model fault.
arguments
    name (1, :) char
    model (1, :) char
    hub (1, :) char = ''
    folder (1, :) char = ''
end

open_system(model);
% A model built from code has never had the Hub's dialog opened, and the dialog is
% where the Hub builds the state the engine reads.  Open it (its mask OpenFcn runs
% xmcHubGUI) before the first attempt.
if ~isempty(hub)
    try
        open_system(hub);
        fprintf('opened the Hub dialog: %s\n', hub);
    catch problem
        fprintf('  note: could not open the Hub dialog: %s\n', problem.message);
    end
end

firstFailure = [];
tried = {};
calls = { ...
    {name, {model, 'closeProgressWindow', 1}};
    {name, {model}};
    {'xmcGenerateButtonPressed', {hub}};
    {'xmcGenerateCallback', {hub}};
    {'xmcHubInit', {hub}};
    {name, {model, 'closeProgressWindow', 1}};
    {'xmcApplyButtonClick', {hub}};
    {'xmcGenerateButtonPressed', {getSimulinkBlockHandle(hub)}};
    {name, {model, 'closeProgressWindow', 1}}};

for index = 1:size(calls, 1)
    entry = calls{index}{1};
    shapeArgs = calls{index}{2};
    if isempty(entry) || any(cellfun(@isempty, shapeArgs))
        continue;
    end
    if exist(entry, 'file') == 0 %#ok<EXIST>
        continue;
    end
    shape = sprintf('%s(%s)', entry, strjoin(cellfun(@mc_argument_text, ...
        shapeArgs, 'UniformOutput', false), ', '));
    if any(strcmp(tried, shape))
        continue;
    end
    tried{end + 1} = shape; %#ok<AGROW>
    fprintf('calling %s\n', shape);
    if strcmp(entry, name)
        reassertHub(hub);
    end
    try
        if strcmp(entry, name)
            status = feval(entry, shapeArgs{:});
            printStatus(status);
            fprintf('%s returned\n', entry);
            return;
        end
        % GUI callbacks return nothing: asking for an output made every one of
        % them fail with "Too many output arguments", which looked like the
        % functions being unusable.  Call them the way the GUI calls them.
        feval(entry, shapeArgs{:});
        fprintf('  %s ran\n', entry);
    catch problem
        fprintf(2, '  %s failed: %s\n', shape, problem.message);
        closeWaitBox();
        if isempty(firstFailure)
            firstFailure = problem;
        end
    end
end

fprintf(2, '\nno entry point started generation.  Tried:\n');
fprintf(2, '  %s\n', tried{:});

if ~isempty(folder)
    mc_hdl_log_tail(folder, 60);
end
if ~isempty(hub)
    mc_dump_hub_params(hub);
end
mc_api_listing();
if ~isempty(firstFailure)
    fprintf(2, 'first failure, %s:\n', firstFailure.message);
    mc_source_context(firstFailure);
end
printHelp(name);
if ~isempty(folder)
    mc_diagnose(folder);
end
error('mc_call_generator:failed', ...
    ['generation did not start.  Model Composer''s own log, the Hub parameters ' ...
     'and the toolchain-versus-model verdict are printed above; paste that block.']);
end

% ---------------------------------------------------------------------------
function reassertHub(hub)
%REASSERTHUB Put the settings back that generation needs.
%   A real run's Hub dump reported CodeGeneration = off although the model had
%   been saved with on: opening the dialog and the failed attempts can reset it,
%   and a generation with code generation off does nothing useful.
if isempty(hub)
    return;
end
try
    set_param(hub, 'CodeGeneration', 'on');
    fprintf('  Hub.CodeGeneration = on (re-asserted)\n');
catch problem
    fprintf('  note: could not re-assert CodeGeneration: %s\n', problem.message);
end
try
    fprintf('  Hub.ExportType = %s\n', get_param(hub, 'ExportType'));
catch problem
    fprintf('  note: could not read ExportType: %s\n', problem.message);
end
end

function printStatus(status)
%PRINTSTATUS xmcGenerate returns the result of the run; do not guess its type.
if isempty(status)
    fprintf('  status: <none returned>\n');
elseif ischar(status) || isstring(status)
    fprintf('  status: %s\n', char(status));
elseif islogical(status) || isnumeric(status)
    fprintf('  status: %s\n', mat2str(status));
elseif isstruct(status)
    fprintf('  status: struct with fields %s\n', strjoin(fieldnames(status)', ', '));
else
    fprintf('  status: <%s>\n', class(status));
end
end

function closeWaitBox()
%CLOSEWAITBOX Close a progress window a failed call left behind.
%   A real run printed "ERROR: Close Wait Box due to exception" and the next
%   attempt did nothing useful.
try
    windows = findall(0, 'Type', 'figure', 'Name', 'Wait Box');
    for index = 1:numel(windows)
        delete(windows(index));
    end
catch problem
    fprintf('  note: no wait box to close: %s\n', problem.message);
end
end

function printHelp(name)
%PRINTHELP What the entry point says about its own arguments.
path = which(name);
fprintf(2, '%s is %s\n', name, path);
text = help(name);
if isempty(text)
    fprintf(2, '(no help text)\n');
    return;
end
lines = strsplit(text, sprintf('\n'));
for index = 1:min(numel(lines), 40)
    fprintf(2, '  | %s\n', lines{index});
end
if numel(lines) > 40
    fprintf(2, '  | ... %d more lines\n', numel(lines) - 40);
end
end
