function mc_source_context(err, depth)
%MC_SOURCE_CONTEXT Print the code lines an exception died on.
%   "Index exceeds the number of array elements. Index must not exceed 0" from
%   xmcGenerate names no parameter, so the only way to learn which Hub field is
%   empty is to look at the line that indexed it.  This prints the failing frame
%   plus a window of source around it, straight from the installed tool.
arguments
    err
    depth (1, 1) double = 3
end
frames = err.stack;
if isempty(frames)
    fprintf(2, '  (no stack: the error was not raised inside a .m file)\n');
    return;
end
shown = 0;
for index = 1:numel(frames)
    if shown >= depth
        return;
    end
    frame = frames(index);
    if isempty(frame.file) || ~isfile(frame.file)
        continue;
    end
    shown = shown + 1;
    fprintf(2, '  at %s line %d (%s)\n', frame.name, frame.line, frame.file);
    printWindow(frame.file, frame.line);
end
if shown == 0
    fprintf(2, '  stack frames are built-ins only:\n');
    for index = 1:min(numel(frames), 6)
        fprintf(2, '    %s line %d\n', frames(index).name, frames(index).line);
    end
end
end

function printWindow(file, line)
%PRINTWINDOW Show the lines around a failure, numbered.
first = max(1, line - 12);
last = line + 8;
try
    text = fileread(file);
catch problem
    fprintf(2, '    (cannot read the file: %s)\n', problem.message);
    return;
end
lines = strsplit(text, sprintf('\n'));
for index = first:min(last, numel(lines))
    marker = ' ';
    if index == line
        marker = '>';
    end
    fprintf(2, '    %s%5d %s\n', marker, index, lines{index});
end
end
