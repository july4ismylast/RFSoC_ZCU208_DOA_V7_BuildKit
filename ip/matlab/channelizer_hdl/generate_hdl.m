function generatedTopFile = generate_hdl()
%GENERATE_HDL Generate one-channel Verilog from the Channelizer DUT.
%
% This function rebuilds the Simulink harness from the config.mk values
% exported in the environment, then invokes HDL Coder for the explicit
% Channelizer_DUT subsystem.  It deliberately does not package the RTL:
% V06 packaging remains blocked until the AXI4-Stream wrapper contract
% is frozen after the generation/OOC/numerical gates.

model = 'zu48dr_channelizer_ip';
dut = [model '/Channelizer_DUT'];
scriptDir = fileparts(mfilename('fullpath'));
targetDirectory = fullfile(scriptDir, 'hdl_prj', 'hdlsrc');

part = strtrim(getenv('PART'));
if isempty(part)
    part = 'xczu48dr-fsvg1517-2-e';
end

build_model();
load_system(model);
cleanup = onCleanup(@() close_system(model, 0)); %#ok<NASGU>

hdlset_param(model, 'HDLSubsystem', dut);
hdlset_param(model, 'TargetLanguage', 'Verilog');
hdlset_param(model, 'SynthesisTool', 'Xilinx Vivado');
hdlset_param(model, 'SynthesisToolChipFamily', 'Zynq UltraScale+ RFSoC');
hdlset_param(model, 'SynthesisToolDeviceName', part);
hdlset_param(model, 'TargetDirectory', targetDirectory);
save_system(model);

makehdl(dut);

expectedTopFile = fullfile(targetDirectory, model, 'Channelizer_DUT.v');
if exist(expectedTopFile, 'file')
    generatedTopFile = expectedTopFile;
else
    matches = dir(fullfile(targetDirectory, '**', 'Channelizer_DUT.v'));
    if isempty(matches)
        error('V06:GeneratedTopMissing', ...
            'HDL Coder finished but Channelizer_DUT.v was not found under %s.', ...
            targetDirectory);
    end
    generatedTopFile = fullfile(matches(1).folder, matches(1).name);
end

fprintf('HDL generated top: %s\n', generatedTopFile);
fprintf('Packaging is intentionally not performed by generate_hdl.\n');
end
