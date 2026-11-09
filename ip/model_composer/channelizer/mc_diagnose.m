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
    % open_system runs the model's PreLoadFcn; load_system does not, and the
    % example's StopFcn (stop_time = toc(start_time)) needs it.
    open_system(probeFile);
    % Its Hub also points at ./netlist, which is why the first attempt died with
    % ERROR-XMC-1002; pin both directories to the probe folder for a fair test.
    hubs = mc_find_hub(probeName);
    if ~isempty(hubs)
        for parameter = {'directory', 'TargetDirectory'}
            name = parameter{1};
            folderFor = probeFolder;
            if strcmp(name, 'TargetDirectory')
                folderFor = fullfile(probeFolder, 'code');
            else
                folderFor = fullfile(probeFolder, 'netlist');
            end
            if ~isfolder(folderFor)
                mkdir(folderFor);
            end
            try
                set_param(hubs{1}, name, folderFor);
                fprintf(2, '  Hub.%s = %s\n', name, folderFor);
            catch problem
                fprintf(2, '  note: cannot set %s on the example Hub: %s\n', ...
                    name, problem.message);
            end
        end
    end
    % Model Composer resolves ./netlist against the working directory, so run
    % from the probe folder and create the folders it writes into.  Without this
    % the example dies with ERROR-XMC-1002 before any compare is possible.
    originalFolder = pwd;
    cd(probeFolder);
    folderCleanup = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
    for created = {fullfile(probeFolder, 'netlist'), ...
            fullfile(probeFolder, 'netlist', 'ip'), fullfile(probeFolder, 'code')}
        if ~isfolder(created{1})
            mkdir(created{1});
        end
    end
    fprintf(2, '  working folder: %s\n', pwd);
    fprintf(2, '  calling xmcGenerate(%s)\n', probeName);
    xmcGenerate(probeName, 'closeProgressWindow', 1);
    fprintf(2, '  the example generated\n');
    verdict = 'example-works';
catch problem
    fprintf(2, '  the example failed too: %s\n', problem.message);
    mc_report_error(problem, 'example generation');
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
