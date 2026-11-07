function result=step3_doa_from_capture(capture_file)
%STEP3_DOA_FROM_CAPTURE The reference estimator, run on a capture or a scene.
%   RESULT=STEP3_DOA_FROM_CAPTURE(FILE) reads a .mat written by
%   step0_antenna/matlab/step0_make_scene.m (field X, 4 x N complex) and runs
%   matlab_v7/estimate_doa_from_covariance_v7.m on it, i.e. exactly the chain
%   that step3_r5_doa/c/doa_core.c implements in C:
%
%       WPI (six baselines, weighted LS)  ->  local ML (36 Bartlett points)
%       ->  Gauss-Newton (2 steps, 0.05 deg cap)
%
%   The point of this file is that the MATLAB reference and the C do not drift:
%   same inputs, same angles, and the fields of P below are the whole parameter
%   set the estimator needs.

if nargin<1
    capture_file=fullfile(fileparts(mfilename('fullpath')),'..','..', ...
                          'step0_antenna','data','scene_matlab.mat');
end
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'..','..','matlab_v7'));

loaded=load(capture_file);
if isfield(loaded,'X')
    data=loaded.X;
elseif isfield(loaded,'x')
    data=loaded.x;
else
    error('step3: %s has no X or x field',capture_file);
end

covariance=data*data'/size(data,2);
report=step0_antenna_model();
P=struct();
P.c=299792458.0;
P.Source=struct('CenterFreqHz',report.fc_hz);
P.DOA=struct();
P.DOA.ArrayPositions=[zeros(4,1), ...
                      [-report.dy_m/2,+report.dy_m/2,-report.dy_m/2,+report.dy_m/2].', ...
                      [-report.dz_m/2,-report.dz_m/2,+report.dz_m/2,+report.dz_m/2].'];
P.DOA.CalibrationDecouplingMatrix=eye(4);
P.DOA.ForwardBackwardAvg=true;
P.DOA.AzScanRange=[-55 55];
P.DOA.ElScanRange=[-45 45];
P.DOA.MLStepSchedule_deg=[0.5 0.1 0.02 0.005];
P.DOA.GNIterations=2;
P.DOA.GNMaxStep_deg=0.05;

[azimuth,elevation]=estimate_doa_from_covariance_v7(covariance,P);

result=struct();
result.az_deg=azimuth;
result.el_deg=elevation;
result.file=capture_file;
result.covariance=covariance;
fprintf('step3: %s -> az %+.3f deg  el %+.3f deg\n',capture_file,azimuth,elevation);
end
