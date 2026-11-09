function mc_selftest()
%MC_SELFTEST Check the helpers that need no toolbox, before a build starts.
%   Model Composer cannot be exercised from a test bench, but the pieces around
%   it can, and two real runs were wasted by bugs in exactly those pieces:
%   a strjoin on a numeric argument, and a Hub field left empty.  This runs in a
%   second inside mc_gui_build, so such a bug stops the run with a clear message
%   instead of after the model has been rebuilt.
failures = {};

part = mc_part_string('xczu48dr-fsvg1517-2-e');
failures = check(failures, strcmp(part.device, 'xczu48dr'), 'part.device');
failures = check(failures, strcmp(part.package, 'fsvg1517'), 'part.package');
failures = check(failures, strcmp(part.speed, '-2-e'), 'part.speed');
failures = check(failures, strcmp(part.family, 'zynquplus'), 'part.family');

text = mc_argument_text(1);
failures = check(failures, ischar(text) && strcmp(text, '1'), 'mc_argument_text(1)');
text = sprintf('%s(%s)', 'f', strjoin(cellfun(@mc_argument_text, ...
    {'myModel', 'closeProgressWindow', 1}, 'UniformOutput', false), ', '));
failures = check(failures, strcmp(text, 'f(myModel, closeProgressWindow, 1)'), ...
    'argument list formatting');

[name, available] = mc_generate_function();
failures = check(failures, ischar(name) && (isempty(name) || exist(name, 'file') ~= 0), ...
    'mc_generate_function name');
failures = check(failures, iscell(available) && ~isempty(available), ...
    'mc_generate_function list');

if isempty(failures)
    fprintf('MC_SELFTEST_OK\n');
    return;
end
fprintf(2, 'MC_SELFTEST_FAILED\n');
fprintf(2, '  %s\n', failures{:});
error('mc_selftest:failed', '%d helper check(s) failed', numel(failures));
end

function failures = check(failures, condition, what)
if ~condition
    failures{end + 1} = sprintf('%s failed', what);
end
end
