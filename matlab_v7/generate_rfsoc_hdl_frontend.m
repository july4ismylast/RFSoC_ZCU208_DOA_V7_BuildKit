%% Generate Verilog for the RFSoC channelizer DUT.
rehash path;
build_rfsoc_hdl_frontend_model;
if exist('makehdl','file')~=2
    error('RFSoCHDL:MissingHDLCoder','HDL Coder is required to generate Verilog.');
end
makehdl('DOA_RFSoC_HDL_FrontEnd/RFSoC_HDL_Channelizer4');
fprintf('HDL generated under %s\n',fullfile(pwd,'hdl_prj','hdlsrc'));
