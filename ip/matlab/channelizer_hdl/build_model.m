function build_model()
%BUILD_MODEL Build a fixed-point, four-sample-vector HDL Coder harness.
model='zu48dr_channelizer_ip';
if bdIsLoaded(model), close_system(model,0); end
if exist([model '.slx'],'file'), delete([model '.slx']); end
new_system(model);

% Match the production DSP System Toolbox prototype: 12 taps per band and
% 80 dB stopband attenuation. The coefficients become a saved model-workspace
% constant, so no run-time filter design logic is synthesized.
numBands = 64;
referenceChannelizer = dsp.Channelizer( ...
    NumFrequencyBands=numBands, ...
    NumTapsPerBand=12, ...
    StopbandAttenuation=80);
coefficientStruct = coeffs(referenceChannelizer);
channelizerCoefficients = coefficientStruct.Numerator;
release(referenceChannelizer);
modelWorkspace = get_param(model,'ModelWorkspace');
assignin(modelWorkspace,'doaChannelizerNumBands',numBands);
assignin(modelWorkspace,'doaChannelizerCoefficients',channelizerCoefficients);

add_block('simulink/Sources/In1',[model '/dataIn'],'Position',[30 60 60 80], ...
    'OutDataTypeStr','fixdt(1,16,15)','PortDimensions','[4 1]','SignalType','complex');
add_block('simulink/Sources/In1',[model '/validIn'],'Position',[30 120 60 140], ...
    'OutDataTypeStr','boolean','PortDimensions','[1 1]');

% HDL Coder requires a model or Subsystem as its DUT. Keep the MATLAB System
% block one level below an explicit atomic subsystem so makehdl can generate a
% stable Channelizer_DUT module and interface.
dut=[model '/Channelizer_DUT'];
add_block('built-in/Subsystem',dut,'Position',[130 45 350 155], ...
    'TreatAsAtomicUnit','on');
add_block('simulink/Sources/In1',[dut '/dataIn'],'Position',[25 35 55 55], ...
    'Port','1');
add_block('simulink/Sources/In1',[dut '/validIn'],'Position',[25 95 55 115], ...
    'Port','2');
core=[dut '/ChannelizerCore'];
add_block('simulink/User-Defined Functions/MATLAB System',core, ...
    'Position',[115 25 305 125]);
set_param(core,'System','ZU48DRChannelizer');
set_param(core, ...
    'NumBands','doaChannelizerNumBands', ...
    'Coefficients','doaChannelizerCoefficients');
add_block('simulink/Sinks/Out1',[dut '/dataOut'],'Position',[365 35 395 55], ...
    'Port','1');
add_block('simulink/Sinks/Out1',[dut '/validOut'],'Position',[365 95 395 115], ...
    'Port','2');
add_line(dut,'dataIn/1','ChannelizerCore/1');
add_line(dut,'validIn/1','ChannelizerCore/2');
add_line(dut,'ChannelizerCore/1','dataOut/1');
add_line(dut,'ChannelizerCore/2','validOut/1');

add_block('simulink/Sinks/Out1',[model '/dataOut'],'Position',[420 60 450 80]);
add_block('simulink/Sinks/Out1',[model '/validOut'],'Position',[420 120 450 140]);
add_line(model,'dataIn/1','Channelizer_DUT/1');
add_line(model,'validIn/1','Channelizer_DUT/2');
add_line(model,'Channelizer_DUT/1','dataOut/1');
add_line(model,'Channelizer_DUT/2','validOut/1');
set_param(model,'SolverType','Fixed-step','Solver','FixedStepDiscrete','StopTime','256');
set_param(model,'SimulationCommand','update');
save_system(model);
fprintf('Created fixed-point vector harness %s.slx: %d bands, %d taps, 4 samples/cycle.\n', ...
    model,numBands,numel(channelizerCoefficients));
end
