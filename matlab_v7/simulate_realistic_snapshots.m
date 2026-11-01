function snapshots=simulate_realistic_snapshots(P,azimuth,elevation,snr_dB,numberSnapshots)
%SIMULATE_REALISTIC_SNAPSHOTS Controlled-SNR RF/array/ADC Monte Carlo frame.
truth=[cosd(elevation)*cosd(azimuth); ...
    cosd(elevation)*sind(azimuth); sind(elevation)];
waveNumber=2*pi*P.Source.CenterFreqHz/P.c;
steering=exp(-1j*waveNumber*(P.Antenna.ActualPositions*truth));
symbols=exp(1j*(pi/2)*randi([0 3],numberSnapshots,1));
ideal=symbols*steering.';

numberPaths=min([numel(P.Multipath.RelativeGain_dB), ...
    numel(P.Multipath.DelaySamples),numel(P.Multipath.AzOffset_deg), ...
    numel(P.Multipath.ElOffset_deg),numel(P.Multipath.Phase_deg)]);
for pathIndex=1:numberPaths
    delay=max(0,min(numberSnapshots-1,round(P.Multipath.DelaySamples(pathIndex))));
    delayed=[complex(zeros(delay,1)); symbols(1:numberSnapshots-delay)];
    pathAz=azimuth+P.Multipath.AzOffset_deg(pathIndex);
    pathEl=elevation+P.Multipath.ElOffset_deg(pathIndex);
    pathDirection=[cosd(pathEl)*cosd(pathAz); ...
        cosd(pathEl)*sind(pathAz); sind(pathEl)];
    pathSteering=exp(-1j*waveNumber*(P.Antenna.ActualPositions*pathDirection));
    pathScale=10^(P.Multipath.RelativeGain_dB(pathIndex)/20)* ...
        exp(1j*deg2rad(P.Multipath.Phase_deg(pathIndex)));
    ideal=ideal+pathScale*delayed*pathSteering.';
end

coupled=ideal*P.Receiver.CouplingMatrix.';
timeSkewPhase=-360*P.Source.CenterFreqHz* ...
    (P.Receiver.RelativeTimeSkew_ps*1e-12);
frameJitter=P.Receiver.FramePhaseJitter_deg*randn(1,4);
gain=P.Receiver.ChannelGain_dB+P.Receiver.GainDrift_dB;
phase=P.Receiver.ChannelPhase_deg+P.Receiver.PhaseDrift_deg+ ...
    timeSkewPhase+frameJitter;
transfer=10.^(gain/20).*exp(1j*deg2rad(phase));
snapshots=coupled.*transfer;

signalRMS=sqrt(mean(abs(snapshots(:)).^2));
noiseRMS=signalRMS*10^(-snr_dB/20);
snapshots=snapshots+noiseRMS/sqrt(2)*( ...
    randn(numberSnapshots,4)+1j*randn(numberSnapshots,4));
commonPhase=cumsum(P.Receiver.CommonPhaseNoiseStep_deg* ...
    randn(numberSnapshots,1));
differentialPhase=cumsum(P.Receiver.DifferentialPhaseNoiseStep_deg* ...
    randn(numberSnapshots,4),1);
snapshots=snapshots.*exp(1j*deg2rad(commonPhase+differentialPhase));

if P.Receiver.EnableAGC
    measuredRMS=sqrt(mean(abs(snapshots(:)).^2));
    requestedGain=P.Receiver.AGCTargetRMS/max(measuredRMS,eps);
    maximumGain=10^(P.Receiver.AGCMaximumGain_dB/20);
    snapshots=snapshots*min(requestedGain,maximumGain);
end
snapshots=snapshots+reshape(P.Receiver.DCOffset,1,4);
if P.Receiver.EnableADCQuantization
    scale=2^(P.Receiver.ADCBits-1);
    normalized=snapshots/P.Receiver.ADCFullScale;
    realPart=min(max(real(normalized),-1),1-1/scale);
    imagPart=min(max(imag(normalized),-1),1-1/scale);
    snapshots=P.Receiver.ADCFullScale*(round(realPart*scale)/scale+ ...
        1j*round(imagPart*scale)/scale);
end
end
