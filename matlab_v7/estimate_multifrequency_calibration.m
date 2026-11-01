function calibration=estimate_multifrequency_calibration( ...
        toneSnapshots,frequenciesHz,centerFreqHz,referenceChannel)
%ESTIMATE_MULTIFREQUENCY_CALIBRATION Relative RF gain, phase and time skew.
% toneSnapshots is N-by-4-by-F complex IQ measured from a known boresight
% calibration signal. The signal generator phase/amplitude may change between
% frequencies because every channel is divided by the reference channel.
if nargin<4, referenceChannel=1; end
validateattributes(toneSnapshots,{'numeric'}, ...
    {'nonempty','finite'},mfilename,'toneSnapshots');
assert(ndims(toneSnapshots)==3,'toneSnapshots must be N-by-4-by-F.');
assert(size(toneSnapshots,2)==4,'Calibration input must contain four channels.');
frequenciesHz=frequenciesHz(:);
assert(size(toneSnapshots,3)==numel(frequenciesHz), ...
    'The third snapshot dimension must match frequenciesHz.');
assert(referenceChannel>=1 && referenceChannel<=4, ...
    'referenceChannel must be in the interval 1..4.');

numberFrequencies=numel(frequenciesHz);
response=complex(zeros(numberFrequencies,4));
for frequencyIndex=1:numberFrequencies
    response(frequencyIndex,:)=mean(toneSnapshots(:,:,frequencyIndex),1);
end
reference=response(:,referenceChannel);
assert(all(abs(reference)>100*eps),'Reference-channel calibration tone is too small.');
relative=response./reference;

frequencyOrigin=mean(frequenciesHz);
frequencyOffset=frequenciesHz-frequencyOrigin;
gain_dB=zeros(1,4); phase_deg=zeros(1,4); timeSkew_ps=zeros(1,4);
phaseFitResidual_deg=zeros(1,4);
for channel=1:4
    gain_dB(channel)=mean(20*log10(max(abs(relative(:,channel)),eps)));
    unwrappedPhase=unwrap(angle(relative(:,channel)));
    coefficients=polyfit(frequencyOffset,unwrappedPhase,1);
    timeSkew_ps(channel)=-coefficients(1)/(2*pi)*1e12;
    phaseAtCenter=polyval(coefficients,centerFreqHz-frequencyOrigin);
    phase_deg(channel)=wrap180(rad2deg(phaseAtCenter));
    fitted=polyval(coefficients,frequencyOffset);
    phaseFitResidual_deg(channel)=sqrt(mean(rad2deg(unwrappedPhase-fitted).^2));
end

% Remove numerical residue in the selected reference channel.
gain_dB(referenceChannel)=0;
phase_deg(referenceChannel)=0;
timeSkew_ps(referenceChannel)=0;
phaseFitResidual_deg(referenceChannel)=0;
correction=10.^(-gain_dB/20).*exp(-1j*deg2rad(phase_deg));

coefficientReal=int16(round(min(max(real(correction),-2),2-2^-14)*2^14));
coefficientImag=int16(round(min(max(imag(correction),-2),2-2^-14)*2^14));
packed=zeros(1,4,'uint32');
for channel=1:4
    low=uint32(typecast(coefficientReal(channel),'uint16'));
    high=bitshift(uint32(typecast(coefficientImag(channel),'uint16')),16);
    packed(channel)=bitor(low,high);
end

calibration=struct('ReferenceChannel',referenceChannel, ...
    'CenterFreqHz',centerFreqHz,'FrequenciesHz',frequenciesHz, ...
    'RelativeGain_dB',gain_dB,'RelativePhaseAtCenter_deg',phase_deg, ...
    'RelativeTimeSkew_ps',timeSkew_ps, ...
    'PhaseFitResidual_deg',phaseFitResidual_deg, ...
    'ComplexCorrection',correction,'PackedQ2_14',packed);
end

function angle=wrap180(angle)
angle=mod(angle+180,360)-180;
end
