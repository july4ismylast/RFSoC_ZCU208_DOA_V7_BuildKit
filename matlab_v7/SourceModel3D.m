classdef SourceModel3D < matlab.System
    % Coherent four-channel RF source and propagation model.
    properties (Nontunable)
        SourcePosition = [500 300 200]
        CenterFreqHz = 4e9
        BandwidthHz = 30e6
        ModulationType = 'QAM16'
        PowerdBm = 20
        ChipRateHz = 20e6
        SweepStartHz = -15e6
        SweepStopHz = 15e6
        SweepTimeSeconds = 4e-6
        ModulationToneHz = 2e6
        PMIndexRad = 2.5
        AMDepth = 0.8
        FMDeviationHz = 10e6
        FSKDeviationHz = 7.5e6
        NLFMShape = 2.0
        PulseWidthSeconds = 1e-6
        PRFHz = 250e3
        Fs = 2.048e9
        FrameLength = 8192
        % Nose-mounted square 2x2 array in the Y-Z plane; boresight is +X.
        AntennaPositions = [0 -0.0125 -0.0125; 0 0.0125 -0.0125; ...
                            0 -0.0125  0.0125; 0 0.0125  0.0125]
        ChannelGain_dB = [0 0.3 -0.2 0.15]
        ChannelPhaseError_deg = [0 1.0 -0.7 0.5]
        NoiseFiguredB = 3.0
        PathLossExponent = 2.0
        AddReceiverNoise = true
        MultipathRelativeGain_dB = []
        MultipathDelaySamples = []
        MultipathAzOffset_deg = []
        MultipathElOffset_deg = []
        MultipathPhase_deg = []
        c = 299792458
    end

    methods
        function obj=SourceModel3D(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end

    methods (Access=protected)
        function X4=stepImpl(obj,platformPosition,platformYaw,platformPitch,platformRoll)
            N=obj.FrameLength;
            platformPosition=reshape(platformPosition,1,3);
            sourcePosition=reshape(obj.SourcePosition,1,3);
            delta=sourcePosition-platformPosition;
            range=max(norm(delta),1);
            worldDirection=delta(:)/range;
            bodyDirection=body_to_navigation_dcm( ...
                platformYaw,platformPitch,platformRoll).'*worldDirection;
            az=atan2d(bodyDirection(2),bodyDirection(1));
            el=atan2d(bodyDirection(3),hypot(bodyDirection(1),bodyDirection(2)));

            lambda=obj.c/obj.CenterFreqHz;
            fspl1m=20*log10(4*pi/lambda);
            pathLoss_dB=fspl1m+10*obj.PathLossExponent*log10(range);
            receivedPower_W=10^((obj.PowerdBm-pathLoss_dB-30)/10);
            signal=obj.generateSignal(N)*sqrt(max(receivedPower_W,0));

            azr=deg2rad(az); elr=deg2rad(el);
            ux=cos(elr)*cos(azr); uy=cos(elr)*sin(azr); uz=sin(elr);
            X4=complex(zeros(N,4));
            for channel=1:4
                tau=(obj.AntennaPositions(channel,1)*ux+ ...
                    obj.AntennaPositions(channel,2)*uy+ ...
                    obj.AntennaPositions(channel,3)*uz)/obj.c;
                X4(:,channel)=signal*exp(-1j*2*pi*obj.CenterFreqHz*tau);
            end

            numberPaths=min([numel(obj.MultipathRelativeGain_dB), ...
                numel(obj.MultipathDelaySamples),numel(obj.MultipathAzOffset_deg), ...
                numel(obj.MultipathElOffset_deg),numel(obj.MultipathPhase_deg)]);
            for pathIndex=1:numberPaths
                delay=max(0,min(N-1,round(obj.MultipathDelaySamples(pathIndex))));
                delayed=[complex(zeros(delay,1)); signal(1:N-delay)];
                pathAz=az+obj.MultipathAzOffset_deg(pathIndex);
                pathEl=max(-89,min(89,el+obj.MultipathElOffset_deg(pathIndex)));
                pathDirection=[cosd(pathEl)*cosd(pathAz); ...
                    cosd(pathEl)*sind(pathAz); sind(pathEl)];
                pathScale=10^(obj.MultipathRelativeGain_dB(pathIndex)/20)* ...
                    exp(1j*deg2rad(obj.MultipathPhase_deg(pathIndex)));
                for channel=1:4
                    tau=obj.AntennaPositions(channel,:)*pathDirection/obj.c;
                    X4(:,channel)=X4(:,channel)+pathScale*delayed* ...
                        exp(-1j*2*pi*obj.CenterFreqHz*tau);
                end
            end

            if obj.AddReceiverNoise
                kB=1.380649e-23;
                noisePower=kB*290*obj.Fs*10^(obj.NoiseFiguredB/10);
                X4=X4+sqrt(noisePower/2)*(randn(N,4)+1j*randn(N,4));
                for channel=1:4
                    gain=10^(obj.ChannelGain_dB(channel)/20);
                    phase=exp(1j*deg2rad(obj.ChannelPhaseError_deg(channel)));
                    X4(:,channel)=X4(:,channel)*gain*phase;
                end
            end
        end

        function sizeOut=getOutputSizeImpl(obj), sizeOut=[obj.FrameLength 4]; end
        function typeOut=getOutputDataTypeImpl(~), typeOut='double'; end
        function value=isOutputComplexImpl(~), value=true; end
        function value=isOutputFixedSizeImpl(~), value=true; end
        function [a,b,c,d]=getInputNamesImpl(~)
            a='PlatformPosition'; b='PlatformYaw'; c='PlatformPitch'; d='PlatformRoll';
        end
        function name=getOutputNamesImpl(~), name='X4'; end
        function icon=getIconImpl(obj)
            icon=sprintf('Source 3D\n%s %.1f GHz',obj.ModulationType,obj.CenterFreqHz/1e9);
        end
    end

    methods (Access=private)
        function signal=generateSignal(obj,N)
            frequency=((0:N-1).'-floor(N/2))*(obj.Fs/N);
            time=(0:N-1).'/obj.Fs;
            modulation=upper(char(obj.ModulationType));
            switch modulation
                case 'CW'
                    signal=ones(N,1);
                case {'BPSK','QPSK','8PSK','QAM16','QAM64'}
                    symbolCount=max(1,ceil(N*obj.ChipRateHz/obj.Fs));
                    repeatCount=ceil(N/symbolCount);
                    switch modulation
                        case 'BPSK'
                            symbols=2*randi([0 1],symbolCount,1)-1;
                        case 'QPSK'
                            symbols=((2*randi([0 1],symbolCount,1)-1)+ ...
                                1j*(2*randi([0 1],symbolCount,1)-1))/sqrt(2);
                        case '8PSK'
                            symbols=exp(1j*(pi/4)*randi([0 7],symbolCount,1));
                        case 'QAM16'
                            constellation=(-3:2:3).'+1j*(-3:2:3);
                            constellation=constellation(:)/sqrt(10);
                            symbols=constellation(randi(16,symbolCount,1));
                        otherwise
                            constellation=(-7:2:7).'+1j*(-7:2:7);
                            constellation=constellation(:)/sqrt(42);
                            symbols=constellation(randi(64,symbolCount,1));
                    end
                    signal=repelem(symbols,repeatCount);
                    signal=signal(1:N);
                case {'LFM','CHIRP'}
                    sweepTime=max(obj.SweepTimeSeconds,1/obj.Fs);
                    sweepTimeLocal=mod(time,sweepTime);
                    chirpSlope=(obj.SweepStopHz-obj.SweepStartHz)/sweepTime;
                    instantaneousFrequency=obj.SweepStartHz+ ...
                        chirpSlope*sweepTimeLocal;
                    phase=2*pi*cumsum(instantaneousFrequency)/obj.Fs;
                    signal=exp(1j*phase);
                case 'NLFM'
                    sweepTime=max(obj.SweepTimeSeconds,1/obj.Fs);
                    sweepTimeLocal=mod(time,sweepTime);
                    normalizedTime=2*sweepTimeLocal/sweepTime-1;
                    shape=max(0,obj.NLFMShape);
                    sweepCenter=(obj.SweepStartHz+obj.SweepStopHz)/2;
                    sweepHalfSpan=(obj.SweepStopHz-obj.SweepStartHz)/2;
                    instantaneousFrequency=sweepCenter+sweepHalfSpan* ...
                        (normalizedTime+shape*normalizedTime.^3)/(1+shape);
                    phase=2*pi*cumsum(instantaneousFrequency)/obj.Fs;
                    signal=exp(1j*phase);
                case 'PM'
                    phase=obj.PMIndexRad*sin(2*pi*obj.ModulationToneHz*time);
                    signal=exp(1j*phase);
                case 'FM'
                    modulationIndex=obj.FMDeviationHz/max(obj.ModulationToneHz,eps);
                    phase=modulationIndex*sin(2*pi*obj.ModulationToneHz*time);
                    signal=exp(1j*phase);
                case 'AM'
                    depth=max(0,min(1,obj.AMDepth));
                    signal=1+depth*cos(2*pi*obj.ModulationToneHz*time);
                case 'FSK'
                    symbolCount=max(1,ceil(N*obj.ChipRateHz/obj.Fs));
                    repeatCount=ceil(N/symbolCount);
                    symbols=2*randi([0 1],symbolCount,1)-1;
                    instantaneousFrequency=repelem(symbols,repeatCount);
                    instantaneousFrequency=instantaneousFrequency(1:N)*obj.FSKDeviationHz;
                    phase=2*pi*cumsum(instantaneousFrequency)/obj.Fs;
                    signal=exp(1j*phase);
                case {'PULSED_LFM','LFM_PULSE'}
                    pulsePeriod=1/max(obj.PRFHz,eps);
                    pulseWidth=min(max(obj.PulseWidthSeconds,1/obj.Fs),pulsePeriod);
                    pulseTime=mod(time,pulsePeriod);
                    active=pulseTime<pulseWidth;
                    chirpSlope=(obj.SweepStopHz-obj.SweepStartHz)/pulseWidth;
                    phase=2*pi*(obj.SweepStartHz*pulseTime+ ...
                        0.5*chirpSlope*pulseTime.^2);
                    signal=double(active).*exp(1j*phase);
                case {'NOISE','WIDEBAND_NOISE'}
                    spectrum=complex(zeros(N,1));
                    active=abs(frequency)<=obj.BandwidthHz/2;
                    activeCount=sum(active);
                    spectrum(active)=(randn(activeCount,1)+1j*randn(activeCount,1))/sqrt(2);
                    signal=ifft(ifftshift(spectrum))*sqrt(N);
                otherwise
                    error('DOA3D:ModulationType', ...
                        ['Unsupported ModulationType "%s". Use CW, BPSK, QPSK, ' ...
                        '8PSK, QAM16, QAM64, LFM, NLFM, PM, FM, AM, FSK, ' ...
                        'PULSED_LFM, or WIDEBAND_NOISE.'],obj.ModulationType);
            end

            shaped=fftshift(fft(signal));
            shaped(abs(frequency)>obj.BandwidthHz/2)=0;
            signal=ifft(ifftshift(shaped));
            powerValue=mean(abs(signal).^2);
            if powerValue>0, signal=signal/sqrt(powerValue); end
        end
    end
end
