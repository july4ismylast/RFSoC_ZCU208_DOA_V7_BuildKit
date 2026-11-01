function build_doa_search_model()
%BUILD_DOA_SEARCH_MODEL Create the executable standalone search-stage model.
run('doa_search_params.m');
model='DOA_SearchStage_Executable';
if bdIsLoaded(model), close_system(model,0); end
if exist([model '.slx'],'file'), delete([model '.slx']); end
new_system(model); open_system(model);
set_param(model,'SolverType','Fixed-step','Solver','FixedStepDiscrete', ...
    'FixedStep',num2str(P.FramePeriod,17),'StopTime',num2str(P.StopTime,17));

source=addSystem(model,'Synthetic_4CH_Source','SyntheticFourChannelSource',[30 90 200 180]);
channelizer=addSystem(model,'PFB_FFT_Channelizer','PFBFFTChannelizer4',[270 90 450 180]);
spectrum=addSystem(model,'Spectrum_Estimator','SpectrumEstimator4',[520 70 685 200]);
noise=addSystem(model,'Noise_Floor','NoiseFloorEstimator1D',[755 245 910 325]);
cfar=addSystem(model,'CA_CFAR','CACFAR1D',[755 70 910 185]);
cluster=addSystem(model,'Bin_Clustering','BinClusterEstimator',[980 70 1145 225]);
selector=addSystem(model,'Candidate_Selector','CandidateSelector',[1220 70 1390 225]);

applyProperties(source,struct('Fs',P.Fs,'FrameLength',P.FrameLength, ...
    'SearchCenterHz',P.SearchCenterHz,'dx',P.dx,'dy',P.dy, ...
    'NumTargets',P.NumTargets,'TargetOffsetHz',P.TargetOffsetHz, ...
    'TargetBandwidthHz',P.TargetBandwidthHz,'TargetSNRdB',P.TargetSNRdB, ...
    'TargetAzDeg',P.TargetAzDeg,'TargetElDeg',P.TargetElDeg, ...
    'NumInterferers',P.NumInterferers,'InterfererOffsetHz',P.InterfererOffsetHz, ...
    'InterfererBandwidthHz',P.InterfererBandwidthHz, ...
    'InterfererSNRdB',P.InterfererSNRdB,'InterfererAzDeg',P.InterfererAzDeg, ...
    'InterfererElDeg',P.InterfererElDeg,'ChannelGain_dB',P.ChannelGain_dB, ...
    'ChannelPhaseError_deg',P.ChannelPhaseError_deg));
applyProperties(channelizer,struct('FrameLength',P.FrameLength,'NumBands',P.NumBands, ...
    'DecimationFactor',P.DecimationFactor,'TapsPerBand',P.TapsPerBand, ...
    'StopbandAttenuation_dB',P.StopbandAttenuation_dB));
applyProperties(spectrum,struct('Fs',P.Fs,'NumBands',P.NumBands, ...
    'AverageAlpha',P.SpectrumAverageAlpha,'PowerFloor',P.SpectrumFloor));
applyProperties(noise,struct('NumBins',P.NumBands, ...
    'MedianWindowBins',P.NoiseMedianWindowBins,'PowerFloor',P.SpectrumFloor));
applyProperties(cfar,struct('NumBins',P.NumBands,'TrainCells',P.CFAR_TrainCells, ...
    'GuardCells',P.CFAR_GuardCells,'Pfa',P.CFAR_Pfa));
applyProperties(cluster,struct('NumBins',P.NumBands,'MaxClusters',P.MaxClusters, ...
    'MergeGapBins',P.MergeGapBins,'MinClusterBins',P.MinClusterBins, ...
    'PowerFloor',P.SpectrumFloor));
applyProperties(selector,struct('MaxClusters',P.MaxClusters, ...
    'BW_MinHz',P.TargetBW_MinHz,'BW_MaxHz',P.TargetBW_MaxHz, ...
    'MinCandidateSNRdB',P.MinCandidateSNRdB));

add_line(model,'Synthetic_4CH_Source/1','PFB_FFT_Channelizer/1','autorouting','on');
add_line(model,'PFB_FFT_Channelizer/1','Spectrum_Estimator/1','autorouting','on');
add_line(model,'Spectrum_Estimator/2','CA_CFAR/1','autorouting','on');
add_line(model,'Spectrum_Estimator/2','Noise_Floor/1','autorouting','on');
add_line(model,'CA_CFAR/1','Bin_Clustering/1','autorouting','on');
add_line(model,'Spectrum_Estimator/2','Bin_Clustering/2','autorouting','on');
add_line(model,'Spectrum_Estimator/4','Bin_Clustering/3','autorouting','on');
add_line(model,'Bin_Clustering/1','Candidate_Selector/1','autorouting','on');
add_line(model,'Bin_Clustering/2','Candidate_Selector/2','autorouting','on');
add_line(model,'Bin_Clustering/3','Candidate_Selector/3','autorouting','on');
add_line(model,'Bin_Clustering/6','Candidate_Selector/4','autorouting','on');
add_line(model,'Noise_Floor/3','Candidate_Selector/5','autorouting','on');

addToWorkspace(model,'Spectrum_dB',[755 365 860 395],'Spectrum_dB');
addToWorkspace(model,'Frequency_Hz',[755 415 860 445],'Frequency_Hz');
addToWorkspace(model,'Detections',[940 365 1045 395],'Detections');
addToWorkspace(model,'Selected_fc_Hz',[1190 300 1310 330],'Selected_fc_Hz');
addToWorkspace(model,'Selected_BW_Hz',[1340 300 1460 330],'Selected_BW_Hz');
addToWorkspace(model,'Candidate_Valid',[1190 350 1310 380],'Candidate_Valid');
add_line(model,'Spectrum_Estimator/3','Spectrum_dB/1','autorouting','on');
add_line(model,'Spectrum_Estimator/4','Frequency_Hz/1','autorouting','on');
add_line(model,'CA_CFAR/1','Detections/1','autorouting','on');
add_line(model,'Candidate_Selector/3','Selected_fc_Hz/1','autorouting','on');
add_line(model,'Candidate_Selector/4','Selected_BW_Hz/1','autorouting','on');
add_line(model,'Candidate_Selector/1','Candidate_Valid/1','autorouting','on');

set_param(model,'SimulationCommand','update');
save_system(model,[model '.slx']); open_system(model);
fprintf('Created %s.slx\n',model);
end

function block=addSystem(model,name,className,position)
block=[model '/' name];
add_block('simulink/User-Defined Functions/MATLAB System',block,'Position',position);
set_param(block,'System',className);
end
function applyProperties(block,values)
names=fieldnames(values);
for index=1:numel(names)
    value=values.(names{index});
    if ischar(value) || isstring(value), textValue=char(value);
    else, textValue=mat2str(value,17); end
    set_param(block,names{index},textValue);
end
end
function addToWorkspace(model,name,position,variableName)
add_block('simulink/Sinks/To Workspace',[model '/' name],'Position',position, ...
    'VariableName',variableName,'SaveFormat','Array');
end
