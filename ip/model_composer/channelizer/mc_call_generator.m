function mc_call_generator(name, model)
%MC_CALL_GENERATOR Invoke the generate entry point with the arguments it takes.
%   The 2023.2 API takes the block diagram name -- the Hub's block path is not a
%   block diagram name, and passing it made xlGenerateButton fail with
%   "No block diagram name specified" inside xlFindSgFig.  Shapes are tried in
%   order, each failure is printed, and the first that returns wins.
arguments
    name (1, :) char
    model (1, :) char
end
handle = str2func(name);
count = NaN;
try
    count = nargin(handle);
catch problem
    fprintf('  nargin(%s) unknown: %s\n', name, problem.message);
end

shapes = {};
if isnan(count) || count ~= 0
    shapes{end + 1} = {model};
    shapes{end + 1} = {model, 'ExportType', 'IP Catalog'};
end
if isnan(count) || count == 0
    shapes{end + 1} = {};
end

failures = {};
for index = 1:numel(shapes)
    arguments = shapes{index};
    fprintf('calling %s(%s)\n', name, strjoin(arguments, ', '));
    try
        feval(handle, arguments{:});
        fprintf('%s returned\n', name);
        return;
    catch problem
        fprintf(2, '  %s failed: %s\n', name, problem.message);
        failures{end + 1} = sprintf('%s(%s): %s', name, ...
            strjoin(arguments, ', '), problem.message); %#ok<AGROW>
    end
end
error('mc_call_generator:failed', ...
    'every argument shape failed for %s:\n  %s', name, strjoin(failures, '\n  '));
end
