function report=step0_antenna_model(dy_m,dz_m,lever_m,fc_hz)
%STEP0_ANTENNA_MODEL The 2x2 array of V07 section 4, and its numbers.
%   REPORTS=STEP0_ANTENNA_MODEL() uses dy = 25 mm, dz = 30 mm, lever = 150 mm
%   and fc = 4 GHz.  Every field is re-derived here, so the MATLAB side cannot
%   drift away from step0_antenna/py/array_model.py.
%
%   report.positions     4x3 element positions, metres
%   report.f_max_hz      highest un-wrapped frequency of the tightest baseline
%   report.beamwidth_deg first-null width of each baseline aperture
%   report.sigma_deg     sigma(angle) at 4096 snapshots for SNR 0:5:25 dB

if nargin<1, dy_m=0.025; end
if nargin<2, dz_m=0.030; end
if nargin<3, lever_m=0.150; end
if nargin<4, fc_hz=4.0e9; end

c=299792458.0;
report=struct();
report.dy_m=dy_m;
report.dz_m=dz_m;
report.lever_m=lever_m;
report.fc_hz=fc_hz;
report.positions=[lever_m,-dy_m/2,-dz_m/2; ...
                  lever_m,+dy_m/2,-dz_m/2; ...
                  lever_m,-dy_m/2,+dz_m/2; ...
                  lever_m,+dy_m/2,+dz_m/2];
report.lambda_m=c/fc_hz;
report.dy_over_lambda=dy_m/report.lambda_m;
report.dz_over_lambda=dz_m/report.lambda_m;
report.f_max_hz=min(c/(2*dy_m),c/(2*dz_m));
report.beamwidth_deg=[0.886*report.lambda_m/(2*dy_m), ...
                      0.886*report.lambda_m/(2*dz_m)]*180/pi;
snr_db=0:5:25;
report.snr_db=snr_db;
report.sigma_deg=1./sqrt(2*4096*10.^(snr_db/10)).* ...
    report.lambda_m/(2*pi*dy_m)*180/pi;
end
