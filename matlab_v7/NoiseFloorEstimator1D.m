classdef NoiseFloorEstimator1D < matlab.System
    properties (Nontunable)
        NumBins = 1024
        MedianWindowBins = 81
        PowerFloor = 1e-15
    end
    methods
        function obj=NoiseFloorEstimator1D(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function [localNoise,globalNoise,globalNoise_dB]=stepImpl(obj,powerValue)
            halfWindow=floor(obj.MedianWindowBins/2);
            localNoise=zeros(obj.NumBins,1);
            for index=1:obj.NumBins
                first=max(1,index-halfWindow);
                last=min(obj.NumBins,index+halfWindow);
                localNoise(index)=median(powerValue(first:last));
            end
            globalNoise=median(powerValue);
            globalNoise_dB=10*log10(max(globalNoise,obj.PowerFloor));
        end
        function [a,b,c]=getOutputSizeImpl(obj)
            a=[obj.NumBins 1]; b=[1 1]; c=[1 1];
        end
        function [a,b,c]=getOutputDataTypeImpl(~), a='double'; b='double'; c='double'; end
        function [a,b,c]=isOutputComplexImpl(~), a=false; b=false; c=false; end
        function [a,b,c]=isOutputFixedSizeImpl(~), a=true; b=true; c=true; end
        function name=getInputNamesImpl(~), name='Psum'; end
        function [a,b,c]=getOutputNamesImpl(~), a='Nlocal'; b='Nglobal'; c='Nglobal_dB'; end
        function icon=getIconImpl(obj), icon=sprintf('Noise Floor\nMedian W=%d',obj.MedianWindowBins); end
    end
end
