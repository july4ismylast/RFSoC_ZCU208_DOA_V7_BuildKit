classdef RealisticReceiver4 < matlab.System
    % Four-channel RF/ADC impairment model kept outside the synthesizable DUT.
    properties (Nontunable)
        Fs = 2.048e9
        FrameLength = 8192
        CenterFreqHz = 4e9
        NoiseFigure_dB = 3
        NoiseTemperature_K = 290
        ChannelGain_dB = [0 0.3 -0.2 0.15]
        ChannelPhase_deg = [0 1.0 -0.7 0.5]
        RelativeTimeSkew_ps = [0 0.4 -0.3 0.2]
        GainDrift_dB = [0 0.004 -0.003 0.005]
        PhaseDrift_deg = [0 0.015 -0.012 0.018]
        CouplingMatrix = eye(4)
        CommonPhaseNoiseStep_deg = 0.002
        DifferentialPhaseNoiseStep_deg = 0.0001
        FramePhaseJitter_deg = 0.005
        AGCTargetRMS = 0.25
        AGCMaximumGain_dB = 90
        ADCBits = 14
        ADCFullScale = 1
        DCOffset = [0 0 0 0]
        EnableThermalNoise = true
        EnableAGC = true
        EnableADCQuantization = true
    end
    methods
        function obj=RealisticReceiver4(varargin)
            setProperties(obj,nargin,varargin{:});
        end
    end
    methods (Access=protected)
        function setupImpl(obj,~)
            validateattributes(obj.CouplingMatrix,{'numeric'}, ...
                {'size',[4 4],'finite'},mfilename,'CouplingMatrix');
            validateattributes(obj.ADCBits,{'numeric'}, ...
                {'scalar','integer','>=',8,'<=',24},mfilename,'ADCBits');
        end
        function output=stepImpl(obj,input)
            numberSamples=size(input,1);

            % Direction-dependent antenna voltages are mixed by mutual
            % coupling before the independent receiver chains.
            output=input*obj.CouplingMatrix.';
            timeSkewPhase_deg=-360*obj.CenterFreqHz* ...
                (obj.RelativeTimeSkew_ps*1e-12);
            frameJitter=obj.FramePhaseJitter_deg*randn(1,4);
            totalGain=obj.ChannelGain_dB+obj.GainDrift_dB;
            totalPhase=obj.ChannelPhase_deg+obj.PhaseDrift_deg+ ...
                timeSkewPhase_deg+frameJitter;
            transfer=10.^(totalGain/20).*exp(1j*deg2rad(totalPhase));
            output=output.*transfer;

            if obj.EnableThermalNoise
                boltzmann=1.380649e-23;
                noisePower=boltzmann*obj.NoiseTemperature_K*obj.Fs* ...
                    10^(obj.NoiseFigure_dB/10);
                output=output+sqrt(noisePower/2)*( ...
                    randn(numberSamples,4)+1j*randn(numberSamples,4));
            end

            commonPhase=cumsum(obj.CommonPhaseNoiseStep_deg* ...
                randn(numberSamples,1));
            differentialPhase=cumsum(obj.DifferentialPhaseNoiseStep_deg* ...
                randn(numberSamples,4),1);
            output=output.*exp(1j*deg2rad(commonPhase+differentialPhase));

            if obj.EnableAGC
                measuredRMS=sqrt(mean(abs(output(:)).^2));
                requestedGain=obj.AGCTargetRMS/max(measuredRMS,eps);
                maximumGain=10^(obj.AGCMaximumGain_dB/20);
                output=output*min(requestedGain,maximumGain);
            end

            output=output+reshape(obj.DCOffset,1,4);
            if obj.EnableADCQuantization
                scale=2^(obj.ADCBits-1);
                normalized=output/obj.ADCFullScale;
                realPart=min(max(real(normalized),-1),1-1/scale);
                imagPart=min(max(imag(normalized),-1),1-1/scale);
                output=obj.ADCFullScale*(round(realPart*scale)/scale+ ...
                    1j*round(imagPart*scale)/scale);
            end
        end
        function sizeOut=getOutputSizeImpl(obj), sizeOut=[obj.FrameLength 4]; end
        function typeOut=getOutputDataTypeImpl(~), typeOut='double'; end
        function value=isOutputComplexImpl(~), value=true; end
        function value=isOutputFixedSizeImpl(~), value=true; end
        function name=getInputNamesImpl(~), name='IdealAntennaIQ'; end
        function name=getOutputNamesImpl(~), name='ADC_IQ'; end
        function icon=getIconImpl(obj)
            icon=sprintf('Real RF + ADC\n%d bit, NF %.1f dB', ...
                obj.ADCBits,obj.NoiseFigure_dB);
        end
    end
end
