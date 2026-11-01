% Generate synthesizable HDL from the Channelizer DUT.
% Run build_model first. Fixed-point types/coefficients must be set for your final hardware.
build_model;
load_system('zu48dr_channelizer_ip');
hdlset_param('zu48dr_channelizer_ip','HDLSubsystem','zu48dr_channelizer_ip/Channelizer_DUT');
hdlset_param('zu48dr_channelizer_ip','TargetLanguage','Verilog');
hdlset_param('zu48dr_channelizer_ip','SynthesisTool','Xilinx Vivado');
hdlset_param('zu48dr_channelizer_ip','SynthesisToolChipFamily','Zynq UltraScale+ RFSoC');
hdlset_param('zu48dr_channelizer_ip','SynthesisToolDeviceName','xczu48dr-fsvg1517-2-e');
hdlset_param('zu48dr_channelizer_ip','TargetDirectory',fullfile(pwd,'hdl_prj','hdlsrc'));
save_system('zu48dr_channelizer_ip');
makehdl('zu48dr_channelizer_ip/Channelizer_DUT');
fprintf('HDL generated under hdl_prj/hdlsrc. Package it with package_generated_rtl.tcl after checking top-module name.\n');
