function manifest=generate_zcu48dr_hil_vectors(outputDirectory)
%GENERATE_ZCU48DR_HIL_VECTORS Write 512-bit AXI stimuli and golden covariance.
if nargin<1, outputDirectory=fullfile(pwd,'hil_vectors'); end
if ~exist(outputDirectory,'dir'), mkdir(outputDirectory); end
run('sim3d_params.m'); rng(P.Sim.RandomSeed+77,'twister');
trueAz_deg=27.35; trueEl_deg=-13.20;
snapshots=simulate_realistic_snapshots( ...
    P,trueAz_deg,trueEl_deg,25,P.DOA.NumSnapshots);
adcScale=2^(P.Receiver.ADCBits-1);
adcReal=int16(round(min(max(real(snapshots),-1),1-1/adcScale)*adcScale));
adcImag=int16(round(min(max(imag(snapshots),-1),1-1/adcScale)*adcScale));
iqInteger=complex(double(adcReal),double(adcImag));

correction=10.^(-P.DOA.CalibrationGain_dB/20).* ...
    exp(-1j*deg2rad(P.DOA.CalibrationPhase_deg));
coefficientReal=int16(round(min(max(real(correction),-2),2-2^-14)*2^14));
coefficientImag=int16(round(min(max(imag(correction),-2),2-2^-14)*2^14));
calibrationQ2_14=zeros(1,4,'uint32');
for channel=1:4
    low=uint32(typecast(coefficientReal(channel),'uint16'));
    high=bitshift(uint32(typecast(coefficientImag(channel),'uint16')),16);
    calibrationQ2_14(channel)=bitor(low,high);
end

stimulusPath=fullfile(outputDirectory,'adc_4ch_4spc_axis512.hex');
file=fopen(stimulusPath,'w'); assert(file>=0,'Cannot create HIL stimulus file.');
cleanup=onCleanup(@()fclose(file));
for firstSample=1:4:size(iqInteger,1)
    words=zeros(1,16,'uint32'); wordIndex=0;
    for lane=0:3
        for channel=1:4
            wordIndex=wordIndex+1; sampleIndex=firstSample+lane;
            if sampleIndex<=size(iqInteger,1)
                low=uint32(typecast(int16(real(iqInteger(sampleIndex,channel))),'uint16'));
                high=bitshift(uint32(typecast(int16(imag(iqInteger(sampleIndex,channel))),'uint16')),16);
                words(wordIndex)=bitor(low,high);
            end
        end
    end
    text='';
    for index=16:-1:1, text=[text dec2hex(words(index),8)]; end %#ok<AGROW>
    fprintf(file,'%s\n',text);
end
clear cleanup

golden=hil_fixed_covariance_reference(iqInteger,calibrationQ2_14);
writematrix(golden,fullfile(outputDirectory,'golden_covariance_i64.csv'));
writematrix([adcReal adcImag],fullfile(outputDirectory,'adc_iq_int16.csv'));
manifest=struct('format_version',1,'samples_per_beat',4, ...
    'frame_samples',size(iqInteger,1),'true_az_deg',trueAz_deg, ...
    'true_el_deg',trueEl_deg,'adc_bits',P.Receiver.ADCBits, ...
    'calibration_q2_14',double(calibrationQ2_14), ...
    'stimulus_file','adc_4ch_4spc_axis512.hex', ...
    'golden_file','golden_covariance_i64.csv');
jsonFile=fopen(fullfile(outputDirectory,'hil_manifest.json'),'w');
assert(jsonFile>=0,'Cannot create HIL manifest.');
fprintf(jsonFile,'%s',jsonencode(manifest,'PrettyPrint',true)); fclose(jsonFile);
save(fullfile(outputDirectory,'hil_reference.mat'),'P','manifest','golden', ...
    'calibrationQ2_14','trueAz_deg','trueEl_deg');
fprintf('Created ZU48DR HIL vectors in %s\n',outputDirectory);
end
