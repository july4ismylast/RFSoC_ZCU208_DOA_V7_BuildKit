function mc_bisect()
%MC_BISECT Which single change makes AMD's example stop generating?
%   The example generates; our model does not.  Instead of guessing which of the
%   differences matters, start from the example and apply our changes one at a
%   time, generating after each step.  The first step that fails names the culprit.
%
%   Every step starts from a fresh copy of the example, applies steps 1..k and
%   generates.  Results and the Hub parameters of the failing step are written to
%   docs/progress/model_composer_bisect.md.
%
%   Output: build/ip_repo/ssr_bisect_step<N>/  and the report.
here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(here)));
if isempty(getenv('IP_REPO'))
    setenv('IP_REPO', fullfile(repoRoot, 'build', 'ip_repo'));
end

% Before any model is opened: a Hub whose library link does not resolve has no
% parameters at all, and every write to it is refused with a message about the
% parameter name.  There is nothing to bisect in that state, so stop here rather
% than write a report that blames the design.
if ~mc_require_libraries(true)
    error(['mc_bisect: the Model Composer block libraries are not on this path, ' ...
        'so the Hub block has no parameters to set.  Run `make mc-libs` for the ' ...
        'paths mc_paths can find, and set MC_ROOT if it guesses wrong.']);
end

example = findExample(repoRoot);
if isempty(example)
    error('no example: run make mc-example first');
end
work = fullfile(repoRoot, 'build', 'mc_bisect');
if ~isfolder(work)
    mkdir(work);
end

steps = { ...
    'export target IP Catalog',        @stepNothing; ...
    'retarget device to MC_PART',      @stepRetarget; ...
    'name the exported subsystem',     @stepIpIdentity; ...
    'our sample format 16.14',         @stepFormat; ...
    'our latency 4',                   @stepLatency; ...
    'our design inside the subsystem', @stepReplaceDesign};

originalFolder = pwd;
results = cell(0, 2);
failedAt = 0;
failedLabel = '';

for count = 1:size(steps, 1)
    label = steps{count, 1};
    modelFile = fullfile(work, 'SSRDDC.slx');
    if isfile(modelFile)
        delete(modelFile);
    end
    copyfile(example, modelFile);
    [~, modelName] = fileparts(modelFile);
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    cd(work);
    for created = {fullfile(work, 'netlist'), fullfile(work, 'netlist', 'ip'), ...
            fullfile(work, 'code')}
        if ~isfolder(created{1})
            mkdir(created{1});
        end
    end
    open_system(modelFile);
    mc_resolve_links(modelName);
    hubs = mc_find_hub(modelName);
    hub = hubs{1};
    if hubHasMask(hub) && prepareHub(hub, work)
        status = 'ok';
    else
        status = 'failed';
    end
    applied = 0;
    while strcmp(status, 'ok') && applied < count
        applied = applied + 1;
        status = steps{applied, 2}(hub, modelName);
    end
    fprintf('\n=== step %d: %s ===\n', count, label);
    switch status
        case 'ok'
            save_system(modelName);
            verdict = generate(modelName, work, sprintf('ssr_bisect_step%d', count));
        case 'empty'
            % Nothing was changed, so generating would prove nothing about this
            % step; stop instead of reporting a result that has no cause.
            verdict = 'no-op: the step matched no block';
        otherwise
            verdict = 'set-failed: a Hub parameter could not be written';
    end
    results{end + 1, 1} = label; %#ok<AGROW>
    results{end + 1, 2} = verdict; %#ok<AGROW>
    fprintf('  -> %s\n', verdict);
    close_system(modelName, 0);
    if ~strcmp(verdict, 'generated')
        failedAt = count;
        failedLabel = label;
        break;
    end
end

cd(originalFolder);
writeReport(repoRoot, results, failedAt, hubParametersOf(example));
fprintf('\n');
for index = 1:size(results, 1)
    fprintf('  %-34s %s\n', results{index, 1}, results{index, 2});
end
if failedAt > 0
    fprintf('\nstopped at step %d: %s\n', failedAt, failedLabel);
    fprintf('  %s\n', results{failedAt, 2});
else
    fprintf('\nevery step generated\n');
end
fprintf('MC_BISECT_DONE\n');
end

% ---------------------------------------------------------------------------
function ok = hubHasMask(hub)
%HUBHASMASK A Hub block with no parameters is an unresolved library link.
ok = ~isempty(mc_hub_get(hub, 'ExportType')) || ~isempty(get_param(hub, 'MaskType'));
if ~ok
    fprintf(2, ['  %s has no mask and no parameters: its library link is not ' ...
        'resolved.\n  mc_require_libraries must run before the model is opened, ' ...
        'and mc_resolve_links\n  right after it; both are called here already, so ' ...
        'this means the library is missing\n  from the installation.\n'], hub);
end
end

function ok = prepareHub(hub, work)
%PREPAREHUB Settings every step shares: IP Catalog, writable folders.
%   The example ships with ExportType = "System Generator" and CodeGeneration =
%   off, so step 1 is a real change and not a no-op.  Writes go through
%   mc_hub_set because this Hub is a library link whose parameters do not answer
%   to set_param by name.
fprintf('  hub %s: ExportType=%s, device=%s\n', hub, mc_hub_get(hub, 'ExportType'), ...
    mc_hub_get(hub, 'ProjDevice'));
% Written first, without CodeGeneration: the network of folders is what the
% engine reads, and a folder it cannot write is the failure it reports as
% "Failed to create and open file ./netlist/ip/Makefile".
ok = mc_hub_set(hub, 'ExportType', 'IP Catalog');
ok = mc_hub_set(hub, 'CodeGeneration', 'on') && ok;
ok = mc_hub_set(hub, 'directory', fullfile(work, 'netlist')) && ok;
ok = mc_hub_set(hub, 'TargetDirectory', fullfile(work, 'code')) && ok;
fprintf('  hub now: ExportType=%s, CodeGeneration=%s\n', ...
    mc_hub_get(hub, 'ExportType'), mc_hub_get(hub, 'CodeGeneration'));
end

function status = stepNothing(~, ~)
%STEPNOTHING The example as shipped, with an IP Catalog target (prepareHub).
status = 'ok';
end

function status = stepRetarget(hub, ~)
%STEPRETARGET The device this repository builds for.
part = getenv('MC_PART');
if isempty(part)
    part = 'xczu48dr-fsvg1517-2-e';
end
pieces = strsplit(part, '-');
% The example ships an UltraScale+ Kintex part (xcku11p-ffva1156-1-e, family
% kintexuplus), so this is a real change of family as well as of part.
ok = mc_hub_set(hub, 'ProjDevice', part);
ok = mc_hub_set(hub, 'ProjDevicePart', part) && ok;
ok = mc_hub_set(hub, 'part', pieces{1}) && ok;
ok = mc_hub_set(hub, 'package', pieces{2}) && ok;
ok = mc_hub_set(hub, 'speed', ['-' pieces{3} '-' pieces{4}]) && ok;
ok = mc_hub_set(hub, 'xilinxfamily', 'zynquplus') && ok;
fprintf('  device -> %s\n', part);
status = pick(ok);
end

function status = stepIpIdentity(hub, modelName)
%STEPIPIDENTITY Say explicitly which block is exported, and under which VLNV.
%   There is no SubsystemName parameter on the 2023.2 Hub: the exported block and
%   the IP identity live in one JSON string, IPInfoJsonString, which the example
%   fills in as {"HDLSubsystem":{"SubsystemName":"DDC_DUT",...,"IPVendor":"User
%   Company"}}.  Writing the JSON is the only way to say it; older notes that
%   called SubsystemName a Hub parameter were wrong.
dut = exportedSubsystem(modelName, hub);
parts = strsplit(dut, '/');
name = parts{end};
ok = mc_hub_set(hub, 'IpVendor', 'doa.v7');
ok = mc_hub_set(hub, 'IpLibrary', 'model_composer') && ok;
ok = mc_hub_set(hub, 'IpVersion', '1.0') && ok;
information = struct('HDLSubsystem', struct('SubsystemName', name, 'IPName', name, ...
    'IPLibrary', 'model_composer', 'IPVendor', 'doa.v7', 'IPVersion', '1.0'));
ok = mc_hub_set(hub, 'IPInfoJsonString', jsonencode(information)) && ok;
fprintf('  exported block -> %s\n', dut);
status = pick(ok);
end

function status = stepFormat(~, modelName)
%STEPFORMAT Gateways to sfix16_En14, as our channels use.
[blocks, hint] = findHDLBlocks(modelName, 'Gateway In');
count = 0;
for index = 1:numel(blocks)
    try
        set_param(blocks{index}, 'n_bits', '16', 'bin_pt', '14');
        count = count + 1;
    catch problem
        fprintf('  note: %s: %s\n', blocks{index}, problem.message);
    end
end
fprintf('  %d gateway(s) set to 16.14\n', count);
status = matched(count, hint);
end

function status = stepLatency(~, modelName)
%STEPLATENCY Every delay to four clocks.
[blocks, hint] = findHDLBlocks(modelName, 'Delay');
count = 0;
for index = 1:numel(blocks)
    try
        set_param(blocks{index}, 'latency', '4');
        count = count + 1;
    catch problem
        fprintf('  note: %s: %s\n', blocks{index}, problem.message);
    end
end
fprintf('  %d delay(s) set to latency 4\n', count);
status = matched(count, hint);
end

function status = stepReplaceDesign(hub, modelName)
%STEPREPLACEDESIGN Our four channels inside the exported subsystem.
dut = exportedSubsystem(modelName, hub);
try
    set_param(dut, 'LinkStatus', 'none');
catch problem
    fprintf('  note: link: %s\n', problem.message);
end
try
    Simulink.SubSystem.deleteContents(dut);
catch problem
    fprintf('  note: deleteContents: %s\n', problem.message);
end
if ~isempty(find_system(dut, 'SearchDepth', 1, 'Type', 'Block'))
    delete_block(dut);
    add_block('built-in/Subsystem', dut, 'Position', [320, 60, 660, 340]);
end
for channel = 1:4
    row = 40 + 60 * (channel - 1);
    inPort = sprintf('%s/InPort%d', dut, channel);
    inBlock = sprintf('%s/In%d', dut, channel);
    delay = sprintf('%s/Delay%d', dut, channel);
    outBlock = sprintf('%s/Out%d', dut, channel);
    outPort = sprintf('%s/OutPort%d', dut, channel);
    add_block('built-in/Inport', inPort, 'Position', [10, row + 3, 30, row + 17]);
    add_block('hdlBasic/Gateway In', inBlock, 'Position', [45, row, 95, row + 20]);
    add_block('hdlBasic/Delay', delay, 'Position', [130, row, 160, row + 20]);
    add_block('hdlBasic/Gateway Out', outBlock, 'Position', [195, row, 245, row + 20]);
    add_block('built-in/Outport', outPort, 'Position', [275, row + 3, 295, row + 17]);
    set_param(inBlock, 'n_bits', '16', 'bin_pt', '14', 'period', '1', ...
        'arith_type', 'Signed  (2''s comp)', 'quantization', 'Truncate', ...
        'overflow', 'Wrap');
    set_param(delay, 'latency', '4');
    links = {sprintf('InPort%d/1', channel), sprintf('In%d/1', channel); ...
        sprintf('In%d/1', channel), sprintf('Delay%d/1', channel); ...
        sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel); ...
        sprintf('Out%d/1', channel), sprintf('OutPort%d/1', channel)};
    for index = 1:size(links, 1)
        try
            add_line(dut, links{index, 1}, links{index, 2}, 'autorouting', 'on');
        catch problem
            fprintf('  note: %s\n', problem.message);
        end
    end
end
fprintf('  design replaced with four channels inside %s\n', dut);
status = 'ok';
end

function status = pick(ok)
if ok
    status = 'ok';
else
    status = 'failed';
end
end

function status = matched(count, hint)
%MATCHED A step that changed nothing must not be reported as a result.
if count > 0
    status = 'ok';
    return
end
fprintf(2, '  nothing matched, so this step changed nothing\n');
if ~isempty(hint)
    fprintf(2, '%s\n', hint);
end
status = 'empty';
end

function dut = exportedSubsystem(modelName, hub)
%EXPORTEDSUBSYSTEM The subsystem the Hub names, else the one with the gateways.
%   The name lives in IPInfoJsonString, not in a SubsystemName parameter.  Falling
%   back to "the first subsystem" is how a run ended up exporting AMD's test-bench
%   block "ADC 1.5GSPS" -- whose name even contains a line break -- so the fallback
%   is now a subsystem that actually holds Gateway In blocks.
candidates = {};
wanted = '';
text = mc_hub_get(hub, 'IPInfoJsonString');
if ~isempty(text)
    try
        wanted = jsondecode(text).HDLSubsystem.SubsystemName;
    catch
        wanted = '';
    end
end
if ~isempty(wanted)
    candidates{end + 1} = [modelName '/' wanted];
end
candidates{end + 1} = [modelName '/DDC_DUT'];
subsystems = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'SubSystem');
for index = 1:numel(subsystems)
    gateways = findHDLBlocks(subsystems{index}, 'Gateway In');
    if ~isempty(gateways)
        candidates{end + 1} = subsystems{index}; %#ok<AGROW>
    end
end
for index = 1:numel(candidates)
    if getSimulinkBlockHandle(candidates{index}) ~= -1
        dut = candidates{index};
        fprintf('  exporting %s\n', dut);
        return
    end
end
error('no subsystem to export in %s (looked for %s)', modelName, strjoin(candidates, ', '));
end

function [blocks, hint] = findHDLBlocks(modelName, kind)
%FINDHDLBLOCKS Blocks of one Model Composer kind, by library, not by MaskType.
%   A linked masked block has an empty MaskType on the instance -- the same reason
%   the Hub could not be found by mask -- so a search on 'MaskType','Gateway In'
%   matched nothing and the step silently changed nothing.  SourceBlock, which is
%   the library block's path, is the identity that exists.
blocks = {};
libraries = {'hdlBasic', 'hdlSSR', 'xilinxUtilities'};
for index = 1:numel(libraries)
    blocks = [blocks; search(modelName, 'SourceBlock', ...
        [libraries{index} '/' kind])]; %#ok<AGROW>
    blocks = [blocks; search(modelName, 'ReferenceBlock', ...
        [libraries{index} '/' kind])]; %#ok<AGROW>
end
blocks = [blocks; search(modelName, 'MaskType', kind)];
blocks = unique(blocks, 'stable');
hint = '';
if ~isempty(blocks)
    return
end
% Nothing matched: say what the model does contain, so the next run is decisive.
sources = {};
every = find_system(modelName, 'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
    'Type', 'Block');
for index = 1:numel(every)
    source = '';
    try
        source = get_param(every{index}, 'SourceBlock');
    catch
        source = '';
    end
    if ~isempty(source)
        sources{end + 1} = source; %#ok<AGROW>
    end
end
sources = unique(sources);
if isempty(sources)
    hint = '  the model has no library-linked blocks at all';
    return
end
limit = min(numel(sources), 40);
hint = sprintf('  library blocks present (%d): %s', numel(sources), ...
    strjoin(sources(1:limit), ', '));
end

function hits = search(modelName, parameter, wanted)
hits = {};
try
    hits = find_system(modelName, 'LookUnderMasks', 'all', 'FollowLinks', 'off', ...
        parameter, wanted);
catch problem
    fprintf('  search by %s failed: %s\n', parameter, problem.message);
    hits = {};
end
end

function verdict = generate(modelName, work, label)
%GENERATE One attempt, artifact copied into the IP repository.
verdict = 'failed';
baseline = now;
try
    xmcGenerate(modelName, 'closeProgressWindow', 1);
catch problem
    fprintf(2, '  xmcGenerate failed: %s\n', problem.message);
    return;
end
component = waitForComponent(work, baseline, 900);
if isempty(component)
    return;
end
destination = fullfile(getenv('IP_REPO'), label);
if isfolder(destination)
    rmdir(destination, 's');
end
copyfile(component.folder, destination);
verdict = 'generated';
end

function component = waitForComponent(folder, baseline, timeoutSeconds)
component = [];
started = tic;
while true
    candidates = dir(fullfile(folder, '**', 'component.xml'));
    preferred = candidates(contains({candidates.folder}, '_ip'));
    if ~isempty(preferred)
        component = preferred(1);
        return;
    end
    fresh = candidates([candidates.datenum] > baseline);
    if ~isempty(fresh)
        component = fresh(1);
        return;
    end
    if toc(started) > timeoutSeconds
        return;
    end
    pause(5);
end
end

function example = findExample(repoRoot)
example = '';
fromEnv = getenv('MC_TEMPLATE');
if ~isempty(fromEnv) && isfile(fromEnv)
    example = fromEnv;
    return;
end
candidates = dir(fullfile(repoRoot, 'build', 'mc_examples', '*.slx'));
if ~isempty(candidates)
    example = fullfile(candidates(1).folder, candidates(1).name);
end
end

function rows = hubParametersOf(example)
%HUBPARAMETERSOF The example's Hub settings, for the report.
rows = {};
[~, name] = fileparts(example);
try
    if ~bdIsLoaded(name)
        load_system(example);
    end
    hubs = mc_find_hub(name);
    if isempty(hubs)
        return;
    end
    mask = get_param(hubs{1}, 'MaskObject');
    if isempty(mask)
        close_system(name, 0);
        return
    end
    parameters = mask.Parameters;
    for index = 1:numel(parameters)
        parameter = parameters(index).Name;
        try
            value = char(get_param(hubs{1}, parameter));
        catch problem
            value = sprintf('<%s>', problem.message);
        end
        rows(end + 1, :) = {parameter, value}; %#ok<AGROW>
    end
    close_system(name, 0);
catch problem
    fprintf('  note: cannot read the example Hub: %s\n', problem.message);
end
end

function writeReport(repoRoot, results, failedAt, hubRows)
%WRITEREPORT The bisect table, plus the Hub settings it ran with.
folder = fullfile(repoRoot, 'docs', 'progress');
if ~isfolder(folder)
    mkdir(folder);
end
file = fullfile(folder, 'model_composer_bisect.md');
handle = fopen(file, 'w');
if handle < 0
    fprintf(2, '  note: cannot write %s\n', file);
    return;
end
cleanup = onCleanup(@() fclose(handle)); %#ok<NASGU>

fprintf(handle, '# Bisecting AMD''s example towards our design\n\n');
fprintf(handle, 'Generated by `make mc-bisect`.  Each step starts from a fresh copy of\n');
fprintf(handle, '`build/mc_examples/SSRDDC.slx`, applies steps 1..k and generates.\n\n');
fprintf(handle, '| step | change | result |\n|---|---|---|\n');
for index = 1:size(results, 1)
    fprintf(handle, '| %d | %s | **%s** |\n', index, results{index, 1}, results{index, 2});
end
if failedAt > 0
    fprintf(handle, '\nThe first failing step: **%s**.\n', results{failedAt, 1});
else
    fprintf(handle, '\nEvery step generated.\n');
end
fprintf(handle, '\n## What this means\n\n');
if failedAt == 0
    fprintf(handle, ['Every step generated, including our four channels inside the ' ...
        'exported subsystem.\nSo IP Catalog export works on this install, for the ' ...
        'part in MC_PART, with our VLNV --\nand the block topology was never the ' ...
        'problem.  What differs is the model this builder assembles.\n']);
else
    fprintf(handle, 'The first step that did not generate was **%s**: %s.\n', ...
        results{failedAt, 1}, results{failedAt, 2});
    if failedAt > 1
        fprintf(handle, '\nSteps 1..%d generated, so those changes are not the cause.\n', ...
            failedAt - 1);
    end
    if startsWith(results{failedAt, 2}, 'no-op')
        fprintf(handle, ['The step matched no block at all, which is a fault in the ' ...
            'script, not a verdict on\nthe design: nothing was changed and nothing ' ...
            'was tested.\n']);
    end
end
if ~isempty(hubRows)
    fprintf(handle, '\n## Hub settings of the example\n\n| parameter | value |\n|---|---|\n');
    for index = 1:size(hubRows, 1)
        value = strrep(hubRows{index, 2}, '|', '\\|');
        fprintf(handle, '| %s | `%s` |\n', hubRows{index, 1}, value);
    end
end
fprintf('\nreport: %s\n', file);
end
