function mc_hdl_log_tail(folder, count)
%MC_HDL_LOG_TAIL Print the end of Model Composer's own log.
%   The engine writes model_composer_hdl.log next to the model, and it says why a
%   generation stopped.  Every round so far printed only the MATLAB exception and
%   never read this file -- that is the first thing to read, not the last.
arguments
    folder (1, :) char
    count (1, 1) double = 60
end
names = {'model_composer_hdl.log', 'sysgen.log', 'hdl.log'};
for index = 1:numel(names)
    file = fullfile(folder, names{index});
    if ~isfile(file)
        continue;
    end
    fprintf(2, '\n--- %s (last %d lines) ---\n', file, count);
    try
        text = fileread(file);
    catch problem
        fprintf(2, '  cannot read it: %s\n', problem.message);
        return;
    end
    lines = strsplit(text, sprintf('\n'));
    lines = lines(~cellfun(@isempty, lines));
    first = max(1, numel(lines) - count + 1);
    for one = first:numel(lines)
        fprintf(2, '  | %s\n', lines{one});
    end
    return;
end
fprintf(2, '\n  no Model Composer log in %s (nothing was written there)\n', folder);
end
