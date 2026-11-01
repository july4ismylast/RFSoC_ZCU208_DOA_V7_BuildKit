function build_rfsoc_hdl_frontend_model()
%BUILD_RFSOC_HDL_FRONTEND_MODEL Build the synthesizable four-channel DUT.
run('sim3d_params.m');
if exist('dsphdl.Channelizer','class')~=8
    error('RFSoCHDL:MissingDSPHDL','DSP HDL Toolbox is required.');
end
coefficients=design_pfb_coefficients(P.PFB.NumBands,P.PFB.DecimationFactor, ...
    P.PFB.TapsPerBand,P.PFB.StopbandAttenuation_dB);

model='DOA_RFSoC_HDL_FrontEnd';
if bdIsLoaded(model), close_system(model,0); end
if exist([model '.slx'],'file'), delete([model '.slx']); end
new_system(model); open_system(model);
set_param(model,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep','1');

inputNames={'ADC0_IQ','ADC1_IQ','ADC2_IQ','ADC3_IQ'};
yPositions=[55 105 155 205];
for index=1:4
    add_block('simulink/Sources/In1',[model '/' inputNames{index}], ...
        'Position',[35 yPositions(index) 65 yPositions(index)+20], ...
        'Port',num2str(index),'OutDataTypeStr','fixdt(1,16,14)','SignalType','complex');
end
add_block('simulink/Sources/In1',[model '/validIn'],'Position',[35 265 65 285], ...
    'Port','5','OutDataTypeStr','boolean');

dut=[model '/RFSoC_HDL_Channelizer4'];
add_block('simulink/User-Defined Functions/MATLAB System',dut, ...
    'Position',[190 70 415 285]);
set_param(dut,'System','ZU48DRChannelizer4', ...
    'NumBands',mat2str(P.PFB.NumBands,17), ...
    'FilterCoefficients',mat2str(coefficients,17));

outputNames={'Bins0','Bins1','Bins2','Bins3'};
for index=1:4
    add_block('simulink/Sinks/Out1',[model '/' outputNames{index}], ...
        'Position',[545 yPositions(index) 575 yPositions(index)+20], ...
        'Port',num2str(index));
    add_line(model,[inputNames{index} '/1'],['RFSoC_HDL_Channelizer4/' num2str(index)]);
    add_line(model,['RFSoC_HDL_Channelizer4/' num2str(index)],[outputNames{index} '/1']);
end
add_block('simulink/Sinks/Out1',[model '/validOut'], ...
    'Position',[545 265 575 285],'Port','5');
add_line(model,'validIn/1','RFSoC_HDL_Channelizer4/5');
add_line(model,'RFSoC_HDL_Channelizer4/5','validOut/1');

annotation=Simulink.Annotation(model,sprintf([ ...
    'RFSoC HDL FRONT END - MATLAB R2024a\n' ...
    '4 coherent scalar complex streams + valid -> 4 parallel dsphdl.Channelizer cores\n' ...
    'M=%d, signed 16-bit fixed-point inputs'],P.PFB.NumBands));
annotation.Position=[75 345 535 420]; annotation.FontSize=11;
set_param(model,'SimulationCommand','update');

if exist('hdlset_param','file')==2
    hdlset_param(model,'HDLSubsystem',dut);
    hdlset_param(model,'TargetLanguage','Verilog');
    hdlset_param(model,'SynthesisTool','Xilinx Vivado');
    hdlset_param(model,'SynthesisToolChipFamily','Zynq UltraScale+ RFSoC');
    hdlset_param(model,'SynthesisToolDeviceName','xczu48dr-fsvg1517-2-e');
    hdlset_param(model,'TargetDirectory',fullfile(pwd,'hdl_prj','hdlsrc'));
end
save_system(model,[model '.slx']); open_system(model);
fprintf('Created RFSoC HDL model: %s.slx\n',model);
end
