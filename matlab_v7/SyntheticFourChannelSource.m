classdef SyntheticFourChannelSource < matlab.System
    % Multi-target wideband source for the standalone search-stage test.
    properties (Nontunable)
        Fs = 2.048e9
        FrameLength = 8192
        SearchCenterHz = 4e9
        dx = 0.025
        dy = 0.025
        NumTargets = 2
        TargetOffsetHz = [250e6 250e6]
        TargetBandwidthHz = [30e6 30e6]
        TargetSNRdB = [5 0]
        TargetAzDeg = [15 16.5]
        TargetElDeg = [8 8]
        NumInterferers = 2
        InterfererOffsetHz = [-620e6 560e6]
        InterfererBandwidthHz = [20e6 80e6]
        InterfererSNRdB = [12 15]
        InterfererAzDeg = [-35 50]
        InterfererElDeg = [5 0]
        ChannelGain_dB = [0 0.3 -0.2 0.15]
        ChannelPhaseError_deg = [0 1.0 -0.7 0.5]
    end
    methods
        function obj=SyntheticFourChannelSource(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function output=stepImpl(obj)
            N=obj.FrameLength; c=299792458;
            frequency=((0:N-1).'-floor(N/2))*(obj.Fs/N);
            output=complex(zeros(N,4));
            positions=[0 0; obj.dx 0; 0 obj.dy; obj.dx obj.dy];
            for index=1:obj.NumTargets
                signal=obj.makeBand(frequency,obj.TargetOffsetHz(index), ...
                    obj.TargetBandwidthHz(index),obj.TargetSNRdB(index));
                output=obj.addSpatialSignal(output,signal,positions, ...
                    obj.SearchCenterHz+obj.TargetOffsetHz(index), ...
                    obj.TargetAzDeg(index),obj.TargetElDeg(index),c);
            end
            for index=1:obj.NumInterferers
                signal=obj.makeBand(frequency,obj.InterfererOffsetHz(index), ...
                    obj.InterfererBandwidthHz(index),obj.InterfererSNRdB(index));
                output=obj.addSpatialSignal(output,signal,positions, ...
                    obj.SearchCenterHz+obj.InterfererOffsetHz(index), ...
                    obj.InterfererAzDeg(index),obj.InterfererElDeg(index),c);
            end
            output=output+(randn(N,4)+1j*randn(N,4))/sqrt(2);
            for channel=1:4
                output(:,channel)=output(:,channel)*10^(obj.ChannelGain_dB(channel)/20)* ...
                    exp(1j*deg2rad(obj.ChannelPhaseError_deg(channel)));
            end
        end
        function sizeOut=getOutputSizeImpl(obj), sizeOut=[obj.FrameLength 4]; end
        function typeOut=getOutputDataTypeImpl(~), typeOut='double'; end
        function value=isOutputComplexImpl(~), value=true; end
        function value=isOutputFixedSizeImpl(~), value=true; end
        function name=getOutputNamesImpl(~), name='X4'; end
        function icon=getIconImpl(~), icon=sprintf('4CH Synthetic IQ\nTargets + Interferers'); end
    end
    methods (Access=private)
        function signal=makeBand(obj,frequency,center,bandwidth,snr_dB)
            spectrum=complex(zeros(obj.FrameLength,1));
            active=abs(frequency-center)<=bandwidth/2;
            count=sum(active);
            spectrum(active)=(randn(count,1)+1j*randn(count,1))/sqrt(2);
            signal=ifft(ifftshift(spectrum))*sqrt(obj.FrameLength);
            powerValue=mean(abs(signal).^2);
            if powerValue>0, signal=signal/sqrt(powerValue); end
            signal=signal*sqrt(10^(snr_dB/10));
        end
        function output=addSpatialSignal(~,output,signal,positions,rfFrequency,azimuth,elevation,c)
            ux=cosd(elevation)*cosd(azimuth);
            uy=cosd(elevation)*sind(azimuth);
            for channel=1:4
                delay=(positions(channel,1)*ux+positions(channel,2)*uy)/c;
                output(:,channel)=output(:,channel)+signal*exp(-1j*2*pi*rfFrequency*delay);
            end
        end
    end
end
