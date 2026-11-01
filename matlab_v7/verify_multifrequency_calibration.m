function verify_multifrequency_calibration()
%VERIFY_MULTIFREQUENCY_CALIBRATION Deterministic calibration-tone regression.
run('sim3d_params.m'); rng(P.Sim.RandomSeed+91,'twister');
frequenciesHz=P.Source.CenterFreqHz+[-40 -20 0 20 40]*1e6;
numberSamples=8192;
actualGain_dB=P.Channel.Gain_dB-P.Channel.Gain_dB(1);
actualPhase_deg=P.Channel.PhaseError_deg-P.Channel.PhaseError_deg(1);
actualSkew_ps=P.Receiver.RelativeTimeSkew_ps- ...
    P.Receiver.RelativeTimeSkew_ps(1);
tone=complex(zeros(numberSamples,4,numel(frequenciesHz)));
for frequencyIndex=1:numel(frequenciesHz)
    commonPhase=2*pi*rand;
    transfer=10.^(actualGain_dB/20).*exp(1j*deg2rad( ...
        actualPhase_deg-360*frequenciesHz(frequencyIndex)*actualSkew_ps*1e-12));
    ideal=exp(1j*commonPhase)*ones(numberSamples,1)*transfer;
    noise=10^(-80/20)/sqrt(2)*(randn(numberSamples,4)+ ...
        1j*randn(numberSamples,4));
    tone(:,:,frequencyIndex)=ideal+noise;
end
calibration=estimate_multifrequency_calibration( ...
    tone,frequenciesHz,P.Source.CenterFreqHz,1);
expectedPhase=wrap180(actualPhase_deg- ...
    360*P.Source.CenterFreqHz*actualSkew_ps*1e-12);
gainError=max(abs(calibration.RelativeGain_dB-actualGain_dB));
phaseError=max(abs(wrap180( ...
    calibration.RelativePhaseAtCenter_deg-expectedPhase)));
skewError=max(abs(calibration.RelativeTimeSkew_ps-actualSkew_ps));
assert(gainError<1e-3 && phaseError<1e-3 && skewError<.01, ...
    'Multi-frequency calibration regression exceeded its tolerance.');
fprintf(['PASS: multi-frequency calibration; max gain %.6f dB, phase %.6f deg, ' ...
    'skew %.6f ps error.\n'],gainError,phaseError,skewError);
end

function angle=wrap180(angle)
angle=mod(angle+180,360)-180;
end
