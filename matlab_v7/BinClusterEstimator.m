classdef BinClusterEstimator < matlab.System
    properties (Nontunable)
        NumBins = 1024
        MaxClusters = 16
        MergeGapBins = 1
        MinClusterBins = 1
        PowerFloor = 1e-15
    end
    methods
        function obj=BinClusterEstimator(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function [count,centerHz,bandwidthHz,startHz,stopHz,peakPower_dB]= ...
                stepImpl(obj,detect,powerSum,frequencyHz)
            mask=logical(detect(:));
            if obj.MergeGapBins>0
                index=1;
                while index<=obj.NumBins
                    if mask(index)
                        next=index+1;
                        while next<=obj.NumBins && ~mask(next) && ...
                                (next-index-1)<=obj.MergeGapBins
                            next=next+1;
                        end
                        if next<=obj.NumBins && mask(next) && ...
                                (next-index-1)<=obj.MergeGapBins
                            mask(index:next)=true;
                        end
                    end
                    index=index+1;
                end
            end

            centerHz=zeros(obj.MaxClusters,1);
            bandwidthHz=zeros(obj.MaxClusters,1);
            startHz=zeros(obj.MaxClusters,1);
            stopHz=zeros(obj.MaxClusters,1);
            peakPower_dB=-inf(obj.MaxClusters,1);
            count=uint16(0);
            if obj.NumBins>1
                binWidth=abs(frequencyHz(2)-frequencyHz(1));
            else
                binWidth=0;
            end

            index=1;
            while index<=obj.NumBins && double(count)<obj.MaxClusters
                if ~mask(index), index=index+1; continue; end
                first=index;
                while index<obj.NumBins && mask(index+1), index=index+1; end
                last=index;
                numberOfBins=last-first+1;
                if numberOfBins>=obj.MinClusterBins
                    count=count+1;
                    outputIndex=double(count);
                    clusterPower=powerSum(first:last);
                    clusterFrequency=frequencyHz(first:last);
                    denominator=sum(clusterPower);
                    if denominator>0
                        centerHz(outputIndex)=sum(clusterFrequency.*clusterPower)/denominator;
                    else
                        centerHz(outputIndex)=mean(clusterFrequency);
                    end
                    startHz(outputIndex)=frequencyHz(first)-binWidth/2;
                    stopHz(outputIndex)=frequencyHz(last)+binWidth/2;
                    bandwidthHz(outputIndex)=numberOfBins*binWidth;
                    peakPower_dB(outputIndex)=10*log10(max(max(clusterPower),obj.PowerFloor));
                end
                index=index+1;
            end
        end
        function [a,b,c,d,e,f]=getOutputSizeImpl(obj)
            a=[1 1]; b=[obj.MaxClusters 1]; c=b; d=b; e=b; f=b;
        end
        function [a,b,c,d,e,f]=getOutputDataTypeImpl(~)
            a='uint16'; b='double'; c='double'; d='double'; e='double'; f='double';
        end
        function [a,b,c,d,e,f]=isOutputComplexImpl(~)
            a=false; b=false; c=false; d=false; e=false; f=false;
        end
        function [a,b,c,d,e,f]=isOutputFixedSizeImpl(~)
            a=true; b=true; c=true; d=true; e=true; f=true;
        end
        function [a,b,c]=getInputNamesImpl(~), a='Detect'; b='Psum'; c='f_Hz'; end
        function [a,b,c,d,e,f]=getOutputNamesImpl(~)
            a='Nclusters'; b='Center_Hz'; c='BW_Hz'; d='Start_Hz'; e='Stop_Hz'; f='Peak_dB';
        end
        function icon=getIconImpl(~), icon=sprintf('Bin Clustering\nfc and BW'); end
    end
end
