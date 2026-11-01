classdef ZU48DRChannelizer4 < matlab.System
    % Four parallel hardware-oriented channelizers for coherent RFSoC input.
    properties (Nontunable)
        NumBands = 1024
        FilterCoefficients = 1
    end
    properties (Access=private)
        Channelizer0
        Channelizer1
        Channelizer2
        Channelizer3
    end
    methods
        function obj=ZU48DRChannelizer4(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function setupImpl(obj,~,~,~,~,~)
            arguments={'NumFrequencyBands',obj.NumBands, ...
                'FilterCoefficients',obj.FilterCoefficients,'Normalize',true};
            obj.Channelizer0=dsphdl.Channelizer(arguments{:});
            obj.Channelizer1=dsphdl.Channelizer(arguments{:});
            obj.Channelizer2=dsphdl.Channelizer(arguments{:});
            obj.Channelizer3=dsphdl.Channelizer(arguments{:});
        end
        function [bins0,bins1,bins2,bins3,validOut]= ...
                stepImpl(obj,adc0,adc1,adc2,adc3,validIn)
            [bins0,valid0]=obj.Channelizer0(adc0,validIn);
            [bins1,valid1]=obj.Channelizer1(adc1,validIn);
            [bins2,valid2]=obj.Channelizer2(adc2,validIn);
            [bins3,valid3]=obj.Channelizer3(adc3,validIn);
            validOut=valid0 && valid1 && valid2 && valid3;
        end
        function resetImpl(obj)
            reset(obj.Channelizer0); reset(obj.Channelizer1);
            reset(obj.Channelizer2); reset(obj.Channelizer3);
        end
        function releaseImpl(obj)
            release(obj.Channelizer0); release(obj.Channelizer1);
            release(obj.Channelizer2); release(obj.Channelizer3);
        end
        function [a,b,c,d,e]=getOutputSizeImpl(obj)
            a=[1 obj.NumBands]; b=a; c=a; d=a; e=[1 1];
        end
        function [a,b,c,d,e]=getOutputDataTypeImpl(obj)
            a=propagatedInputDataType(obj,1); b=propagatedInputDataType(obj,2);
            c=propagatedInputDataType(obj,3); d=propagatedInputDataType(obj,4);
            e='logical';
        end
        function [a,b,c,d,e]=isOutputComplexImpl(~)
            a=true; b=true; c=true; d=true; e=false;
        end
        function [a,b,c,d,e]=isOutputFixedSizeImpl(~)
            a=true; b=true; c=true; d=true; e=true;
        end
        function [a,b,c,d,e]=getInputNamesImpl(~)
            a='ADC0_IQ'; b='ADC1_IQ'; c='ADC2_IQ'; d='ADC3_IQ'; e='validIn';
        end
        function [a,b,c,d,e]=getOutputNamesImpl(~)
            a='Bins0'; b='Bins1'; c='Bins2'; d='Bins3'; e='validOut';
        end
        function icon=getIconImpl(obj)
            icon=sprintf('RFSoC HDL 4CH\nChannelizer M=%d',obj.NumBands);
        end
    end
end
