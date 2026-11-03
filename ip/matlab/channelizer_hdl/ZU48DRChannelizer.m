classdef ZU48DRChannelizer < matlab.System
    % HDL-oriented one-channel channelizer wrapper.
    %
    % build_model.m supplies the production-size NumBands, prototype
    % Coefficients, FilterStructure and NormalizeFFT values from
    % config.mk.  The defaults below identify the proved systolic V06
    % baseline, but the short fallback coefficient vector is only a
    % placeholder for an unconfigured block and must never be used for
    % generated hardware.
    properties (Nontunable)
        NumBands = 1024
        Coefficients = [-0.032 0.121 0.318 0.482 0.546 0.482 0.318 0.121 -0.032]
        % Gate-2 proved this default for one-channel OOC synthesis.
        % build_model.m selects 'Direct form transposed' only for the
        % isolated Gate-2T A/B targets.  Keep the allowed values as a
        % cell array of character vectors: Simulink code generation
        % rejects string arrays in a MATLAB System block (Gate-1
        % transposed attempt 2).
        FilterStructure (1,:) char {mustBeMember(FilterStructure, {'Direct form systolic', 'Direct form transposed'})} = 'Direct form systolic'
        % Gate-0 probe v2 proved Normalize=false for the 1024-band,
        % SSR-8 fixed-point configuration.  Normalize=true underflowed
        % to about two output LSBs in attempt 1.
        NormalizeFFT = false
    end
    properties(Access=private)
        H
    end
    methods(Access=protected)
        function setupImpl(obj,~,~)
            obj.H = dsphdl.Channelizer(NumFrequencyBands=obj.NumBands, ...
                FilterCoefficients=obj.Coefficients, ...
                FilterStructure=obj.FilterStructure, ...
                OutputSize='Same as input size', ...
                Normalize=logical(obj.NormalizeFFT));
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
