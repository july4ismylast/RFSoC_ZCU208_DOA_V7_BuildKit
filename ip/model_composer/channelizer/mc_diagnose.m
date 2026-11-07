function verdict = mc_diagnose(folder)
%MC_DIAGNOSE Decide whether the fault is the toolchain or our model.
%   Guessing has already cost too many rounds, so this measures instead: run the
%   same generation call on AMD's own example, unmodified, in the same session.
%
%     example fails too -> the toolchain/session is at fault, not this model
%     example works     -> the difference is in our model, and the Hub parameters
%                          of both are printed side by side to show it
%
%   verdict is a short string for the log.
arguments
    folder (1, :) char = ''
end
verdict = 'unknown';
example = findExample(folder);
if isempty(example)
    fprintf(2, ['  no AMD example to compare against; run make mc-example so the ' ...
        'next run can tell the toolchain from the model\n']);
    verdict = 'no-example';
    return;
end

probeFolder = fullfile(fileparts(fileparts(fileparts(folder))), 'build', 'mc_diagnose');
if ~isfolder(probeFolder)
    mkdir(probeFolder);
end
[~, exampleName] = fileparts(example);
probeFile = fullfile(probeFolder, 'mc_probe_example.slx');
copyfile(example, probeFile);
[~, probeName] = fileparts(probeFile);

fprintf(2, '\n--- generating AMD''s own example (%s) to compare ---\n', exampleName);
try
    if bdIsLoaded(probeName)
        close_system(probeName, 0);
    end
    load_system(probeFile);
    fprintf(2, '  calling xmcGenerate(%s)\n', probeName);
    xmcGenerate(probeName, 'closeProgressWindow', 1);
    fprintf(2, '  the example generated\n');
    verdict = 'example-works';
catch problem
    fprintf(2, '  the example failed too: %s\n', problem.message);
    mc_hdl_log_tail(probeFolder, 40);
    verdict = 'example-fails';
end
try
    if bdIsLoaded(probeName)
        close_system(probeName, 0);
    end
catch closeProblem
    fprintf(2, '  note: could not close %s: %s\n', probeName, closeProblem.message);
end

fprintf(2, '\n--- verdict ---\n');
switch verdict
    case 'example-fails'
        fprintf(2, ['  AMD''s unmodified example fails the same way, so this is not ' ...
            'a fault in our model: the install, licence or session is the ' ...
            'problem.\n']);
    case 'example-works'
        fprintf(2, ['  AMD''s example generates and ours does not, so the difference ' ...
            'is in our model.  Compare the two Hub parameter dumps above.\n']);
    otherwise
        fprintf(2, '  inconclusive\n');
end
end

function example = findExample(folder)
%FINDEXAMPLE The AMD example used as the reference, if it was downloaded.
example = '';
fromEnv = getenv('MC_TEMPLATE');
if ~isempty(fromEnv) && isfile(fromEnv)
    example = fromEnv;
    return;
end
roots = {};
if ~isempty(folder)
    roots{end + 1} = fileparts(fileparts(fileparts(folder)));
end
roots{end + 1} = pwd;
for index = 1:numel(roots)
    candidates = dir(fullfile(roots{index}, 'build', 'mc_examples', '*.slx'));
    if ~isempty(candidates)
        example = fullfile(candidates(1).folder, candidates(1).name);
        return;
    end
end
end
