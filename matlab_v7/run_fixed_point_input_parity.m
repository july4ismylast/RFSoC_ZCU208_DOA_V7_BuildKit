function report=run_fixed_point_input_parity()
%RUN_FIXED_POINT_INPUT_PARITY Compare double and signed-16-bit IQ inputs.
% This checks ADC/input quantization sensitivity. It is not a substitute for
% HDL Coder/Vitis HLS cosimulation of the complete covariance and CORDIC path.
run('sim3d_params.m');
rng(P.Sim.RandomSeed+1,'twister');
numberTrials=250;
numberSnapshots=P.DOA.NumSnapshots;
snr_dB=20;
fractionLength=14;
scale=2^fractionLength;
minimum=-2;
maximum=2-1/scale;

commonArguments={ ...
    'Algorithm','HYBRID_CAL_WPI_ML_EKF', ...
    'CenterFreqHz',P.Source.CenterFreqHz, ...
    'ArrayPositions',P.Antenna.Positions, ...
    'AzScanRange',P.DOA.AzScanRange,'ElScanRange',P.DOA.ElScanRange, ...
    'ScanResolution',P.DOA.ScanResolution, ...
    'CalibrationGain_dB',P.Calibration.EstimatedGain_dB, ...
    'CalibrationPhase_deg',P.Calibration.EstimatedPhase_deg, ...
    'MLStepSchedule_deg',P.DOA.MLStepSchedule_deg, ...
    'EnableTracking',false};
floatingEstimator=DOAEstimator4Ch(commonArguments{:});
quantizedEstimator=DOAEstimator4Ch(commonArguments{:});
floatingError=zeros(numberTrials,1);
quantizedError=zeros(numberTrials,1);

for trial=1:numberTrials
    az=P.Accuracy.AzQualified_deg(1)+diff(P.Accuracy.AzQualified_deg)*rand;
    el=P.Accuracy.ElQualified_deg(1)+diff(P.Accuracy.ElQualified_deg)*rand;
    truth=[cosd(el)*cosd(az); cosd(el)*sind(az); sind(el)];
    steering=exp(-1j*2*pi*P.Source.CenterFreqHz/P.c* ...
        (P.Antenna.Positions*truth));
    symbols=exp(1j*(pi/2)*randi([0 3],numberSnapshots,1));
    noiseScale=10^(-snr_dB/20)/sqrt(2);
    noise=noiseScale*(randn(numberSnapshots,4)+1j*randn(numberSnapshots,4));
    channelTransfer=10.^(P.Channel.Gain_dB/20).* ...
        exp(1j*deg2rad(P.Channel.PhaseError_deg));
    floating=(symbols*steering.'+noise).*channelTransfer;
    quantizedReal=min(max(real(floating),minimum),maximum);
    quantizedImag=min(max(imag(floating),minimum),maximum);
    quantized=round(quantizedReal*scale)/scale+ ...
        1j*round(quantizedImag*scale)/scale;

    [azFloat,elFloat]=floatingEstimator(floating,0,0,0);
    [azFixed,elFixed]=quantizedEstimator(quantized,0,0,0);
    floatingVector=[cosd(elFloat)*cosd(azFloat); ...
        cosd(elFloat)*sind(azFloat); sind(elFloat)];
    quantizedVector=[cosd(elFixed)*cosd(azFixed); ...
        cosd(elFixed)*sind(azFixed); sind(elFixed)];
    floatingError(trial)=acosd(max(-1,min(1,dot(floatingVector,truth))));
    quantizedError(trial)=acosd(max(-1,min(1,dot(quantizedVector,truth))));
end
release(floatingEstimator); release(quantizedEstimator);

report=table(snr_dB,numberSnapshots,numberTrials, ...
    sqrt(mean(floatingError.^2)),sqrt(mean(quantizedError.^2)), ...
    sqrt(mean(quantizedError.^2))-sqrt(mean(floatingError.^2)), ...
    'VariableNames',{'SNR_dB','Snapshots','Trials','FloatRMSE3D_deg', ...
    'QuantizedInputRMSE3D_deg','RMSEDegradation_deg'});
disp(report);
assert(report.QuantizedInputRMSE3D_deg<=P.Accuracy.Required3DRMSE_deg, ...
    'DOA2x2:FixedInputAccuracy','Signed-16-bit input failed 0.1-degree RMSE.');
assert(report.RMSEDegradation_deg<0.02, ...
    'DOA2x2:FixedInputDegradation','Input quantization added >=0.02 degree RMSE.');
end
