function mc_call_generator(name, model, hub)
%MC_CALL_GENERATOR Invoke the generate entry point, trying every plausible shape.
%   `xmcGenerate('model')` is the documented call (UG1259) and is what the GUI
%   button ends up doing, but on a real install it died with
%
%       Index exceeds the number of array elements. Index must not exceed 0.
%
%   which names no parameter -- that error comes from inside AMD's code, most
%   likely on a Hub field that is still empty.  So: try the documented shape, then
%   the GUI button (xlGenerateButton with no arguments works on the current
%   figure, which is why open_system + CurrentFigure are set first), then the
%   other entry points.  If everything fails, dump the Hub parameters and the
%   source line that failed, so the next run answers the question instead of
%   producing another "multiple causes".
arguments
    name (1, :) char
    model (1, :) char
    hub (1, :) char = ''
end

open_system(model);
focusFigure(model);

attempts = { ...
    {name, {model}};
    {'xlGenerateButton', {}};
    {'xmcGenerateButton', {model}};
    {'xmcHubGenerate', {model}};
    {'xlGenerate', {model}};
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
        feval(entry, shapeArgs{:});
        fprintf('%s returned\n', entry);
        return;
    catch problem
        fprintf(2, '  %s failed: %s\n', shape, problem.message);
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

function focusFigure(model)
%FOCUSFIGURE Make the model the current figure, which the GUI buttons use.
try
    handle = get_param(model, 'Handle');
    set(0, 'CurrentFigure', handle);
catch problem
    fprintf('  note: could not focus %s: %s\n', model, problem.message);
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
