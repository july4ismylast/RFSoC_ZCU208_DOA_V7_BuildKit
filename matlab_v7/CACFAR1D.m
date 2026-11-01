classdef CACFAR1D < matlab.System
    properties (Nontunable)
        NumBins = 1024
        TrainCells = 24
        GuardCells = 4
        Pfa = 1e-5
    end
    methods
        function obj=CACFAR1D(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function [detections,threshold,noiseEstimate]=stepImpl(obj,powerValue)
            trainingCount=2*obj.TrainCells;
            alpha=trainingCount*(obj.Pfa^(-1/trainingCount)-1);
            detections=false(obj.NumBins,1);
            threshold=inf(obj.NumBins,1);
            noiseEstimate=zeros(obj.NumBins,1);
            first=1+obj.TrainCells+obj.GuardCells;
            last=obj.NumBins-(obj.TrainCells+obj.GuardCells);
            for index=first:last
                left=powerValue(index-obj.GuardCells-obj.TrainCells:index-obj.GuardCells-1);
                right=powerValue(index+obj.GuardCells+1:index+obj.GuardCells+obj.TrainCells);
                noise=(sum(left)+sum(right))/trainingCount;
                noiseEstimate(index)=noise;
                threshold(index)=alpha*noise;
                detections(index)=powerValue(index)>threshold(index);
            end
        end
        function [a,b,c]=getOutputSizeImpl(obj), a=[obj.NumBins 1]; b=a; c=a; end
        function [a,b,c]=getOutputDataTypeImpl(~), a='logical'; b='double'; c='double'; end
        function [a,b,c]=isOutputComplexImpl(~), a=false; b=false; c=false; end
        function [a,b,c]=isOutputFixedSizeImpl(~), a=true; b=true; c=true; end
        function name=getInputNamesImpl(~), name='Psum'; end
        function [a,b,c]=getOutputNamesImpl(~), a='Detect'; b='Threshold'; c='CFAR_Noise'; end
        function icon=getIconImpl(obj)
            icon=sprintf('CA-CFAR\nT=%d, G=%d',obj.TrainCells,obj.GuardCells);
        end
    end
end
