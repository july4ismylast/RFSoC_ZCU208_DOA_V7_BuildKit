%% DOA 3D HOMING SIMULATION - MASTER PARAMETERS
clear P
P.c = 299792458;

P.Source.Position = [500 300 200];
P.Source.CenterFreqHz = 4.0e9;
P.Source.ModulationType = 'QAM16';
P.Source.PowerdBm = 40;

P.Platform.Position0 = [0 0 50];
P.Platform.Velocity = 25;
P.Platform.MaxTurnRate = 20;
P.Platform.MaxClimbRate = 10;
P.Platform.Heading0 = 0;
P.Platform.Pitch0 = 0;
P.Platform.Roll0 = 0;
P.Platform.NavFilterAlpha = 0.3;

% Physical 2x2 square array on the vehicle nose (the Y-Z plane).  The
% boresight is +X.  With d=25 mm at 4 GHz, even the diagonal baseline is
% below lambda/2, so every one of the six pair phases is unambiguous.
P.Antenna.d = 0.025;
P.Antenna.dx = 0;
P.Antenna.dy = P.Antenna.d;
P.Antenna.dz = P.Antenna.d;
P.Antenna.Positions = [ ...
    0 -P.Antenna.d/2 -P.Antenna.d/2; ...
    0  P.Antenna.d/2 -P.Antenna.d/2; ...
    0 -P.Antenna.d/2  P.Antenna.d/2; ...
    0  P.Antenna.d/2  P.Antenna.d/2];

P.Channel.Gain_dB = [0 0.3 -0.2 0.15];
P.Channel.PhaseError_deg = [0 1.0 -0.7 0.5];
P.Channel.NoiseFigure_dB = 3.0;
P.Channel.PathLossExponent = 2.0;

% Select IDEAL, CALIBRATED_LOS, or FIELD_STRESS. The formal 0.1-degree
% acceptance condition applies to CALIBRATED_LOS; FIELD_STRESS is deliberately
% difficult and reports degradation rather than silently forcing a pass.
P.Realism.Profile = 'CALIBRATED_LOS';
R=realism_profile(P.Realism.Profile,P.Antenna.Positions,P.Source.CenterFreqHz);
P.Antenna.ActualPositions=R.Array.ActualPositions;
P.Antenna.CalibratedPositions=R.Array.CalibratedPositions;
P.Multipath=R.Multipath;
P.Receiver=R.Receiver;
P.Receiver.Fs=2.048e9;
P.Receiver.FrameLength=8192;
P.Receiver.CenterFreqHz=P.Source.CenterFreqHz;
P.Receiver.NoiseFigure_dB=P.Channel.NoiseFigure_dB;
P.Receiver.ChannelGain_dB=P.Channel.Gain_dB;
P.Receiver.ChannelPhase_deg=P.Channel.PhaseError_deg;
P.Receiver.CommonPhaseNoiseStep_deg=.002;
P.Receiver.AGCTargetRMS=.25;
P.Receiver.AGCMaximumGain_dB=90;
P.Receiver.ADCBits=14;
P.Receiver.ADCFullScale=1;
P.Receiver.DCOffset=[0 2 -1 1]*2^-16;
P.Receiver.EnableThermalNoise=true;
P.Receiver.EnableAGC=true;
P.Receiver.EnableADCQuantization=true;

% Receiver calibration estimates.  The small residuals below are deliberate:
% they make the acceptance test realistic instead of silently assuming a
% mathematically perfect receiver.  In hardware these values are written by
% the calibration routine after RFDC MTS and cable/antenna calibration.
P.Calibration.ResidualGain_dB = [0 0.005 -0.004 0.006];
P.Calibration.ResidualPhase_deg = [0 0.020 -0.020 0.030];
P.Calibration.EstimatedGain_dB = P.Channel.Gain_dB- ...
    P.Calibration.ResidualGain_dB;
P.Calibration.EstimatedPhase_deg = P.Channel.PhaseError_deg+ ...
    R.Calibration.TimeSkewPhase_deg- ...
    P.Calibration.ResidualPhase_deg;
P.Calibration.DecouplingMatrix=R.Calibration.DecouplingMatrix;
clear R

P.PFB.Fs = 2.048e9;
P.PFB.FrameLength = 8192;
P.PFB.NumBands = 1024;
P.PFB.DecimationFactor = 1024;
P.PFB.TapsPerBand = 12;
P.PFB.StopbandAttenuation_dB = 100;
P.PFB.ChannelSpacingHz = P.PFB.Fs/P.PFB.NumBands;

% Fetch the complete parameter set for the selected modulation. To change an
% LFM, NLFM, PM, or another waveform profile, edit its switch/case in
% source_modulation_profile.m rather than mixing unrelated controls here.
waveform=source_modulation_profile(P.Source.ModulationType);
waveformFields=fieldnames(waveform);
for waveformIndex=1:numel(waveformFields)
    waveformField=waveformFields{waveformIndex};
    P.Source.(waveformField)=waveform.(waveformField);
end
clear waveform waveformFields waveformIndex waveformField

% OPTIONAL EXPERIMENT OVERRIDES (place them here, after profile loading).
% Example for a 130 MHz LFM sweep:
% P.Source.SweepStartHz = -65e6;
% P.Source.SweepStopHz = 65e6;
% P.Source.SweepTimeSeconds = P.PFB.FrameLength/P.PFB.Fs;
% P.Source.BandwidthHz = 130e6;

P.Spectrum.AverageAlpha = 0.25;
P.Spectrum.PowerFloor = 1e-15;
P.Noise.MedianWindowBins = 81;

P.CFAR.TrainCells = 24;
P.CFAR.GuardCells = 4;
P.CFAR.Pfa = 1e-3;

P.Cluster.MaxClusters = 16;
P.Cluster.MergeGapBins = 1;
P.Cluster.MinClusterBins = 1;

P.Candidate.BW_MinHz = 0.5e6;
P.Candidate.BW_MaxHz = max(40e6,1.25*P.Source.BandwidthHz);
P.Candidate.MinSNRdB = 3;

P.DOA.Algorithm = 'HYBRID_CAL_WPI_ML_EKF';
P.DOA.NumSnapshots = 4096;
P.DOA.SnapshotStride = P.PFB.FrameLength/P.DOA.NumSnapshots;
% A planar 2x2 array needs the known forward-hemisphere constraint.  These
% limits describe the qualified precision field of view, not an all-sky claim.
P.DOA.AzScanRange = [-55 55];
P.DOA.ElScanRange = [-45 45];
% The hybrid estimator is off-grid; this 1-degree value controls only the
% lightweight display matrix and the optional legacy MUSIC/MVDR modes.
P.DOA.ScanResolution = 1;
P.DOA.NumSignals = 1;
P.DOA.ForwardBackwardAvg = true;
P.DOA.ArrayPositions = P.Antenna.CalibratedPositions;
P.DOA.CalibrationGain_dB = P.Calibration.EstimatedGain_dB;
P.DOA.CalibrationPhase_deg = P.Calibration.EstimatedPhase_deg;
P.DOA.CalibrationDecouplingMatrix=P.Calibration.DecouplingMatrix;
% Fixed, bounded local search: 4 stages x 9 candidates = 36 ML scores/frame.
P.DOA.MLStepSchedule_deg = [0.5 0.1 0.02 0.005];
P.DOA.EnableGNPolish=true;
P.DOA.GNIterations=2;
P.DOA.GNMaxStep_deg=.05;
P.DOA.EnableTracking = true;
P.DOA.TrackerDt = 0.1;
P.DOA.EKFProcessNoise = 2e-5;
P.DOA.EKFMeasurementNoise = 1.5e-5;

% Definition of the 0.1-degree claim.  It is checked by
% run_accuracy_campaign, not inferred from one homing plot.
P.Accuracy.Required3DRMSE_deg = 0.1;
P.Accuracy.MinimumInputSNR_dB = 15;
P.Accuracy.SnapshotsPerEstimate = P.DOA.NumSnapshots;
P.Accuracy.AzQualified_deg = [-45 45];
P.Accuracy.ElQualified_deg = [-35 35];
P.Accuracy.MonteCarloTrials = 1000;

P.Nav.GuidanceLaw = 'pure_pursuit';
P.Nav.ProNavGain = 3;
P.Nav.ArrivalRadius = 10;
P.Nav.HeadingUpdateRate = 10;
P.Nav.MaxSimTime = 60;

P.Sim.Dt = 0.1;
P.Sim.StopTime = P.Nav.MaxSimTime;
P.Sim.FramePeriod = P.PFB.FrameLength/P.PFB.Fs;
P.Sim.RandomSeed = 8675309;
assert(abs(P.DOA.TrackerDt-P.Sim.Dt)<eps, ...
    'TrackerDt must match the DOA/Simulink frame update interval P.Sim.Dt.');

P.GUI.Enable = true;
P.GUI.UpdateRate = 10;

assert(mod(P.PFB.FrameLength,P.PFB.DecimationFactor)==0, ...
    'FrameLength must be a multiple of DecimationFactor.');
assert(P.PFB.DecimationFactor<=P.PFB.NumBands);
assert(P.Source.BandwidthHz>0 && P.Source.BandwidthHz<P.PFB.Fs, ...
    'Source bandwidth must be positive and below the complex sample rate.');
assert(P.Source.ModulationToneHz>0,'ModulationToneHz must be positive.');
assert(P.Source.SweepTimeSeconds>0,'SweepTimeSeconds must be positive.');
assert(P.Source.SweepStopHz>P.Source.SweepStartHz, ...
    'SweepStopHz must be greater than SweepStartHz.');
selectedModulation=upper(char(P.Source.ModulationType));
if any(strcmp(selectedModulation,{'LFM','CHIRP','NLFM','PULSED_LFM','LFM_PULSE'}))
    assert(max(abs([P.Source.SweepStartHz P.Source.SweepStopHz]))<P.PFB.Fs/2, ...
        'Sweep start/stop must lie inside the complex Nyquist interval.');
    assert(P.Source.BandwidthHz>=abs(P.Source.SweepStopHz-P.Source.SweepStartHz), ...
        'BandwidthHz must contain the complete LFM/NLFM sweep span.');
end
clear selectedModulation
assert(P.Source.PRFHz>0 && P.Source.PulseWidthSeconds>0, ...
    'PulseWidthSeconds and PRFHz must be positive.');
assert(P.Source.PulseWidthSeconds*P.Source.PRFHz<=1, ...
    'PulseWidthSeconds*PRFHz must not exceed one.');
assert(mod(P.PFB.FrameLength,P.DOA.NumSnapshots)==0, ...
    'DOA NumSnapshots must divide FrameLength.');
assert(mod(P.Noise.MedianWindowBins,2)==1,'MedianWindowBins must be odd.');
assert(P.DOA.NumSignals>=1 && P.DOA.NumSignals<4,'NumSignals must be 1, 2, or 3.');
lambda=P.c/P.Source.CenterFreqHz;
baselineDistances=pdist_local(P.Antenna.ActualPositions);
assert(max(baselineDistances)<=lambda/2, ...
    'The largest 2x2 baseline must be <= lambda/2 for unambiguous phase LS.');
fprintf('Params loaded. Source=[%.0f,%.0f,%.0f] Platform=[%.0f,%.0f,%.0f]\n', ...
    P.Source.Position,P.Platform.Position0);
fprintf('Selected source: %s, BW %.1f MHz, %s\n',P.Source.ModulationType, ...
    P.Source.BandwidthHz/1e6,source_modulation_summary(P.Source));
fprintf('Realism profile: %s, %d-bit ADC, calibrated coupling and position manifold.\n', ...
    P.Realism.Profile,P.Receiver.ADCBits);

function distances=pdist_local(positions)
distances=zeros(6,1); pairIndex=0;
for first=1:3
    for second=first+1:4
        pairIndex=pairIndex+1;
        distances(pairIndex)=norm(positions(second,:)-positions(first,:));
    end
end
end
