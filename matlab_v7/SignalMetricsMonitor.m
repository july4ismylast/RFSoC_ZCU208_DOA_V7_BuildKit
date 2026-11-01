classdef SignalMetricsMonitor < matlab.System
    % Convert spectrum/candidate values into display-friendly metrics.
    properties (Nontunable)
        SearchCenterHz = 4e9
        NumBins = 1024
    end
    methods
        function obj=SignalMetricsMonitor(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function [peak_dB,snr_dB,selectedRF_GHz,selectedBW_MHz]= ...
                stepImpl(obj,spectrum_dB,noise_dB,valid,centerOffsetHz,bandwidthHz)
            peak_dB=max(spectrum_dB);
            snr_dB=peak_dB-noise_dB;
            selectedRF_GHz=NaN;
            selectedBW_MHz=NaN;
            if valid
                selectedRF_GHz=(obj.SearchCenterHz+centerOffsetHz)/1e9;
                selectedBW_MHz=bandwidthHz/1e6;
            end
        end
        function [a,b,c,d]=getOutputSizeImpl(~), a=[1 1]; b=a; c=a; d=a; end
        function [a,b,c,d]=getOutputDataTypeImpl(~)
            a='double'; b='double'; c='double'; d='double';
        end
        function [a,b,c,d]=isOutputComplexImpl(~), a=false; b=false; c=false; d=false; end
        function [a,b,c,d]=isOutputFixedSizeImpl(~), a=true; b=true; c=true; d=true; end
        function [a,b,c,d,e]=getInputNamesImpl(~)
            a='Spectrum_dB'; b='Noise_dB'; c='DetectionValid';
            d='CenterOffset_Hz'; e='Bandwidth_Hz';
        end
        function [a,b,c,d]=getOutputNamesImpl(~)
            a='Peak_dB'; b='SNR_dB'; c='SelectedRF_GHz'; d='SelectedBW_MHz';
        end
        function icon=getIconImpl(~), icon=sprintf('Signal Metrics\nPeak / SNR / fc / BW'); end
    end
end
