function report=run_zcu48dr_hil(mode,captureFile)
%RUN_ZCU48DR_HIL Separate prepare/compare harness for the real ZCU48DR board.
% PREPARE creates AXI512 stimulus and golden output. COMPARE consumes the
% 16 signed int64 values captured from the board's covariance AXI stream.
if nargin<1, mode='prepare'; end
vectorDirectory=fullfile(pwd,'hil_vectors');
switch lower(char(mode))
    case 'prepare'
        manifest=generate_zcu48dr_hil_vectors(vectorDirectory);
        report=struct('Mode','prepare','Pass',true,'Manifest',manifest);
        fprintf(['Next: replay adc_4ch_4spc_axis512.hex through ' ...
            'doa_covariance_4ch_v4 and save its 16 outputs as capture.csv.\n']);
        return
    case 'loopback'
        if ~exist(fullfile(vectorDirectory,'hil_reference.mat'),'file')
            generate_zcu48dr_hil_vectors(vectorDirectory);
        end
        captureFile=fullfile(vectorDirectory,'golden_covariance_i64.csv');
    case 'compare'
        assert(nargin>=2 && exist(captureFile,'file')==2, ...
            'Provide the board capture CSV for compare mode.');
    otherwise
        error('HIL:Mode','Mode must be prepare, loopback, or compare.');
end

assert(exist(fullfile(vectorDirectory,'hil_reference.mat'),'file')==2, ...
    'Run run_zcu48dr_hil(''prepare'') before comparing a board capture.');
reference=load(fullfile(vectorDirectory,'hil_reference.mat'));
captured=int64(readmatrix(captureFile)); captured=captured(:);
golden=reference.golden(:);
assert(numel(captured)==16,'Board capture must contain exactly 16 int64 values.');
difference=double(captured)-double(golden);
exact=all(difference==0);
relative=max(abs(difference)./max(abs(double(golden)),1));

covariance=covarianceFromValues(captured);
[azimuth,elevation]=estimate_doa_from_covariance_v7(covariance,reference.P);
truth=[cosd(reference.trueEl_deg)*cosd(reference.trueAz_deg); ...
    cosd(reference.trueEl_deg)*sind(reference.trueAz_deg);sind(reference.trueEl_deg)];
estimate=[cosd(elevation)*cosd(azimuth);cosd(elevation)*sind(azimuth);sind(elevation)];
angularError=acosd(max(-1,min(1,dot(truth,estimate))));
report=struct('Mode',char(mode),'ExactIntegerMatch',exact, ...
    'MaximumRelativeCovarianceError',relative,'EstimatedAz_deg',azimuth, ...
    'EstimatedEl_deg',elevation,'AngularError_deg',angularError, ...
    'Pass',exact && angularError<=reference.P.Accuracy.Required3DRMSE_deg);
disp(report);
assert(report.Pass,'HIL comparison failed exact covariance or 0.1-degree DOA.');
end

function covariance=covarianceFromValues(values)
pairs=[1 2;1 3;1 4;2 3;2 4;3 4];
covariance=complex(zeros(4));
for channel=1:4, covariance(channel,channel)=double(values(channel)); end
for pair=1:6
    second=pairs(pair,2); first=pairs(pair,1);
    value=double(values(4+pair))+1j*double(values(10+pair));
    covariance(second,first)=value;
    covariance(first,second)=conj(value);
end
end
