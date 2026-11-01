classdef PFBFFTChannelizer4 < matlab.System
    % Frame-based floating-point PFB/FFT reference model.
    properties (Nontunable)
        FrameLength = 8192
        NumBands = 1024
        DecimationFactor = 1024
        TapsPerBand = 12
        StopbandAttenuation_dB = 100
    end
    properties (Access=private)
        Channelizer0
        Channelizer1
        Channelizer2
        Channelizer3
    end

    methods
        function obj=PFBFFTChannelizer4(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end

    methods (Access=protected)
        function setupImpl(obj,~)
            obj.Channelizer0=obj.createChannelizer();
            obj.Channelizer1=obj.createChannelizer();
            obj.Channelizer2=obj.createChannelizer();
            obj.Channelizer3=obj.createChannelizer();
        end
        function output=stepImpl(obj,input)
            output=complex(zeros(obj.FrameLength/obj.DecimationFactor,obj.NumBands,4));
            output(:,:,1)=obj.Channelizer0(input(:,1));
            output(:,:,2)=obj.Channelizer1(input(:,2));
            output(:,:,3)=obj.Channelizer2(input(:,3));
            output(:,:,4)=obj.Channelizer3(input(:,4));
        end
        function resetImpl(obj)
            reset(obj.Channelizer0); reset(obj.Channelizer1);
            reset(obj.Channelizer2); reset(obj.Channelizer3);
        end
        function releaseImpl(obj)
            release(obj.Channelizer0); release(obj.Channelizer1);
            release(obj.Channelizer2); release(obj.Channelizer3);
        end
        function sizeOut=getOutputSizeImpl(obj)
            sizeOut=[obj.FrameLength/obj.DecimationFactor obj.NumBands 4];
        end
        function typeOut=getOutputDataTypeImpl(~), typeOut='double'; end
        function value=isOutputComplexImpl(~), value=true; end
        function value=isOutputFixedSizeImpl(~), value=true; end
        function name=getInputNamesImpl(~), name='X4'; end
        function name=getOutputNamesImpl(~), name='Ysub'; end
        function icon=getIconImpl(obj)
            icon=sprintf('PFB + FFT\nM=%d, D=%d',obj.NumBands,obj.DecimationFactor);
        end
    end
    methods (Access=private)
        function channelizer=createChannelizer(obj)
            channelizer=dsp.Channelizer(obj.NumBands,obj.DecimationFactor, ...
                'Specification','Number of taps per band and stopband attenuation', ...
                'NumTapsPerBand',obj.TapsPerBand, ...
                'StopbandAttenuation',obj.StopbandAttenuation_dB);
        end
    end
end
