function values=hil_fixed_covariance_reference(iqInteger,calibrationQ2_14)
%HIL_FIXED_COVARIANCE_REFERENCE Bit-accurate model of covariance HLS output.
assert(size(iqInteger,2)==4,'iqInteger must be N-by-4 complex integer data.');
assert(numel(calibrationQ2_14)==4,'Four packed complex calibration values required.');
numberSamples=size(iqInteger,1);
calibratedReal=zeros(numberSamples,4);
calibratedImag=zeros(numberSamples,4);
for channel=1:4
    packed=uint32(calibrationQ2_14(channel));
    coefficientReal=double(typecast(uint16(bitand(packed,65535)),'int16'));
    coefficientImag=double(typecast(uint16(bitshift(packed,-16)),'int16'));
    inputReal=double(real(iqInteger(:,channel)));
    inputImag=double(imag(iqInteger(:,channel)));
    calibratedReal(:,channel)=floor((inputReal*coefficientReal- ...
        inputImag*coefficientImag)/2^14);
    calibratedImag(:,channel)=floor((inputReal*coefficientImag+ ...
        inputImag*coefficientReal)/2^14);
end

pairs=[1 2;1 3;1 4;2 3;2 4;3 4];
power=zeros(4,1); crossReal=zeros(6,1); crossImag=zeros(6,1);
for channel=1:4
    power(channel)=sum(calibratedReal(:,channel).^2+ ...
        calibratedImag(:,channel).^2);
end
for pair=1:6
    first=pairs(pair,1); second=pairs(pair,2);
    crossReal(pair)=sum(calibratedReal(:,second).*calibratedReal(:,first)+ ...
        calibratedImag(:,second).*calibratedImag(:,first));
    crossImag(pair)=sum(calibratedImag(:,second).*calibratedReal(:,first)- ...
        calibratedReal(:,second).*calibratedImag(:,first));
end
values=int64([power;crossReal;crossImag]);
end
