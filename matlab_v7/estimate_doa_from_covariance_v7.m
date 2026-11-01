function [azimuth,elevation]=estimate_doa_from_covariance_v7(covariance,P)
%ESTIMATE_DOA_FROM_COVARIANCE_V7 PS reference using a captured PL covariance.
covariance=P.DOA.CalibrationDecouplingMatrix*covariance* ...
    P.DOA.CalibrationDecouplingMatrix';
covariance=(covariance+covariance')/2;
if P.DOA.ForwardBackwardAvg
    exchange=fliplr(eye(4));
    covariance=.5*(covariance+exchange*conj(covariance)*exchange);
end
pairs=[1 2;1 3;1 4;2 3;2 4;3 4];
baseline=zeros(6,2); phase=zeros(6,1); weight=zeros(6,1);
for pair=1:6
    first=pairs(pair,1); second=pairs(pair,2);
    difference=P.DOA.ArrayPositions(second,:)-P.DOA.ArrayPositions(first,:);
    baseline(pair,:)=difference(2:3);
    crossValue=covariance(second,first);
    phase(pair)=angle(crossValue);
    coherence=abs(crossValue)^2/max(real(covariance(first,first))* ...
        real(covariance(second,second)),eps);
    coherence=min(.999,max(.001,coherence));
    weight(pair)=min(100,max(.05,coherence/(1-coherence)));
end
waveNumber=2*pi*P.Source.CenterFreqHz/P.c;
directionYZ=-(baseline'*(weight.*baseline)+1e-12*eye(2))\ ...
    (baseline'*(weight.*phase))/waveNumber;
if norm(directionYZ)>.999999, directionYZ=.999999*directionYZ/norm(directionYZ); end
ux=sqrt(max(1-sum(directionYZ.^2),eps));
azimuth=atan2d(directionYZ(1),ux); elevation=asind(directionYZ(2));

for stage=1:numel(P.DOA.MLStepSchedule_deg)
    step=P.DOA.MLStepSchedule_deg(stage); best=-inf;
    for elOffset=-1:1
        for azOffset=-1:1
            candidateAz=max(P.DOA.AzScanRange(1), ...
                min(P.DOA.AzScanRange(2),azimuth+azOffset*step));
            candidateEl=max(P.DOA.ElScanRange(1), ...
                min(P.DOA.ElScanRange(2),elevation+elOffset*step));
            steering=steeringVector(candidateAz,candidateEl,P);
            score=real(steering'*covariance*steering);
            if score>best, best=score; bestAz=candidateAz; bestEl=candidateEl; end
        end
    end
    azimuth=bestAz; elevation=bestEl;
end

signalVector=steeringVector(azimuth,elevation,P);
for iteration=1:4
    signalVector=covariance*signalVector;
    signalVector=signalVector/max(norm(signalVector),eps);
end
projector=eye(4)-signalVector*signalVector';
for iteration=1:P.DOA.GNIterations
    az=deg2rad(azimuth); el=deg2rad(elevation);
    direction=[cos(el)*cos(az);cos(el)*sin(az);sin(el)];
    dAz=[-cos(el)*sin(az);cos(el)*cos(az);0];
    dEl=[-sin(el)*cos(az);-sin(el)*sin(az);cos(el)];
    steering=exp(-1j*waveNumber*(P.DOA.ArrayPositions*direction));
    derivative=[-1j*waveNumber*(P.DOA.ArrayPositions*dAz).*steering, ...
        -1j*waveNumber*(P.DOA.ArrayPositions*dEl).*steering];
    gradient=2*real(derivative'*(projector*steering));
    hessian=2*real(derivative'*projector*derivative)+1e-7*eye(2);
    delta=rad2deg(hessian\gradient);
    if norm(delta)>P.DOA.GNMaxStep_deg
        delta=delta*P.DOA.GNMaxStep_deg/norm(delta);
    end
    azimuth=max(P.DOA.AzScanRange(1), ...
        min(P.DOA.AzScanRange(2),azimuth-delta(1)));
    elevation=max(P.DOA.ElScanRange(1), ...
        min(P.DOA.ElScanRange(2),elevation-delta(2)));
end
end

function steering=steeringVector(azimuth,elevation,P)
direction=[cosd(elevation)*cosd(azimuth); ...
    cosd(elevation)*sind(azimuth);sind(elevation)];
steering=exp(-1j*2*pi*P.Source.CenterFreqHz/P.c* ...
    (P.DOA.ArrayPositions*direction));
end
