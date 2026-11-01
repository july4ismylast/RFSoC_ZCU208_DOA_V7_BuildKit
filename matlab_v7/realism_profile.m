function R=realism_profile(name,nominalPositions,centerFreqHz)
%REALISM_PROFILE Reproducible calibrated-LOS and field-stress assumptions.
if nargin<1 || isempty(name), name='CALIBRATED_LOS'; end
if nargin<2, nominalPositions=[0 -.0125 -.0125;0 .0125 -.0125; ...
        0 -.0125 .0125;0 .0125 .0125]; end
if nargin<3, centerFreqHz=4e9; end
name=upper(char(name));

positionError_um=[0 0 0; 0 18 -7; 0 -11 15; 0 9 -13];
calibrationResidual_um=[0 0 0; 0 3 -2; 0 -2 3; 0 2 -2];
R.Name=name;
R.Array.ActualPositions=nominalPositions+positionError_um*1e-6;
R.Array.CalibratedPositions=R.Array.ActualPositions- ...
    calibrationResidual_um*1e-6;

switch name
    case 'IDEAL'
        couplingAmplitude=0;
        couplingResidualFraction=0;
        R.Multipath.RelativeGain_dB=[];
        R.Multipath.DelaySamples=[];
        R.Multipath.AzOffset_deg=[];
        R.Multipath.ElOffset_deg=[];
        R.Multipath.Phase_deg=[];
        R.Receiver.GainDrift_dB=zeros(1,4);
        R.Receiver.PhaseDrift_deg=zeros(1,4);
        R.Receiver.FramePhaseJitter_deg=0;
        R.Receiver.DifferentialPhaseNoiseStep_deg=0;
    case 'FIELD_STRESS'
        couplingAmplitude=10^(-30/20);
        couplingResidualFraction=0.05;
        R.Multipath.RelativeGain_dB=[-28 -35];
        R.Multipath.DelaySamples=[7 19];
        R.Multipath.AzOffset_deg=[18 -27];
        R.Multipath.ElOffset_deg=[-9 13];
        R.Multipath.Phase_deg=[40 -115];
        R.Receiver.GainDrift_dB=[0 .012 -.010 .015];
        R.Receiver.PhaseDrift_deg=[0 .055 -.045 .070];
        R.Receiver.FramePhaseJitter_deg=.020;
        R.Receiver.DifferentialPhaseNoiseStep_deg=.0004;
    otherwise
        R.Name='CALIBRATED_LOS';
        couplingAmplitude=10^(-36/20);
        couplingResidualFraction=0.02;
        R.Multipath.RelativeGain_dB=[-48 -54];
        R.Multipath.DelaySamples=[5 17];
        R.Multipath.AzOffset_deg=[14 -22];
        R.Multipath.ElOffset_deg=[-7 11];
        R.Multipath.Phase_deg=[35 -90];
        R.Receiver.GainDrift_dB=[0 .004 -.003 .005];
        R.Receiver.PhaseDrift_deg=[0 .015 -.012 .018];
        R.Receiver.FramePhaseJitter_deg=.005;
        R.Receiver.DifferentialPhaseNoiseStep_deg=.0001;
end

phasePattern=[0 25 -40 70; -25 0 55 -30; 40 -55 0 20; -70 30 -20 0];
actualCoupling=eye(4)+couplingAmplitude*exp(1j*deg2rad(phasePattern)).*(1-eye(4));
estimatedCoupling=eye(4)+couplingAmplitude*(1-couplingResidualFraction)* ...
    exp(1j*deg2rad(phasePattern+0.2)).*(1-eye(4));
R.Receiver.CouplingMatrix=actualCoupling;
R.Calibration.DecouplingMatrix=inv(estimatedCoupling);
R.Receiver.RelativeTimeSkew_ps=[0 .35 -.28 .20];
timeSkewPhase=-360*centerFreqHz*(R.Receiver.RelativeTimeSkew_ps*1e-12);
R.Calibration.TimeSkewPhase_deg=timeSkewPhase;
end
