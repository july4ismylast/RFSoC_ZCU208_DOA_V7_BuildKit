function make_channelizer_model(destination)
%MAKE_CHANNELIZER_MODEL Build the channelizer model from scratch, without a GUI.
%   A .slx is a binary that nobody can review, so the model lives here as code:
%   this function creates the model with new_system/add_block/add_line and saves
%   it as destination (default: channelizer.slx next to this file).
%
%   A batch MATLAB session does not know Model Composer: the block libraries are
%   files inside the installation and only the GUI launcher adds their folders.
%   mc_paths() finds them from MC_ROOT / MC_VIVADO_ROOT and adds them; if a
%   library still cannot be loaded, this function says which folder it searched
%   and which blocks it did find, instead of dying with "no block named".
%
%   Structure follows UG1483: the Vitis Model Composer Hub at the top level,
%   Gateway In blocks for the inputs, Gateway Out blocks for the outputs, the
%   datapath between them.  Four channels, Q2.14, 200 MHz, exported as an IP
%   Catalog IP.
%
%   Block library paths are the 2023.2 ones, read out of a real 2023.2 model
%   (Examples/HDL/RFSoC/SSR_Digital_Down_Conversion/SSRDDC.slx on branch 2023.2
%   of Xilinx/Vitis_Model_Composer): hdlBasic/Gateway In, hdlBasic/Gateway Out,
%   hdlBasic/Delay, vmcUtilities/Vitis Model Composer Hub.
arguments
    destination (1, :) char = ''
end

here = fileparts(mfilename('fullpath'));
if isempty(destination)
    destination = fullfile(here, 'channelizer.slx');
end
[modelDir, modelName] = fileparts(destination);
if isempty(modelDir)
    modelDir = here;
    destination = fullfile(modelDir, [modelName '.slx']);
end

channels = 4;
bits = 16;
binaryPoint = 14;
sampleHz = 200e6;
tapDelay = 4;

fprintf('looking for the Model Composer libraries\n');
info = mc_paths();
requireLibrary('vmcUtilities', info);
requireLibrary('hdlBasic', info);

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if isfile(destination)
    delete(destination);
end

new_system(modelName);
cleanup = onCleanup(@() discardIfOpen(modelName));
set_param(modelName, 'Solver', 'FixedStepDiscrete', ...
    'FixedStep', '1', 'StopTime', '16', 'SaveTime', 'off', 'SaveOutput', 'off');

% ---------------------------------------------------------------- the Hub ---
hub = [modelName '/Vitis Model Composer Hub'];
addFromLibrary('vmcUtilities', 'Vitis Model Composer Hub', hub, [40, 60, 90, 110]);
applyParam(hub, 'ExportType', 'IP Catalog');
applyParam(hub, 'IpVendor', 'doa.v7');
applyParam(hub, 'IpLibrary', 'model_composer');
applyParam(hub, 'IpVersion', '1.0');
applyParam(hub, 'IpHWLanguage', 'Verilog');
applyParam(hub, 'part', 'xczu208');
applyParam(hub, 'xilinxfamily', 'zynquplus');
applyParam(hub, 'Part', 'xczu208-ffvb1156-2-e');
applyParam(hub, 'ProjDevicePart', 'xczu208-ffvb1156-2-e');
applyParam(hub, 'sysclk_period', num2str(1e9 / sampleHz));
applyParam(hub, 'simulink_period', '1');

% ------------------------------------------------------------ the channels ---
for channel = 1:channels
    row = 150 + 60 * (channel - 1);
    inBlock = sprintf('%s/In%d', modelName, channel);
    delayBlock = sprintf('%s/Delay%d', modelName, channel);
    outBlock = sprintf('%s/Out%d', modelName, channel);

    addFromLibrary('hdlBasic', 'Gateway In', inBlock, [40, row, 90, row + 20]);
    applyParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    applyParam(inBlock, 'arith_type', 'Signed (2''s comp)');
    applyParam(inBlock, 'n_bits', num2str(bits));
    applyParam(inBlock, 'bin_pt', num2str(binaryPoint));
    applyParam(inBlock, 'quantization', 'Truncate');
    applyParam(inBlock, 'overflow', 'Wrap');
    applyParam(inBlock, 'period', '1');

    addFromLibrary('hdlBasic', 'Delay', delayBlock, [160, row, 190, row + 20]);
    applyParam(delayBlock, 'latency', num2str(tapDelay));

    addFromLibrary('hdlBasic', 'Gateway Out', outBlock, [270, row, 320, row + 20]);
    applyParam(outBlock, 'period', '1');

    add_line(modelName, sprintf('In%d/1', channel), sprintf('Delay%d/1', channel), ...
        'autorouting', 'on');
    add_line(modelName, sprintf('Delay%d/1', channel), sprintf('Out%d/1', channel), ...
        'autorouting', 'on');
end

% ------------------------------------------------------------------- save ----
save_system(modelName, destination);
close_system(modelName, 0);

fprintf('\nmodel created: %s\n', destination);
fprintf('  %d channels, %d.%d signed fixed point, %g MHz, %d-clock delay each\n', ...
    channels, bits - binaryPoint, binaryPoint, sampleHz / 1e6, tapDelay);
fprintf('  Hub export target: %s\n', readable(hub, 'ExportType'));
fprintf('MC_MODEL_CREATED %s\n', destination);
end

function requireLibrary(name, info)
%REQUIRELIBRARY Load one Model Composer library, or explain what is missing.
try
    load_system(name);
    fprintf('library loaded: %s\n', name);
    return;
catch problem
    reason = problem.message;
end
fprintf('\nERROR: the Model Composer library "%s" could not be loaded.\n', name);
fprintf('  loaded error: %s\n', reason);
fprintf('  MC_ROOT:      %s\n', info.mcRoot);
fprintf('  MC_VIVADO_ROOT: %s\n', info.vivadoRoot);
if isempty(info.mcRoot)
    fprintf('  MC_ROOT is empty: set MODEL_COMPOSER in config.local.mk so it can be derived.\n');
else
    fprintf('  searched %s recursively for %s.slx\n', info.mcRoot, name);
end
if isempty(info.found)
    fprintf('  no Model Composer library file was found at all.\n');
else
    fprintf('  library files that WERE found:\n');
    for index = 1:numel(info.found)
        fprintf('    %-12s %s\n', info.found(index).name, info.found(index).file);
    end
end
fprintf(['  Diagnose with: make mc-libs   (prints the same search, no model built)\n' ...
         '  The GUI sets this up itself, so the same builder works there:\n' ...
         '      make mc-gui\n' ...
         '      then in the MATLAB Command Window:  mc_gui_build\n']);
error('make_channelizer_model:library', 'library %s is not loadable', name);
end

function addFromLibrary(library, blockName, path, position)
%ADDFROMLIBRARY Add one block, listing the library contents if the name is wrong.
try
    add_block([library '/' blockName], path, 'Position', position);
catch problem
    fprintf('\nERROR: add_block(''%s/%s'') failed: %s\n', library, blockName, problem.message);
    listLibrary(library);
    error('make_channelizer_model:block', 'cannot add %s/%s', library, blockName);
end
end

function listLibrary(library)
%LISTLIBRARY Print the top-level blocks of a library, so the right name is visible.
try
    load_system(library);
    blocks = find_system(library, 'SearchDepth', 1, 'Type', 'Block');
catch problem
    fprintf('  (cannot list %s: %s)\n', library, problem.message);
    return;
end
fprintf('  blocks available in %s (%d):\n', library, numel(blocks));
for index = 1:min(numel(blocks), 40)
    fprintf('    %s\n', blocks{index});
end
if numel(blocks) > 40
    fprintf('    ... %d more\n', numel(blocks) - 40);
end
end

function discardIfOpen(modelName)
%DISCARDIFOPEN Leave no half-built model behind when this function fails.
try
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
catch problem
    fprintf('note: could not close %s: %s\n', modelName, problem.message);
end
end

function readable = readable(block, parameter)
%READABLE Read a block parameter without failing the build.
readable = '<not readable>';
try
    readable = get_param(block, parameter);
catch problem
    readable = sprintf('<%s>', problem.message);
end
end

function applyParam(block, parameter, value)
%APPLYPARAM Write one block parameter, printing whether it took.
try
    set_param(block, parameter, value);
    fprintf('  %s.%s = %s\n', shortName(block), parameter, value);
catch problem
    fprintf('  skipped %s.%s = %s (%s)\n', shortName(block), parameter, value, ...
        problem.message);
end
end

function name = shortName(block)
%SHORTNAME Last path element of a block path.
parts = strsplit(block, '/');
name = parts{end};
end
