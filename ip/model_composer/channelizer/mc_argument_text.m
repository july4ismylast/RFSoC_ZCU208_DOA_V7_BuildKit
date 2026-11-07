function text = mc_argument_text(value)
%MC_ARGUMENT_TEXT Format one function argument for a log line.
%   A real run died in strjoin because one argument of
%   ('closeProgressWindow', 1) is numeric: "First input must be a string array or
%   cell array of character vectors".  Every argument is converted here, and
%   mc_selftest checks it before a build starts.
if ischar(value)
    text = value;
elseif isstring(value)
    text = char(value);
elseif isnumeric(value) || islogical(value)
    text = mat2str(value);
else
    text = sprintf('<%s>', class(value));
end
end
