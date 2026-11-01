function results=run_realistic_accuracy_campaign(mode)
%RUN_REALISTIC_ACCURACY_CAMPAIGN Calibrated array/RF/ADC Monte Carlo audit.
if nargin<1, mode='acceptance'; end
run('sim3d_params.m');
if strcmpi(mode,'quick'), numberTrials=100; else, numberTrials=1000; end
snrValues=[15 20 25];
rng(P.Sim.RandomSeed+21,'twister');
values=zeros(numel(snrValues),7);
fprintf('\n=== V7 REALISTIC 2x2 DOA CAMPAIGN: %s ===\n',P.Realism.Profile);
for snrIndex=1:numel(snrValues)
    estimator=DOAEstimator4Ch( ...
        'Algorithm',P.DOA.Algorithm,'CenterFreqHz',P.Source.CenterFreqHz, ...
        'ArrayPositions',P.DOA.ArrayPositions, ...
        'AzScanRange',P.DOA.AzScanRange,'ElScanRange',P.DOA.ElScanRange, ...
        'CalibrationGain_dB',P.DOA.CalibrationGain_dB, ...
        'CalibrationPhase_deg',P.DOA.CalibrationPhase_deg, ...
        'CalibrationDecouplingMatrix',P.DOA.CalibrationDecouplingMatrix, ...
        'MLStepSchedule_deg',P.DOA.MLStepSchedule_deg, ...
        'EnableGNPolish',P.DOA.EnableGNPolish, ...
        'GNIterations',P.DOA.GNIterations,'GNMaxStep_deg',P.DOA.GNMaxStep_deg, ...
        'EnableTracking',false);
    azError=zeros(numberTrials,1); elError=azError; angularError=azError;
    for trial=1:numberTrials
        trueAz=P.Accuracy.AzQualified_deg(1)+diff(P.Accuracy.AzQualified_deg)*rand;
        trueEl=P.Accuracy.ElQualified_deg(1)+diff(P.Accuracy.ElQualified_deg)*rand;
        truth=[cosd(trueEl)*cosd(trueAz);cosd(trueEl)*sind(trueAz);sind(trueEl)];
        snapshots=simulate_realistic_snapshots( ...
            P,trueAz,trueEl,snrValues(snrIndex),P.DOA.NumSnapshots);
        [estimatedAz,estimatedEl]=estimator(snapshots,0,0,0);
        estimate=[cosd(estimatedEl)*cosd(estimatedAz); ...
            cosd(estimatedEl)*sind(estimatedAz);sind(estimatedEl)];
        azError(trial)=wrap180(estimatedAz-trueAz);
        elError(trial)=estimatedEl-trueEl;
        angularError(trial)=acosd(max(-1,min(1,dot(estimate,truth))));
    end
    release(estimator);
    rmse3d=sqrt(mean(angularError.^2));
    p95=percentileLocal(angularError,95);
    values(snrIndex,:)=[snrValues(snrIndex) numberTrials ...
        sqrt(mean(azError.^2)) sqrt(mean(elError.^2)) rmse3d p95 ...
        double(rmse3d<=P.Accuracy.Required3DRMSE_deg)];
    fprintf('SNR=%2d dB | Az %.4f | El %.4f | 3-D %.4f | P95 %.4f | %s\n', ...
        snrValues(snrIndex),values(snrIndex,3:6),passText(logical(values(snrIndex,7))));
end
results=array2table(values,'VariableNames',{'SNR_dB','Trials','AzRMSE_deg', ...
    'ElRMSE_deg','RMSE3D_deg','P95_3D_deg','Pass_0p1deg'});
results.Pass_0p1deg=logical(results.Pass_0p1deg);
writetable(results,'realistic_accuracy_results.csv');
save('realistic_accuracy_results.mat','results','P','mode');
acceptancePass=all(results.Pass_0p1deg);
fprintf('\nRealistic qualified-SNR acceptance: %s\n',passText(acceptancePass));
if strcmpi(mode,'acceptance') && ~acceptancePass
    warning('DOA2x2:RealisticAcceptance', ...
        'One or more calibrated-LOS SNR rows exceeded 0.1-degree RMSE.');
end
end

function angle=wrap180(angle), angle=mod(angle+180,360)-180; end
function value=percentileLocal(values,percentage)
values=sort(values(:)); position=1+(numel(values)-1)*percentage/100;
lower=floor(position); upper=ceil(position);
if lower==upper, value=values(lower); else
    value=values(lower)+(position-lower)*(values(upper)-values(lower));
end
end
function text=passText(value)
if value, text='PASS'; else, text='FAIL'; end
end
