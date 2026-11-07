function scene=step0_make_scene(out_dir,name,snr_db,az_deg,el_deg,bw_hz)
%STEP0_MAKE_SCENE Write one 4-channel scene with MATLAB, same contract as python.
%   SCENE=STEP0_MAKE_SCENE(OUT_DIR) writes OUT_DIR/scene_matlab.mat and prints
%   what it wrote.  The .mat holds X (4 x 4096 complex, fs = 2 GS/s), the truth
%   in DEGREES and HZ, and the array report -- identical in meaning to the .npz
%   that step0_antenna/py/make_scenes.py writes, so the two can be compared.
%
%   The point of this file: everything downstream (step2 vectors, step3
%   estimator, step4 AMC labels) can be fed from either language.

if nargin<1
    out_dir=fullfile(fileparts(mfilename('fullpath')),'..','data');
end
if nargin<2
    name='scene_matlab';
end
if nargin<3
    snr_db=20.0;
end
if nargin<4
    az_deg=12.5;
end
if nargin<5
    el_deg=-7.25;
end
if nargin<6
    bw_hz=100e6;
end

report=step0_antenna_model();
fs_hz=2.0e9;
samples=4096;
c=299792458.0;

% fft-ordered bins, exactly like numpy.fft.fftfreq
index=0:(samples-1);
signed=index;
signed(signed>samples/2)=signed(signed>samples/2)-samples;
bins=signed*fs_hz/samples;
occupied=abs(bins)<=bw_hz/2;
count=nnz(occupied);

direction=[cosd(el_deg)*cosd(az_deg),cosd(el_deg)*sind(az_deg),sind(el_deg)];
projection=report.positions*direction.';
frequency=report.fc_hz+bins(occupied);
steering=exp(-1i*2*pi*frequency.'*projection.'/c);

payload=(randn(count,1)+1i*randn(count,1))/sqrt(2)/sqrt(count);
spectra=zeros(4,samples);
spectra(:,occupied)=steering.'*payload;

in_band=mean(reshape(abs(spectra(:,occupied)).^2,1,[]));
noise_amplitude=sqrt(in_band/10^(snr_db/10)/2);
spectra=spectra+noise_amplitude*(randn(4,samples)+1i*randn(4,samples));

if ~exist(out_dir,'dir')
    mkdir(out_dir);
end
X=ifft(spectra,[],2);
truth=struct('az_deg',az_deg,'el_deg',el_deg,'snr_db',snr_db, ...
             'bandwidth_hz',bw_hz,'fc_hz',report.fc_hz,'fs_hz',fs_hz, ...
             'samples',samples,'occupied_bins',count);
target=fullfile(out_dir,[name '.mat']);
save(target,'X','truth','report');
info=dir(target);
fprintf('step0: wrote %s  (%d occupied bins, %.1f kB)\n', ...
        target,count,info.bytes/1024);
scene=struct('path',target,'truth',truth);
end
