classdef ZU48DRChannelizer < matlab.System
    % HDL-oriented channelizer wrapper used with a four-sample vector harness.
    % Generated HDL must still prove the required sample rate and timing.
    properties (Nontunable)
        NumBands = 64
        % build_model overrides this fallback with a production 768-tap
        % prototype stored as a constant in the model workspace.
        Coefficients = [-0.032 0.121 0.318 0.482 0.546 0.482 0.318 0.121 -0.032]
    end
    properties(Access=private)
        H
    end
    methods(Access=protected)
        function setupImpl(obj,~,~)
            obj.H = dsphdl.Channelizer(NumFrequencyBands=obj.NumBands, ...
                FilterCoefficients=obj.Coefficients, ...
                FilterStructure='Direct form systolic', ...
                OutputSize='Same as input size', ...
                Normalize=true);
        end
        function [y,v] = stepImpl(obj,x,valid)
            % R2024a requires a column-vector data input and logical scalar
            % valid input. Indexing is static and synthesizable.
            [y,v] = obj.H(x(:),logical(valid(1)));
        end
        function resetImpl(obj), reset(obj.H); end
        function releaseImpl(obj), release(obj.H); end
        function icon=getIconImpl(obj), icon=sprintf('DSP HDL Channelizer\\nM=%d',obj.NumBands); end
    end
end
