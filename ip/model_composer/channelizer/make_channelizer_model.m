function make_channelizer_model(destination)
%MAKE_CHANNELIZER_MODEL Build the channelizer model from scratch, without a GUI.
%   A .slx is a binary that nobody can review, so the model lives here as code:
%   this function creates the model with new_system/add_block/add_line and saves
%   it as destination (default: channelizer.slx next to this file).
%
%   The structure is the one Vitis Model Composer expects (UG1483): a Vitis
%   Model Composer Hub block at the top level, Gateway In blocks for the inputs,
%   the datapath in the middle, Gateway Out blocks for the outputs.  Four
%   channels, 16-bit signed fixed point at 200 MHz, exported as an IP Catalog IP
%   named by the Hub block.
%
%   Every block parameter is written through a helper that prints what it did
%   and never aborts the build: block parameter names differ between Model
%   Composer releases, and a wrong name must show up in the log as "skipped",
%   not as a silent half-built model.
%
%   Block library paths are the 2023.2 ones, taken from a real 2023.2 example
%   (Examples/HDL/RFSoC/SSR_Digital_Down_Conversion/SSRDDC.slx on the 2023.2
%   branch of Xilinx/Vitis_Model_Composer): hdlBasic/Gateway In,
%   hdlBasic/Gateway Out, hdlBasic/Delay, vmcUtilities/Vitis Model Composer Hub.
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

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if isfile(destination)
    delete(destination);
end

new_system(modelName);
set_param(modelName, 'Solver', 'FixedStepDiscrete', ...
    'FixedStep', '1', 'StopTime', '16', 'SaveTime', 'off', 'SaveOutput', 'off');

% ---------------------------------------------------------------- the Hub ---
hub = [modelName '/Vitis Model Composer Hub'];
add_block('vmcUtilities/Vitis Model Composer Hub', hub, ...
    'Position', [40, 60, 90, 110]);
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

    add_block('hdlBasic/Gateway In', inBlock, 'Position', [40, row, 90, row + 20]);
    applyParam(inBlock, 'gui_display_data_type', 'Fixed-point');
    applyParam(inBlock, 'arith_type', 'Signed (2''s comp)');
    applyParam(inBlock, 'n_bits', num2str(bits));
    applyParam(inBlock, 'bin_pt', num2str(binaryPoint));
    applyParam(inBlock, 'quantization', 'Truncate');
    applyParam(inBlock, 'overflow', 'Wrap');
    applyParam(inBlock, 'period', '1');

    add_block('hdlBasic/Delay', delayBlock, 'Position', [160, row, 190, row + 20]);
    applyParam(delayBlock, 'latency', num2str(tapDelay));

    add_block('hdlBasic/Gateway Out', outBlock, 'Position', [270, row, 320, row + 20]);
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

function readable(block, parameter)
%READABLE Read a block parameter without failing the build.
value = '<not readable>';
try
    value = get_param(block, parameter);
catch problem
    value = sprintf('<%s>', problem.message);
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
