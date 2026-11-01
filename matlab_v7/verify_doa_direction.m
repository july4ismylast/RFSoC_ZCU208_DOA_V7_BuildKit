function verify_doa_direction()
%VERIFY_DOA_DIRECTION Confirm that the array covariance does not mirror DOA.
run('sim3d_params.m');
rng(41,'twister');
estimator=DOAEstimator4Ch( ...
    'Algorithm','MUSIC','CenterFreqHz',P.Source.CenterFreqHz, ...
    'ArrayPositions',P.Antenna.Positions,'NumSignals',1, ...
    'AzScanRange',P.DOA.AzScanRange,'ElScanRange',P.DOA.ElScanRange, ...
    'ScanResolution',1,'ForwardBackwardAvg',true,'EnableTracking',false);
truthCases=[32 18; -27 -22];
numberSnapshots=2048;
positions=P.Antenna.Positions;
for caseIndex=1:size(truthCases,1)
    trueAzimuth=truthCases(caseIndex,1);
    trueElevation=truthCases(caseIndex,2);
    ux=cosd(trueElevation)*cosd(trueAzimuth);
    uy=cosd(trueElevation)*sind(trueAzimuth);
    uz=sind(trueElevation);
    delay=(positions(:,1)*ux+positions(:,2)*uy+positions(:,3)*uz)/P.c;
    steering=exp(-1j*2*pi*P.Source.CenterFreqHz*delay);
    symbols=(randn(numberSnapshots,1)+1j*randn(numberSnapshots,1))/sqrt(2);
    noise=0.01*(randn(numberSnapshots,4)+1j*randn(numberSnapshots,4))/sqrt(2);
    snapshots=symbols*steering.'+noise;
    [estimatedAzimuth,estimatedElevation]=estimator(snapshots,0,0,0);
    azimuthError=mod(estimatedAzimuth-trueAzimuth+180,360)-180;
    elevationError=estimatedElevation-trueElevation;
    assert(abs(azimuthError)<=1 && abs(elevationError)<=1, ...
        'DOA sign check failed: truth=[%.1f %.1f], estimate=[%.1f %.1f].', ...
        trueAzimuth,trueElevation,estimatedAzimuth,estimatedElevation);
    fprintf('PASS: DOA direction sign. Truth=[%.1f %.1f], estimate=[%.1f %.1f] deg.\n', ...
        trueAzimuth,trueElevation,estimatedAzimuth,estimatedElevation);
end
release(estimator);
end
