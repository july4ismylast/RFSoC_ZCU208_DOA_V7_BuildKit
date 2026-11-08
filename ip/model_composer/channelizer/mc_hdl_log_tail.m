function mc_hdl_log_tail(folder, count)
%MC_HDL_LOG_TAIL Print the end of Model Composer's own log.
%   The engine writes its log where it works, and it says why a generation
%   stopped.  Every round printed only the MATLAB exception and never read this
%   file -- that is the first thing to read, not the last.
%
%   The location is not fixed: a real run had it at <folder>/netlist/
%   model_composer.log, while an earlier version of this function looked only for
%   model_composer_hdl.log in <folder> and reported "no log".  Known names in known
%   folders are tried first, then the newest *.log anywhere below <folder>.
arguments
    folder (1, :) char
    count (1, 1) double = 60
end

places = {folder, fullfile(folder, 'netlist'), fullfile(folder, 'code')};
names = {'model_composer_hdl.log', 'model_composer.log', 'sysgen.log', 'hdl.log'};
for place = 1:numel(places)
    for index = 1:numel(names)
        file = fullfile(places{place}, names{index});
        if isfile(file)
            showLog(file, count);
            return
        end
    end
end
found = dir(fullfile(folder, '**', '*.log'));
if ~isempty(found)
    [~, newest] = max([found.datenum]);
    showLog(fullfile(found(newest).folder, found(newest).name), count);
    return
end
fprintf(2, '\n  no Model Composer log in %s (nothing was written there)\n', folder);
end

function showLog(file, count)
fprintf(2, '\n--- %s (last %d lines) ---\n', file, count);
try
    text = fileread(file);
catch problem
    fprintf(2, '  cannot read it: %s\n', problem.message);
    return
end
lines = strsplit(text, sprintf('\n'));
lines = lines(~cellfun(@isempty, lines));
first = max(1, numel(lines) - count + 1);
for one = first:numel(lines)
    fprintf(2, '  | %s\n', lines{one});
end
end
