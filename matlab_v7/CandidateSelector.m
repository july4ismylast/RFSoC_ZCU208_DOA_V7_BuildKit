classdef CandidateSelector < matlab.System
    properties (Nontunable)
        MaxClusters = 16
        BW_MinHz = 0.5e6
        BW_MaxHz = 40e6
        MinCandidateSNRdB = 0
    end
    methods
        function obj=CandidateSelector(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function [valid,indexSelected,centerHz,bandwidthHz,peak_dB]= ...
                stepImpl(obj,count,centers,bandwidths,peaks,noise_dB)
            number=min(double(count),obj.MaxClusters);
            bestScore=-inf;
            selected=0;
            for index=1:number
                bandwidth=bandwidths(index);
                snr=peaks(index)-noise_dB;
                if bandwidth>=obj.BW_MinHz && bandwidth<=obj.BW_MaxHz && ...
                        snr>=obj.MinCandidateSNRdB
                    score=snr-0.05*abs(bandwidth-30e6)/1e6;
                    if score>bestScore, bestScore=score; selected=index; end
                end
            end
            valid=selected>0;
            indexSelected=uint16(selected);
            centerHz=0; bandwidthHz=0; peak_dB=-inf;
            if valid
                centerHz=centers(selected);
                bandwidthHz=bandwidths(selected);
                peak_dB=peaks(selected);
            end
        end
        function [a,b,c,d,e]=getOutputSizeImpl(~), a=[1 1]; b=a; c=a; d=a; e=a; end
        function [a,b,c,d,e]=getOutputDataTypeImpl(~)
            a='logical'; b='uint16'; c='double'; d='double'; e='double';
        end
        function [a,b,c,d,e]=isOutputComplexImpl(~)
            a=false; b=false; c=false; d=false; e=false;
        end
        function [a,b,c,d,e]=isOutputFixedSizeImpl(~)
            a=true; b=true; c=true; d=true; e=true;
        end
        function [a,b,c,d,e]=getInputNamesImpl(~)
            a='Nclusters'; b='Centers'; c='BWs'; d='Peaks'; e='Noise_dB';
        end
        function [a,b,c,d,e]=getOutputNamesImpl(~)
            a='Valid'; b='Index'; c='fc_Hz'; d='BW_Hz'; e='Peak_dB';
        end
        function icon=getIconImpl(~), icon=sprintf('Candidate Selector\nBW + SNR'); end
    end
end
