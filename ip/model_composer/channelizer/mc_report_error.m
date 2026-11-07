function mc_report_error(err, context)
%MC_REPORT_ERROR Print an exception with all of its causes, not "multiple causes".
%   MATLAB collapses several S-function errors into
%       Error due to multiple causes.
%   whose real text lives in err.cause.  This prints every level so the log
%   names the block and the reason.
arguments
    err
    context (1, :) char = ''
end
if ~isempty(context)
    fprintf(2, '\n%s failed: %s\n', context, err.message);
else
    fprintf(2, '\n%s\n', err.message);
end
printCauses(err, 1);
try
    fprintf(2, '%s\n', getReport(err, 'extended', 'hyperlinks', 'off'));
catch problem
    fprintf(2, '  (no detailed report: %s)\n', problem.message);
end
end

function printCauses(err, depth)
if ~isprop(err, 'cause') || isempty(err.cause)
    return;
end
for index = 1:numel(err.cause)
    inner = err.cause{index};
    fprintf(2, '%s- %s\n', repmat('  ', 1, depth), inner.message);
    if ~isempty(inner.stack)
        fprintf(2, '%s  at %s line %d\n', repmat('  ', 1, depth), ...
            inner.stack(1).name, inner.stack(1).line);
    end
    printCauses(inner, depth + 1);
end
end
