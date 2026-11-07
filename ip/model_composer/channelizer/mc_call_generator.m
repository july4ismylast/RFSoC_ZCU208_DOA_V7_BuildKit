function mc_call_generator(name, model, hub)
%MC_CALL_GENERATOR Start generation, with the arguments xmcGenerate documents.
%   `help xmcGenerate` on the real install says:
%
%       xmcGenerate('MyModel')                     uses the Hub block settings
%       status = xmcGenerate('MyModel', 'MyModel_hubInfo.json')
%       status = xmcGenerate('MyModel', 'closeProgressWindow', 1)
%
%   so the shape is the model name plus optional name-value pairs.  A run without
%   them died inside the protected xmcGenerate.p with
%   "Index exceeds the number of array elements", while the Hub dump showed
%   SubsystemName and IpName EMPTY -- that is what is fixed in configureHub.
%
%   'closeProgressWindow', 1 is used first because a failed call left a wait box
%   open ("Close Wait Box due to exception"), which blocks the next attempt.
arguments
    name (1, :) char
    model (1, :) char
    hub (1, :) char = ''
end

open_system(model);

attempts = { ...
    {name, {model, 'closeProgressWindow', 1}};
    {name, {model}};
    {'xlGenerateButton', {model}}};

firstFailure = [];
tried = {};
for index = 1:size(attempts, 1)
    entry = attempts{index}{1};
    shapeArgs = attempts{index}{2};
    if exist(entry, 'file') == 0 %#ok<EXIST>
        continue;
    end
    shape = sprintf('%s(%s)', entry, strjoin(shapeArgs, ', '));
    if any(strcmp(tried, shape))
        continue;
    end
    tried{end + 1} = shape; %#ok<AGROW>
    fprintf('calling %s\n', shape);
    try
        status = feval(entry, shapeArgs{:});
        fprintf('%s returned\n', entry);
        printStatus(status);
        return;
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
if ~isempty(hub)
    mc_dump_hub_params(hub);
end
if ~isempty(firstFailure)
    fprintf(2, 'first failure, %s:\n', firstFailure.message);
    mc_source_context(firstFailure);
end
printHelp(name);
error('mc_call_generator:failed', ...
    ['generation did not start.  The Hub parameters and the failing source ' ...
     'line are printed above; paste that block and it can be fixed.']);
end

% ---------------------------------------------------------------------------
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
%   A real run printed "ERROR: Close Wait Box due to exception" after the first
%   failure and then blocked the following attempts.
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
