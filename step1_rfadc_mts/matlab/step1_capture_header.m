function header=step1_capture_header(fs_hz,fc_hz,channels,samples,bits,scale,flags)
%STEP1_CAPTURE_HEADER The 32-byte capture header, byte for byte, in MATLAB.
%   STEP1_CAPTURE_HEADER() returns a struct with the default ZCU208 values and
%   a .bytes field holding the 32 bytes the PL must write and the PS must read.
%   The layout is the one in step1_rfadc_mts/py/capture_format.py:
%
%     0 char[8] "ZC208C01" | 8 uint32 fs | 12 uint32 fc | 16 uint16 channels
%     18 uint16 bits | 20 uint32 samples | 24 float32 scale | 28 uint32 flags
%
%   Use it to check the C driver: read the first 32 bytes of a capture with
%   fread(fid,32,'uint8=>uint8') and compare against header.bytes.

if nargin<1
    fs_hz=2.0e9;
end
if nargin<2
    fc_hz=4.0e9;
end
if nargin<3
    channels=4;
end
if nargin<4
    samples=4096;
end
if nargin<5
    bits=12;
end
if nargin<6
    scale=2^(bits-1)-1;
end
if nargin<7
    flags=0;
end

header=struct();
header.magic=uint8('ZC208C01');
header.fs_hz=uint32(fs_hz);
header.fc_hz=uint32(fc_hz);
header.channels=uint16(channels);
header.bits=uint16(bits);
header.samples=uint32(samples);
header.scale=single(scale);
header.flags=uint32(flags);

bytes=[header.magic, ...
       typecast(header.fs_hz,'uint8'), ...
       typecast(header.fc_hz,'uint8'), ...
       typecast(header.channels,'uint8'), ...
       typecast(header.bits,'uint8'), ...
       typecast(header.samples,'uint8'), ...
       typecast(header.scale,'uint8'), ...
       typecast(header.flags,'uint8')];

if numel(bytes)~=32
    error('step1: header is %d bytes, must be 32',numel(bytes));
end
header.bytes=bytes;
header.payload_bytes=double(samples)*double(channels)*4;
end
