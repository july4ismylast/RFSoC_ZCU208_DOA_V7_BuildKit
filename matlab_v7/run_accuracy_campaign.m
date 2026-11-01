function results=run_accuracy_campaign(mode)
%RUN_ACCURACY_CAMPAIGN Reproducible statistical test of the 0.1-degree claim.
%
%   RESULTS=RUN_ACCURACY_CAMPAIGN('acceptance') runs 1000 independent
%   directions at each SNR.  'quick' uses 100 trials for a short smoke test.
%
% Accuracy is the root mean square of the exact great-circle separation
% between true and estimated unit vectors.  Azimuth/elevation RMSE, bias,
% and 95th-percentile great-circle error are reported separately.  This is
% not a grid step, a single plot point, or an average of 1000 output angles.

if nargin<1, mode='acceptance'; end
mode=lower(char(mode));
run('sim3d_params.m');

switch mode
    case 'quick'
        numberTrials=100;
    case 'acceptance'
        numberTrials=P.Accuracy.MonteCarloTrials;
    otherwise
        error('DOA2x2:CampaignMode','Mode must be ''quick'' or ''acceptance''.');
end

snrValues=[10 15 18 20 25];
numberSnapshots=P.Accuracy.SnapshotsPerEstimate;
rng(P.Sim.RandomSeed,'twister');

metricNames={'SNR_dB','Snapshots','Trials','AzBias_deg','ElBias_deg', ...
    'AzRMSE_deg','ElRMSE_deg','RMSE3D_deg','P95_3D_deg','Pass_0p1deg'};
metricValues=zeros(numel(snrValues),numel(metricNames));

fprintf('\n=== 2x2 HYBRID DOA ACCURACY CAMPAIGN ===\n');
fprintf(['Definition: great-circle RMSE over independent Monte-Carlo estimates; ' ...
    'Az %.0f..%.0f deg, El %.0f..%.0f deg, %d snapshots/estimate.\n'], ...
    P.Accuracy.AzQualified_deg,P.Accuracy.ElQualified_deg,numberSnapshots);
fprintf('Receiver calibration residual phase = [%s] deg.\n\n', ...
    sprintf(' %.3f',P.Calibration.ResidualPhase_deg));

for snrIndex=1:numel(snrValues)
    snr_dB=snrValues(snrIndex);
    estimator=DOAEstimator4Ch( ...
        'Algorithm','HYBRID_CAL_WPI_ML_EKF', ...
        'CenterFreqHz',P.Source.CenterFreqHz, ...
        'ArrayPositions',P.Antenna.Positions, ...
        'AzScanRange',P.DOA.AzScanRange,'ElScanRange',P.DOA.ElScanRange, ...
        'ScanResolution',P.DOA.ScanResolution, ...
        'ForwardBackwardAvg',P.DOA.ForwardBackwardAvg, ...
        'CalibrationGain_dB',P.Calibration.EstimatedGain_dB, ...
        'CalibrationPhase_deg',P.Calibration.EstimatedPhase_deg, ...
        'MLStepSchedule_deg',P.DOA.MLStepSchedule_deg, ...
        'EnableGNPolish',P.DOA.EnableGNPolish, ...
        'GNIterations',P.DOA.GNIterations, ...
        'GNMaxStep_deg',P.DOA.GNMaxStep_deg, ...
        'EnableTracking',false);

    azimuthError=zeros(numberTrials,1);
    elevationError=zeros(numberTrials,1);
    angularError=zeros(numberTrials,1);
    for trial=1:numberTrials
        trueAzimuth=uniformRandom(P.Accuracy.AzQualified_deg);
        trueElevation=uniformRandom(P.Accuracy.ElQualified_deg);
        trueVector=anglesToVector(trueAzimuth,trueElevation);
        steering=exp(-1j*2*pi*P.Source.CenterFreqHz/P.c* ...
            (P.Antenna.Positions*trueVector));
        symbols=exp(1j*(pi/2)*randi([0 3],numberSnapshots,1));
        noiseScale=10^(-snr_dB/20)/sqrt(2);
        receiverNoise=noiseScale*(randn(numberSnapshots,4)+ ...
            1j*randn(numberSnapshots,4));
        % The V7 calibration table corrects both static receiver phase and
        % RFDC/channel time skew. Inject that same skew into this controlled
        % baseline so the applied calibration and test signal are consistent.
        timeSkewPhase_deg=-360*P.Source.CenterFreqHz* ...
            (P.Receiver.RelativeTimeSkew_ps*1e-12);
        channelTransfer=10.^(P.Channel.Gain_dB/20).* ...
            exp(1j*deg2rad(P.Channel.PhaseError_deg+timeSkewPhase_deg));
        snapshots=(symbols*steering.'+receiverNoise).*channelTransfer;

        [estimatedAzimuth,estimatedElevation]=estimator(snapshots,0,0,0);
        estimatedVector=anglesToVector(estimatedAzimuth,estimatedElevation);
        azimuthError(trial)=wrap180(estimatedAzimuth-trueAzimuth);
        elevationError(trial)=estimatedElevation-trueElevation;
        angularError(trial)=acosd(max(-1,min(1, ...
            dot(estimatedVector,trueVector))));
    end
    release(estimator);

    azimuthRMSE=sqrt(mean(azimuthError.^2));
    elevationRMSE=sqrt(mean(elevationError.^2));
    rmse3d=sqrt(mean(angularError.^2));
    p95=percentileLocal(angularError,95);
    passes=snr_dB>=P.Accuracy.MinimumInputSNR_dB && ...
        rmse3d<=P.Accuracy.Required3DRMSE_deg;
    metricValues(snrIndex,:)=[snr_dB numberSnapshots numberTrials, ...
        mean(azimuthError),mean(elevationError),azimuthRMSE,elevationRMSE, ...
        rmse3d,p95,double(passes)];
    fprintf(['SNR=%2.0f dB | Az RMSE=%7.4f | El RMSE=%7.4f | ' ...
        '3-D RMSE=%7.4f | P95=%7.4f deg | %s\n'], ...
        snr_dB,azimuthRMSE,elevationRMSE,rmse3d,p95,passText(passes));
end

results=array2table(metricValues,'VariableNames',metricNames);
results.Pass_0p1deg=logical(results.Pass_0p1deg);
writetable(results,'accuracy_results.csv');
save('accuracy_results.mat','results','P','mode');

qualified=results.SNR_dB>=P.Accuracy.MinimumInputSNR_dB;
acceptancePass=all(results.RMSE3D_deg(qualified)<= ...
    P.Accuracy.Required3DRMSE_deg);
fprintf('\nAcceptance over every qualified SNR row: %s\n',passText(acceptancePass));

figure('Name','2x2 DOA accuracy','Color','w');
plot(results.SNR_dB,results.RMSE3D_deg,'o-','LineWidth',1.6); hold on;
yline(P.Accuracy.Required3DRMSE_deg,'r--','0.1 deg requirement');
xline(P.Accuracy.MinimumInputSNR_dB,'k:','qualified SNR');
grid on; xlabel('Per-channel input SNR (dB)');
ylabel('3-D great-circle RMSE (deg)');
title(sprintf('Calibrated 2x2 WPI + local ML, N=%d',numberSnapshots));
exportgraphics(gcf,'accuracy_rmse_vs_snr.png','Resolution',160);
end

function value=uniformRandom(limits)
value=limits(1)+(limits(2)-limits(1))*rand;
end

function vector=anglesToVector(azimuth,elevation)
vector=[cosd(elevation)*cosd(azimuth); ...
        cosd(elevation)*sind(azimuth); sind(elevation)];
end

function angle=wrap180(angle)
angle=mod(angle+180,360)-180;
end

function value=percentileLocal(values,percentage)
values=sort(values(:));
position=1+(numel(values)-1)*percentage/100;
lower=floor(position); upper=ceil(position);
if lower==upper
    value=values(lower);
else
    value=values(lower)+(position-lower)*(values(upper)-values(lower));
end
end

function text=passText(value)
if value, text='PASS'; else, text='FAIL'; end
end
