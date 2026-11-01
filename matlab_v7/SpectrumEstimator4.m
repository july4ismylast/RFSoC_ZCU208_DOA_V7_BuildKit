classdef SpectrumEstimator4 < matlab.System
    properties (Nontunable)
        Fs = 2.048e9
        NumBands = 1024
        AverageAlpha = 0.25
        PowerFloor = 1e-15
    end
    properties (Access=private)
        PowerState
    end

    methods
        function obj=SpectrumEstimator4(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end

    methods (Access=protected)
        function setupImpl(obj,~), obj.PowerState=zeros(obj.NumBands,4); end
        function [power4,powerSum,power_dB,frequencyHz]=stepImpl(obj,input)
            shifted=fftshift(input,2);
            current=squeeze(mean(abs(shifted).^2,1));
            current=reshape(current,obj.NumBands,4);
            alpha=obj.AverageAlpha;
            obj.PowerState=(1-alpha)*obj.PowerState+alpha*current;
            power4=obj.PowerState;
            powerSum=mean(power4,2);
            power_dB=10*log10(max(powerSum,obj.PowerFloor));
            frequencyHz=((0:obj.NumBands-1).'-floor(obj.NumBands/2))*(obj.Fs/obj.NumBands);
        end
        function resetImpl(obj), obj.PowerState=zeros(obj.NumBands,4); end
        function [a,b,c,d]=getOutputSizeImpl(obj)
            a=[obj.NumBands 4]; b=[obj.NumBands 1]; c=b; d=b;
        end
        function [a,b,c,d]=getOutputDataTypeImpl(~)
            a='double'; b='double'; c='double'; d='double';
        end
        function [a,b,c,d]=isOutputComplexImpl(~)
            a=false; b=false; c=false; d=false;
        end
        function [a,b,c,d]=isOutputFixedSizeImpl(~)
            a=true; b=true; c=true; d=true;
        end
        function name=getInputNamesImpl(~), name='Ysub'; end
        function [a,b,c,d]=getOutputNamesImpl(~)
            a='P4'; b='Psum'; c='P_dB'; d='f_Hz';
        end
        function icon=getIconImpl(~), icon=sprintf('Spectrum / PSD\n4 channels'); end
    end
end
