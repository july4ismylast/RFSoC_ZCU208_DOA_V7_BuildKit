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
    'our channels: gateway -> delay -> gateway', @stepReplaceDesign; ...
    'our own subsystem instead of AMD''s', @stepOwnSubsystem};

originalFolder = pwd;
results = cell(0, 2);
failedAt = 0;
failedLabel = '';

startAt = firstStep();
for count = 1:size(steps, 1)
    label = steps{count, 1};
    if count < startAt
        % Steps before this one were proven by an earlier run; the model still gets
        % their changes (1..count are applied), only their own generation is skipped.
        verdict = sprintf('skipped (MC_BISECT_FROM=%d)', startAt);
        fprintf('\n=== step %d: %s ===\n  -> %s\n', count, label, verdict);
        results{end + 1, 1} = label; %#ok<AGROW>
        results{end + 1, 2} = verdict; %#ok<AGROW>
        continue
    end
    [cached, why] = cachedArtifact(label, example);
    if isempty(cached)
        fprintf('  step %d: generating (%s)\n', count, why);
    end
    if ~isempty(cached)
        verdict = sprintf('generated earlier (%s)', cached);
        fprintf('\n=== step %d: %s ===\n  -> %s\n', count, label, verdict);
        results{end + 1, 1} = label; %#ok<AGROW>
        results{end + 1, 2} = verdict; %#ok<AGROW>
        continue
    end
    modelFile = fullfile(work, 'SSRDDC.slx');
    clearModelCopy(modelFile);
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
        % A step that throws must not take the whole run down with it: the report is
        % written after this loop, so an uncaught error loses the evidence too.
        try
            status = steps{applied, 2}(hub, modelName);
        catch problem
            fprintf(2, '  step %d threw: %s\n', applied, problem.message);
            status = 'threw';
        end
    end
    fprintf('\n=== step %d: %s ===\n', count, label);
    switch status
        case 'ok'
            save_system(modelName);
            if checkOnly()
                verdict = checkModel(modelName);
            else
                verdict = generate(modelName, work, sprintf('ssr_bisect_step%d', count));
            end
        case 'empty'
            % Nothing was changed, so generating would prove nothing about this
            % step; stop instead of reporting a result that has no cause.  Name the
            % sub-step that failed, not the outer one: a run once reported step 6
            % for a selector that broke at step 4.
            verdict = sprintf('no-op: step %d (%s) matched no block', ...
                applied, steps{applied, 1});
        case 'threw'
            verdict = sprintf('step %d threw, see the console', applied);
        otherwise
            verdict = 'set-failed: a Hub parameter could not be written';
    end
    results{end + 1, 1} = label; %#ok<AGROW>
    results{end + 1, 2} = verdict; %#ok<AGROW>
    fprintf('  -> %s\n', verdict);
    close_system(modelName, 0);
    accepted = strncmp(verdict, 'generated', 9) || strncmp(verdict, 'model ok', 8);
    if ~accepted && failedAt == 0
        failedAt = count;
        failedLabel = label;
    end
    if ~accepted && ~checkOnly()
        break;
    end
end

cd(originalFolder);
try
    writeReport(repoRoot, results, failedAt, hubParametersOf(example));
catch problem
    fprintf(2, '  the report failed: %s\n%s\n', problem.message, ...
        getReport(problem, 'extended', 'hyperlinks', 'off'));
end
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
%STEPREPLACEDESIGN Our four channels inside AMD's exported subsystem.
%   Measured, not assumed: this model defines a design by its Simulink Inport/Outport
%   blocks -- AMD's own DDC_DUT is 3 in, 2 out -- and a Gateway In does accept a line.
%   So each channel is P -> Gateway In -> Delay -> Gateway Out -> Q.
dut = exportedSubsystem(modelName, hub);
try
    originalPorts = get_param(dut, 'PortHandles');
    fprintf('  AMD''s own %s: %d in, %d out (before the replacement)\n', dut, ...
        numel(originalPorts.Inport), numel(originalPorts.Outport));
catch problem
    fprintf('  note: no ports to count: %s\n', problem.message);
end
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
portWrapped = buildChannels(dut);
stripRoot(modelName, hub);
driveRoot(modelName, dut, portWrapped);
status = 'ok';
end

function status = stepOwnSubsystem(hub, modelName)
%STEPOWNSUBSYSTEM Our design in a subsystem of our own, AMD's left untouched.
%   Every earlier attempt edited AMD's DDC_DUT: broke its library link, emptied it, and
%   filled it with our blocks.  This leaves that block alone and gives the Hub a
%   subsystem that was never anything else -- what a person does in the GUI: drop a
%   subsystem, drag gateways in, select it in the Hub.
name = 'CHANNELIZER';
dut = [modelName '/' name];
former = exportedSubsystem(modelName, hub);
if getSimulinkBlockHandle(dut) ~= -1
    delete_block(dut);
end
add_block('built-in/Subsystem', dut, 'Position', [320, 60, 660, 340]);
portWrapped = buildChannels(dut);
if ~strcmp(former, dut) && getSimulinkBlockHandle(former) ~= -1
    try
        delete_block(former);
        fprintf('  AMD''s %s removed\n', former);
    catch problem
        fprintf(2, '  note: cannot remove %s: %s\n', former, problem.message);
    end
end
json = sprintf(['{"HDLSubsystem":{"SubsystemName":"%s","IPName":"%s",' ...
    '"IPLibrary":"model_composer","IPVendor":"doa.v7","IPVersion":"1.0"}}'], name, name);
if mc_hub_set(hub, 'IPInfoJsonString', json)
    fprintf('  Hub now exports %s\n', name);
end
stripRoot(modelName, hub);
driveRoot(modelName, dut, portWrapped);
status = 'ok';
end

function portWrapped = buildChannels(dut)
%BUILDCHANNELS Four P -> gateway in -> delay -> gateway out -> Q channels.
%   The delay is copied from AMD's own model, not added from the library: the compiler
%   said "ERROR-XMC-2002: Unsupported block .../Delay1 for code generation" for our
%   add_block instances and accepts theirs.  A library block carries mask fields that
%   add_block does not reproduce -- XmcBlockStatus, block_type, block_config -- and a
%   copy brings every one of them along.
portWrapped = false;
source = loadPristine();
cleanup = onCleanup(@() closeQuietly(source)); %#ok<NASGU>
delaySource = '';
if ~isempty(source)
    candidates = findHDLBlocks(source, 'Delay');
    if ~isempty(candidates)
        delaySource = candidates{1};
        fprintf('  copying the delay from %s\n', delaySource);
    end
end
for channel = 1:4
    row = 40 + 60 * (channel - 1);
    inBlock = sprintf('%s/In%d', dut, channel);
    delay = sprintf('%s/Delay%d', dut, channel);
    outBlock = sprintf('%s/Out%d', dut, channel);
    add_block('hdlBasic/Gateway In', inBlock, 'Position', [45, row, 95, row + 20]);
    if isempty(delaySource)
        add_block('hdlBasic/Delay', delay, 'Position', [130, row, 160, row + 20]);
        setQuietly(delay, 'XmcBlockStatus', '1');
    else
        try
            add_block(delaySource, delay, 'Position', [130, row, 160, row + 20]);
        catch problem
            fprintf(2, '  cannot copy the delay: %s\n', problem.message);
            add_block('hdlBasic/Delay', delay, 'Position', [130, row, 160, row + 20]);
        end
    end
    add_block('hdlBasic/Gateway Out', outBlock, 'Position', [195, row, 245, row + 20]);
    setIfPossible(inBlock, 'n_bits', '16');
    setIfPossible(inBlock, 'bin_pt', '14');
    % -1 is refused ("must be greater than 0"), 1 is a second against a Hub whose period
    % is 2 ns; Tclk is what AMD's own gateways carry, one sample per clock.
    setIfPossible(inBlock, 'period', 'Tclk');
    setIfPossible(inBlock, 'quantization', 'Truncate');
    setIfPossible(inBlock, 'overflow', 'Wrap');
    setParamIfPresent(inBlock, 'arith_type', ...
        {'Signed  (2''s comp)', 'Signed (2''s comp)', 'Signed'});
    setIfPossible(delay, 'latency', '4');
    if channel == 1 && ~isempty(delaySource)
        compareBlocks(delaySource, delay);
    end
    if channel == 1
        inPorts = get_param(inBlock, 'PortHandles');
        outPorts = get_param(outBlock, 'PortHandles');
        fprintf('  gateway in: %d in, %d out; gateway out: %d in, %d out\n', ...
            numel(inPorts.Inport), numel(inPorts.Outport), ...
            numel(outPorts.Inport), numel(outPorts.Outport));
        portWrapped = numel(inPorts.Inport) > 0 && numel(outPorts.Outport) > 0;
        fprintf('  the design is defined by %s\n', ternaryText(portWrapped, ...
            'Simulink Inport/Outport blocks', 'the gateways themselves'));
    end
    if portWrapped
        add_block('built-in/Inport', sprintf('%s/P%d', dut, channel), ...
            'Position', [10, row + 3, 30, row + 17]);
        add_block('built-in/Outport', sprintf('%s/Q%d', dut, channel), ...
            'Position', [270, row + 3, 290, row + 17]);
        wire(dut, sprintf('P%d/1', channel), sprintf('In%d/1', channel));
    end
    wire(dut, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel));
    wire(dut, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel));
    if portWrapped
        wire(dut, sprintf('Out%d/1', channel), sprintf('Q%d/1', channel));
    end
end
fprintf('  four channels built inside %s\n', dut);
end

function driveRoot(modelName, dut, portWrapped)
%DRIVEROOT Give the design's ports a signal outside, and prove it.
%   Wiring is done by port handles, never by block name or by geometry: with names,
%   add_line reads 'CHANNELIZER/1' as either port 1 of the block, and with 'autorouting'
%   it finds ports by position, which is how a Terminator placed on top of the subsystem
%   produced "The destination port already has a line connection".  Handles cannot be
%   misread.  The result is verified: a dangling port is an error, not a note.
if ~portWrapped
    return
end
name = get_param(dut, 'Name');
ports = get_param(dut, 'PortHandles');
for handle = [ports.Inport, ports.Outport]
    line = get_param(handle, 'Line');
    if line ~= -1
        try
            delete_line(line);
        catch problem
            fprintf(2, '  note: cannot clear a line on %s: %s\n', name, problem.message);
        end
    end
end
rootBlocks = find_system(modelName, 'SearchDepth', 1, 'Type', 'Block');
for index = 1:numel(rootBlocks)
    [~, leaf] = fileparts(rootBlocks{index});
    if beginsWith(leaf, 'Const') || beginsWith(leaf, 'Term')
        try
            delete_block(rootBlocks{index});
        catch problem
            fprintf(2, '  note: cannot delete %s: %s\n', rootBlocks{index}, ...
                problem.message);
        end
    end
end
ports = get_param(dut, 'PortHandles');
for index = 1:numel(ports.Inport)
    source = sprintf('%s/Const%d', modelName, index);
    add_block('built-in/Constant', source, 'Position', ...
        [120, 60 + 60 * (index - 1), 150, 80 + 60 * (index - 1)]);
    setIfPossible(source, 'Value', '0');
    setIfPossible(source, 'SampleTime', 'Tclk');
    sourcePorts = get_param(source, 'PortHandles');
    try
        add_line(modelName, sourcePorts.Outport(1), ports.Inport(index));
    catch problem
        fprintf(2, '  note: cannot drive input %d: %s\n', index, problem.message);
    end
end
for index = 1:numel(ports.Outport)
    terminator = sprintf('%s/Term%d', modelName, index);
    % x = 700: the subsystem spans 320..660, and a sink on top of it is exactly what
    % geometry-based autorouting misreads.
    add_block('built-in/Terminator', terminator, 'Position', ...
        [700, 60 + 60 * (index - 1), 720, 80 + 60 * (index - 1)]);
    terminatorPorts = get_param(terminator, 'PortHandles');
    try
        add_line(modelName, ports.Outport(index), terminatorPorts.Inport(1));
    catch problem
        fprintf(2, '  note: cannot terminate output %d: %s\n', index, problem.message);
    end
end
dangling = unconnectedPorts(dut);
fprintf('  %d inport(s) driven, %d outport(s) terminated: %d unconnected\n', ...
    numel(ports.Inport), numel(ports.Outport), dangling);
if dangling > 0
    error('mc_bisect:wiring', '%d port(s) of %s are still unconnected', dangling, dut);
end
end

function compareBlocks(theirs, ours)
%COMPAREBLOCKS Print the fields that differ, so the fix is evidence and not a guess.
%   'Unsupported block' says the compiler does not recognise the instance; these are the
%   fields that could carry that recognition.
names = {'MaskType', 'XmcBlockStatus', 'block_type', 'block_config', 'latency', ...
    'rst', 'en', 'reg_retiming', 'SourceType', 'SourceBlock'};
fprintf('  %-30s %-22s %s\n', 'field', 'AMD', 'ours');
for index = 1:numel(names)
    theirsValue = readParameter(theirs, names{index});
    oursValue = readParameter(ours, names{index});
    marker = '';
    if ~strcmp(theirsValue, oursValue)
        marker = '   <- differs';
    end
    fprintf('  %-30s %-22s %s%s\n', names{index}, theirsValue, oursValue, marker);
end
end

function value = readParameter(block, name)
value = '<n/a>';
try
    value = char(get_param(block, name));
catch
    return
end
if isempty(value)
    value = '<empty>';
end
end

function setQuietly(block, name, value)
%SETQUIETLY Write a hidden mask field; a miss is not worth a line in the log.
try
    set_param(block, name, value);
catch
    return
end
end

function sourceModel = loadPristine()
%LOADPRISTINE AMD's example under another name, as a source of block instances.
sourceModel = '';
here = fileparts(mfilename('fullpath'));
repoRoot = fileparts(fileparts(fileparts(here)));
example = findExample(repoRoot);
if isempty(example)
    fprintf(2, '  no pristine example to copy a block from\n');
    return
end
target = fullfile(workFolder(), 'SSRDDC_src.slx');
try
    clearModelCopy(target);
    copyfile(example, target);
    [~, name] = fileparts(target);
    if bdIsLoaded(name)
        close_system(name, 0);
    end
    load_system(target);
    sourceModel = name;
catch problem
    fprintf(2, '  cannot load a pristine copy: %s\n', problem.message);
    sourceModel = '';
end
end

function closeQuietly(name)
%CLOSEQUIETLY Close a model if it is open, never throwing from a destructor.
try
    if ~isempty(name) && bdIsLoaded(name)
        close_system(name, 0);
    end
catch problem
    fprintf(2, '  note: cannot close %s: %s\n', name, problem.message);
end
end

function folder = workFolder()
folder = fullfile(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))), ...
    'build', 'mc_bisect');
end

function count = unconnectedPorts(block)
%UNCONNECTEDPORTS How many of a block's ports have no line.
count = 0;
ports = get_param(block, 'PortHandles');
handles = [ports.Inport, ports.Outport];
for index = 1:numel(handles)
    if get_param(handles(index), 'Line') == -1
        count = count + 1;
    end
end
end

function text = ternaryText(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end
function text = describeBlock(block)
%DESCRIBEBLOCK The few parameters that decide rates and widths, for the log.
text = '';
names = {'MaskType', 'period', 'n_bits', 'bin_pt', 'latency', 'SamplePeriod'};
for index = 1:numel(names)
    try
        value = char(get_param(block, names{index}));
    catch
        continue
    end
    if isempty(value)
        continue
    end
    if isempty(text)
        text = sprintf('%s=%s', names{index}, value);
    else
        text = sprintf('%s, %s=%s', text, names{index}, value);
    end
end
end

function removed = stripRoot(modelName, hub)
%STRIPROOT Leave the Hub and the exported design at the root, and nothing else.
%   A Model Composer design needs nothing beside them -- the gateways are the interface,
%   and the stimulus is only there to simulate AMD's datapath.
dut = '';
try
    dut = [modelName '/' jsonSubsystem(hub)];
catch problem
    fprintf(2, '  note: %s\n', problem.message);
end
blocks = find_system(modelName, 'SearchDepth', 1, 'Type', 'Block');
removed = 0;
for index = 1:numel(blocks)
    if strcmp(blocks{index}, hub) || strcmp(blocks{index}, dut)
        continue
    end
    try
        delete_block(blocks{index});
        removed = removed + 1;
    catch problem
        fprintf(2, '  note: cannot delete %s: %s\n', blocks{index}, problem.message);
    end
end
if removed > 0
    fprintf('  %d block(s) removed from the root\n', removed);
end
purgeDanglingLines(modelName);
if ~isempty(dut) && getSimulinkBlockHandle(dut) ~= -1
    % The ornaments inside the design go the same way: emptying a subsystem leaves line
    % fragments behind it as well.
    purgeDanglingLines(dut);
end
end

function purgeDanglingLines(modelName)
%PURGEDANGLINGLINES Delete line fragments whose source or sink block is gone.
%   Deleting the testbench blocks leaves lines whose other end no longer exists: a run
%   printed 'cannot delete a line: Invalid Simulink line handle' twice and later
%   seventeen 'Unconnected line found in SSRDDC' warnings during simulation.  Those
%   warnings come from the simulation the GUI entry point runs before generating, and
%   the run died there with 'Error due to multiple causes'.  A line with no source or no
%   destination port is deleted here.
lines = find_system(modelName, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'Line');
removed = 0;
for index = 1:numel(lines)
    try
        source = get_param(lines(index), 'SrcPortHandle');
        destinations = get_param(lines(index), 'DstPortHandle');
        if source == -1 || any(destinations == -1)
            delete_line(lines(index));
            removed = removed + 1;
        end
    catch
        % The handle went with its parent line; nothing to delete.
        continue
    end
end
if removed > 0
    fprintf('  %d dangling line(s) removed from the root\n', removed);
end
end

function wire(subsystem, source, destination)
try
    add_line(subsystem, source, destination, 'autorouting', 'on');
catch problem
    fprintf(2, '  note: cannot wire %s -> %s: %s\n', source, destination, problem.message);
end
end

function setIfPossible(block, name, value)
%SETIFPOSSIBLE Write a block parameter, and carry on if this release spells it
%   differently.  A missing popup is worth a note, never a dead run.
try
    set_param(block, name, value);
catch problem
    fprintf(2, '  note: %s: %s = %s (%s)\n', block, name, value, problem.message);
end
end

function setParamIfPresent(block, name, candidates)
%SETPARAMIFPRESENT Try each spelling until one is accepted.
for index = 1:numel(candidates)
    try
        set_param(block, name, candidates{index});
        return
    catch problem
        if index == numel(candidates)
            fprintf(2, '  note: %s: %s (%s)\n', block, name, problem.message);
        end
    end
end
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
%FINDHDLBLOCKS Blocks of one Model Composer kind, by library path, not by MaskType.
%   Three failures in a row came from guessing how to enumerate blocks here, so this
%   now uses handles from 'FindAll' and filters on get(h,'Type')=='block', which is
%   what "a block" actually means to Simulink ('Type' is 'block', not 'Block').  When
%   nothing matches it prints what the model contains -- block count, how many carry
%   a library source, the MaskTypes and the LinkStatus values -- because every earlier
%   hint ("the model has no library-linked blocks at all") was an assertion, not a
%   measurement.
blocks = {};
handles = [];
try
    handles = find_system(modelName, 'FindAll', 'on', 'LookUnderMasks', 'all', ...
        'FollowLinks', 'off');
catch problem
    fprintf('  listing %s failed: %s\n', modelName, problem.message);
end
count = 0;
sourced = 0;
sources = {};
maskTypes = {};
statuses = {};
for index = 1:numel(handles)
    if ~strcmp(blockType(handles(index)), 'block')
        continue
    end
    count = count + 1;
    % getfullname, not get_param(handle,'Path'): a block has no 'Path' parameter,
    % which is how a run died with "SubSystem block does not have a parameter named
    % 'Path'" after the handle-based rewrite.
    path = nameOf(handles(index));
    source = parameterOf(handles(index), 'SourceBlock');
    maskType = parameterOf(handles(index), 'MaskType');
    status = parameterOf(handles(index), 'LinkStatus');
    if ~isempty(source)
        sourced = sourced + 1;
        sources{end + 1} = source; %#ok<AGROW>
    end
    if ~isempty(maskType)
        maskTypes{end + 1} = maskType; %#ok<AGROW>
    end
    if ~isempty(status)
        statuses{end + 1} = status; %#ok<AGROW>
    end
    % 'Gateway In Block', 'Delay Block', 'VMC Hub': the 2023.2 blocks are plain masked
    % subsystems, not library links, so the mask IS the identity and it has a suffix.
    % A run measured this: 110 blocks, 0 with a library source, mask 'Gateway In Block'.
    if contains(source, kind) || contains(maskType, kind)
        blocks{end + 1} = path; %#ok<AGROW>
    end
end
blocks = unique(blocks, 'stable');
hint = '';
if ~isempty(blocks)
    return
end
hint = sprintf(['  %d block(s), %d with a library source; masks: %s; links: %s; sources: %s'], ...
    count, sourced, summarise(maskTypes), summarise(statuses), summarise(sources));
end

function text = summarise(values)
%SUMMARISE The distinct values, at most ten, or "none".
if isempty(values)
    text = 'none';
    return
end
distinct = unique(values);
limit = min(numel(distinct), 10);
text = strjoin(distinct(1:limit), ', ');
if numel(distinct) > limit
    text = sprintf('%s (+%d more)', text, numel(distinct) - limit);
end
end

function path = nameOf(handle)
path = '';
try
    path = getfullname(handle);
catch
    path = '';
end
end

function text = blockType(handle)
text = '';
try
    text = get_param(handle, 'Type');
catch
    text = '';
end
end

function value = parameterOf(handle, name)
value = '';
try
    value = get_param(handle, name);
catch
    value = '';
end
end

function startGeneration(modelName)
%STARTGENERATION Ask for the build the way the GUI asks for it, not only by API.
%   Twenty runs have tried xmcGenerate('SSRDDC') and nothing else, and it dies inside
%   vmcGenerate with an index into an empty array whatever the design.  The GUI's own
%   entry points ship in this installation -- xmcGenerateButtonPressed,
%   xmcGenerateCallback, xmcHubInit -- and the Hub's dialog is where the state the engine
%   reads is built.  So each is tried in turn, the first one that starts the engine wins,
%   and the log says which.  A person pressing Generate runs exactly this code.
hubList = mc_find_hub(modelName);
hub = '';
if ~isempty(hubList)
    hub = hubList{1};
end
if ~isempty(hub)
    try
        open_system(hub);
        fprintf('  opened the Hub dialog: %s\n', hub);
    catch problem
        fprintf('  note: could not open the Hub dialog: %s\n', problem.message);
    end
    selectDesign(hub);
end
% The model's StopFcn does toc(start_time) and fails if nothing set it, which shows up
% as a second cause on every generation error and buries the real one.
assignin('base', 'start_time', tic);
% xmcGenerateCallback is not in this list: a run showed it return without doing
% anything, and the script then waited an hour for a file nothing was producing.
attempts = {
    'xmcGenerateButtonPressed', {hub};
    'xmcHubInit', {hub};
    'xmcGenerate', {modelName, 'closeProgressWindow', 1}};
for index = 1:size(attempts, 1)
    entry = attempts{index, 1};
    args = attempts{index, 2};
    if isempty(strtrim(args{1})) || exist(entry, 'file') == 0 %#ok<EXIST>
        continue
    end
    fprintf('  generating via %s\n', entry);
    try
        callWithoutOutput(entry, args);
        fprintf('  %s returned\n', entry);
        return
    catch problem
        fprintf(2, '  %s threw: %s\n', entry, problem.message);
        causes = problem.cause;
        for index = 1:numel(causes)
            fprintf(2, '    cause %d: %s\n', index, causes{index}.message);
        end
        fprintf(2, '%s\n', getReport(problem, 'extended', 'hyperlinks', 'off'));
    end
end
end

function selectDesign(hub)
%SELECTDESIGN Name the design in whichever field the compiler actually reads.
%   ERROR-XMC-2001 said it plainly: "Did not find top level subsystem '' specified in the
%   Model Composer Hub."  The Hub's IPInfoJsonString carries DDC_DUT, so the compiler is
%   reading another field -- one the dialog creates when a subsystem is picked from its
%   dropdown.  Opening the dialog makes that field exist; this prints every Hub parameter
%   whose name looks like a subsystem selector and fills the empty ones in.
name = '';
try
    name = jsonSubsystem(hub);
catch problem
    fprintf('  note: %s\n', problem.message);
end
fprintf('  Hub design according to IPInfoJsonString: %s\n', ternaryText(isempty(name), ...
    '<empty>', name));
try
    mask = get_param(hub, 'MaskObject');
catch problem
    fprintf('  note: no mask object: %s\n', problem.message);
    return
end
if isempty(mask)
    fprintf('  note: the Hub has no mask object to read\n');
    return
end
parameters = mask.Parameters;
fillable = 0;
for index = 1:numel(parameters)
    parameter = parameters(index).Name;
    if isempty(regexpi(parameter, 'subsystem|top|design|hdl', 'once'))
        continue
    end
    value = '';
    try
        value = char(get_param(hub, parameter));
    catch problem
        fprintf('  note: hub.%s unreadable: %s\n', parameter, problem.message);
        continue
    end
    fprintf('  hub.%s = %s\n', parameter, value);
    if isempty(value) && ~isempty(name)
        fillable = fillable + 1;
    end
end
if fillable == 0
    fprintf('  no empty subsystem field among the Hub mask parameters\n');
    return
end
for index = 1:numel(parameters)
    parameter = parameters(index).Name;
    if isempty(regexpi(parameter, 'subsystem|top|design|hdl', 'once'))
        continue
    end
    value = '';
    try
        value = char(get_param(hub, parameter));
    catch
        continue
    end
    if isempty(value) && ~isempty(name) && mc_hub_set(hub, parameter, name)
        fprintf('  hub.%s filled with %s\n', parameter, name);
    end
end
end

function callWithoutOutput(entry, args)
%CALLWITHOUTOUTPUT GUI callbacks are defined with nargout 0; asking for a value throws.
switch numel(args)
    case 1
        feval(entry, args{1});
    case 2
        feval(entry, args{1}, args{2});
    otherwise
        feval(entry, args{1}, args{2}, args{3});
end
end

function yes = checkOnly()
%CHECKONLY MC_BISECT_CHECK=1 stops after the diagram update.
%   A generation is minutes and its error names nothing; a diagram update is seconds
%   and now prints the actual cause.  Fixing a model is a loop, and the loop belongs on
%   the cheap side.
yes = strcmp(getenv('MC_BISECT_CHECK'), '1');
end

function verdict = checkModel(modelName)
%CHECKMODEL Update the diagram, and say what is wrong with it in words.
inspectModel(modelName);
try
    set_param(modelName, 'SimulationCommand', 'update');
    verdict = 'model ok (not generated: MC_BISECT_CHECK=1)';
catch problem
    causes = problem.cause;
    if isempty(causes)
        verdict = sprintf('model invalid: %s', problem.message);
    else
        verdict = sprintf('model invalid: %s', causes{1}.message);
    end
end
end

function inspectModel(modelName)
%INSPECTMODEL What the engine is being handed, in numbers.
%   Two suggestions from outside this project were that the design has no Simulink
%   Inport/Outport and that the Hub's inputs are left disconnected.  Both are checkable
%   in one line each before generating, so they stop being opinions: the ports of the
%   exported subsystem, the ports of the Hub, and a diagram update, which turns a
%   broken line into a diagnostic instead of an empty array deep inside the tool.
hubList = mc_find_hub(modelName);
if isempty(hubList)
    fprintf(2, '  no Hub found, cannot inspect\n');
    return
end
hub = hubList{1};
fprintf('  hub %s\n', hub);
ports = get_param(hub, 'PortHandles');
fprintf('  hub ports: %d in, %d out\n', numel(ports.Inport), numel(ports.Outport));
for name = {'ClockFrequency', 'SamplePeriod', 'clock_wrapper'}
    try
        fprintf('  hub.%s = %s\n', name{1}, char(get_param(hub, name{1})));
    catch
        continue
    end
end
for index = 1:numel(ports.Inport)
    line = get_param(ports.Inport(index), 'Line');
    fprintf('    hub input %d: line handle %d%s\n', index, line, ...
        ternary(line == -1, ' (disconnected)', ''));
end
wanted = '';
try
    wanted = get_param(hub, 'SubsystemName');
catch problem
    fprintf('  note: no SubsystemName parameter: %s\n', problem.message);
end
if isempty(wanted)
    wanted = jsonSubsystem(hub);
end
if isempty(wanted)
    fprintf(2, '  the Hub does not name a subsystem\n');
else
    dut = [modelName '/' wanted];
    if getSimulinkBlockHandle(dut) == -1
        fprintf(2, '  the Hub names %s, which does not exist\n', dut);
    else
        dutPorts = get_param(dut, 'PortHandles');
        fprintf('  %s: %d inport(s), %d outport(s), %d child block(s)\n', dut, ...
            numel(dutPorts.Inport), numel(dutPorts.Outport), ...
            numel(find_system(dut, 'SearchDepth', 1, 'Type', 'Block')));
        ins = findHDLBlocks(dut, 'Gateway In');
        outs = findHDLBlocks(dut, 'Gateway Out');
        fprintf('  gateway blocks inside: %d in, %d out\n', numel(ins), numel(outs));
        fprintf('  unconnected ports on %s: %d\n', wanted, unconnectedPorts(dut));
        for index = 1:numel(dutPorts.Inport)
            fprintf('    in %d: line %d\n', index, get_param(dutPorts.Inport(index), 'Line'));
        end
        for index = 1:numel(dutPorts.Outport)
            fprintf('    out %d: line %d\n', index, ...
                get_param(dutPorts.Outport(index), 'Line'));
        end
    end
end
try
    set_param(modelName, 'SimulationCommand', 'update');
    fprintf('  diagram update: ok\n');
catch problem
    fprintf(2, '  diagram update failed: %s\n', problem.message);
    causes = problem.cause;
    for index = 1:numel(causes)
        fprintf(2, '    cause %d: %s\n', index, causes{index}.message);
    end
end
end

function text = ternary(condition, whenTrue, whenFalse)
if condition
    text = whenTrue;
else
    text = whenFalse;
end
end

function name = jsonSubsystem(hub)
%JSONSUBSYSTEM The subsystem name the Hub carries inside IPInfoJsonString.
name = '';
try
    text = char(get_param(hub, 'IPInfoJsonString'));
catch problem
    fprintf('  note: no IPInfoJsonString: %s\n', problem.message);
    return
end
at = strfind(text, '"SubsystemName":"');
if isempty(at)
    return
end
rest = text(at(1) + numel('"SubsystemName":"'):end);
stop = find(rest == '"', 1);
if ~isempty(stop)
    name = rest(1:stop - 1);
end
end

function verdict = generate(modelName, work, label)
%GENERATE One attempt, artifact copied into the IP repository.
%   A retargeted design is synthesised for the new part, which is minutes of
%   Vivado, not seconds: a real run sat in "generation in progress" past ten
%   minutes while a fixed 15 minute timeout printed nothing at all, so the tool
%   looked dead.  The wait now says what is happening and how long it may take,
%   and when it gives up it prints the engine's own log.
verdict = 'failed';
baseline = now;
inspectModel(modelName);
try
    startGeneration(modelName);
catch problem
    % Cancelling is not the same as failing.  A real run showed "generation in
    % progress" for 47 minutes after Vivado had already written "Exiting Vivado"
    % and packaged the IP: the call never returned, the work was done.  So on any
    % error, look for the component before believing the error.
    % The message alone says nothing about where it broke: three rounds of work went
    % into guessing at "Index exceeds the number of array elements".  The extended
    % report names the function and the line inside Model Composer.
    fprintf(2, '  xmcGenerate threw: %s\n', problem.message);
    fprintf(2, '  stack:\n%s\n', getReport(problem, 'extended', 'hyperlinks', 'off'));
    component = newestComponent(work, baseline);
    if isempty(component)
        mc_hdl_log_tail(work, 40);
        return
    end
    fprintf('  the engine had finished anyway: %s\n', component.folder);
end
limit = timeoutSeconds();
if ~exist('component', 'var') || isempty(component)
    component = waitForComponent(work, baseline, limit);
end
if isempty(component)
    fprintf(2, '  no component.xml after %d s\n', round(limit));
    mc_hdl_log_tail(work, 60);
    verdict = sprintf('timeout after %d s', round(limit));
    return
end
destination = fullfile(getenv('IP_REPO'), label);
if isfolder(destination)
    rmdir(destination, 's');
end
copyfile(component.folder, destination);
verdict = 'generated';
end

function component = waitForComponent(folder, baseline, limit)
component = [];
started = tic;
reported = 0;
while true
    candidates = dir(fullfile(folder, '**', 'component.xml'));
    if isempty(candidates)
        % contains({}, '_ip') raises "First argument must be text.", which is how a
        % failed generation ended the run without a report at all.
        pause(5);
        if toc(started) > limit
            return
        end
        continue
    end
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
    elapsed = toc(started);
    if elapsed > limit
        return
    end
    if elapsed - reported > 30
        fprintf('  waiting for component.xml (%d s of %d): %s\n', ...
            round(elapsed), round(limit), activity(folder));
        reported = elapsed;
    end
    pause(5);
end
end

function component = newestComponent(folder, baseline)
%NEWESTCOMPONENT The component.xml this run wrote, or empty.
component = [];
candidates = dir(fullfile(folder, '**', 'component.xml'));
if isempty(candidates)
    return
end
fresh = candidates([candidates.datenum] > baseline);
if isempty(fresh)
    return
end
[~, newest] = max([fresh.datenum]);
component = fresh(newest);
end

function limit = timeoutSeconds()
%TIMEOUTSECONDS How long one generation may take, in seconds.
limit = str2double(getenv('MC_GENERATE_TIMEOUT'));
if isnan(limit) || limit <= 0
    limit = 3600;
end
end

function text = activity(folder)
%ACTIVITY What the work folder is doing, so a wait does not look like a hang.
newest = '';
age = Inf;
files = dir(fullfile(folder, '**', '*'));
for index = 1:numel(files)
    if files(index).isdir
        continue
    end
    if files(index).datenum < age
        age = files(index).datenum;
        newest = files(index).name;
    end
end
if isempty(newest)
    text = 'nothing written yet';
else
    text = sprintf('newest file %s, %d s ago', newest, round((now - age) * 86400));
end
count = runningVivado();
if count >= 0
    text = sprintf('%s, %d Vivado process(es)', text, count);
end
end

function count = runningVivado()
count = -1;
if ~isunix
    return
end
try
    [status, output] = system('pgrep -c vivado');
    if status == 0
        count = str2double(strtrim(output));
        if isnan(count)
            count = -1;
        end
    elseif status == 1
        count = 0;
    end
catch
    count = -1;
end
end

function clearModelCopy(modelFile)
%CLEARMODELCOPY Remove the model and everything Simulink keeps beside it.
%   A newer .autosave makes open_system stop and ask a question -- impossible to
%   answer in a scripted run, and the run waits for ever.  The .r2021a copy appears
%   because the example was saved by R2021a and R2022b saves it again.
patterns = {modelFile, [modelFile '.autosave'], [modelFile '.r2021a'], ...
    [modelFile '.r20*']};
for index = 1:numel(patterns)
    hits = dir(patterns{index});
    for one = 1:numel(hits)
        file = fullfile(hits(one).folder, hits(one).name);
        if isfile(file)
            try
                delete(file);
            catch problem
                fprintf('  note: cannot delete %s: %s\n', file, problem.message);
            end
        end
    end
end
end

function startAt = firstStep()
%FIRSTSTEP Where the ladder starts, so proven steps are not generated again.
startAt = str2double(getenv('MC_BISECT_FROM'));
if isnan(startAt) || startAt < 1
    startAt = 1;
end
startAt = round(startAt);
end

function [cached, why] = cachedArtifact(label, example)
%CACHEDARTIFACT A component this step already produced, if it is not out of date.
%   Steps 1-3 generated on an earlier run; regenerating them spends ten minutes
%   proving again what is already on disk.  MC_BISECT_FRESH=1 ignores the cache.
cached = '';
why = 'nothing cached for this step';
if strcmp(getenv('MC_BISECT_FRESH'), '1')
    why = 'MC_BISECT_FRESH=1';
    return
end
component = fullfile(getenv('IP_REPO'), label, 'component.xml');
if ~isfile(component)
    why = 'no component.xml from an earlier run';
    return
end
if dir(component).datenum < dir(example).datenum
    why = sprintf('the example is newer than the artifact (%s)', datestr(dir(example).date));
    return
end
% The third step once exported a block called "ADC 1.5GSPS", whose name even holds
% a line break; that component exists and would count as a cache hit.  A name that
% is not an identifier cannot be the IP this kit exports, so regenerate instead.
name = componentName(component);
if isempty(name) || isempty(regexp(name, '^[A-Za-z0-9_]+$', 'once'))
    why = sprintf('the cached component is named %s, which cannot be an IP', ...
        printableName(name));
    return
end
cached = datestr(dir(component).date);
why = 'cached';
end

function name = componentName(file)
name = '';
try
    tokens = regexp(fileread(file), '<name>([^<]*)</name>', 'tokens', 'once');
    if ~isempty(tokens)
        name = strtrim(tokens{1});
    end
catch
    name = '';
end
end

function text = printableName(name)
if isempty(name)
    text = '<empty>';
else
    text = strrep(name, sprintf('\n'), '\\n');
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

function yes = beginsWith(text, prefix)
%BEGINSWITH startsWith, without raising on something that is not text.
yes = ischar(text) && numel(text) >= numel(prefix) && strcmp(text(1:numel(prefix)), prefix);
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
    if beginsWith(results{failedAt, 2}, 'no-op')
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
