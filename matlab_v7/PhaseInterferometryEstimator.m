classdef PhaseInterferometryEstimator < matlab.System
    % Per-bin phase-interferometry DOA for the 2x2 ZCU208 array (V07).
    %
    % PS-side estimator for the wideband path in V07_PHASE_INTERFEROMETRY.md.
    % Input: Nfft x 4 complex, the four channel spectra of one snapshot,
    % already fftshift'ed (DC in the middle), as produced by
    % fftshift(fft(x .* window)) or by the 1024-band channelizer.
    %
    % PRIMARY ESTIMATOR: coherent weighted phase interferometry (WPI).  The
    % cross-spectrum is summed coherently over every bin the emitter occupies
    % and over every accumulated snapshot, then the six baseline phases are
    % solved by weighted least squares with coherence weights.  For a known
    % carrier this is the minimum-variance phase estimator:
    %
    %   sigma_theta = c/(2*pi*fc*d) * sigma_phi_bin / sqrt(K),  K = bins x snaps
    %
    % DIAGNOSTIC ONLY: multi-frequency phase-slope fit.  It is computed and
    % reported (SlopeAzimuth_deg/SlopeElevation_deg) because the external
    % architecture review proposed it as the primary estimator, but it is not
    % used for the reported angle.  Its variance is
    %
    %   sigma_theta = c/(2*pi*d) * sigma_phi_bin * sqrt(12/(K*B^2))
    %
    % which is sqrt(12)*fc/B worse than WPI, and fc > B/2 always, so the slope
    % estimator is never better for a known carrier.  It is the right tool only
    % when the emitter fills the band AND the carrier is unknown, or to unwrap
    % an ambiguous long baseline.
    %
    % FixedPointMode = true reproduces the PL exactly: Q3.17 calibrated
    % integers, int64 cross-spectrum accumulators and the same integer CORDIC
    % atan2 as ip/custom/phase_interf_4ch (Q3.13 output, <=2 LSB error).
    %
    % Sign convention (identical to estimate_doa_from_covariance_v7.m):
    %   A_n = exp(-1j*k*(p_n . u));  S_ab = X_a*conj(X_b) => angle = +k*B*u
    %   u = (B'WB)^-1 * B'W*phi / k;  uy from CH1->CH2 (+y), uz from CH1->CH3 (+z).
    %
    % See also verify_phase_interferometry_2x2, DOAEstimator4Ch,
    % estimate_doa_from_covariance_v7.
    
    properties (Nontunable)
        % Array geometry in metres; array plane = y-z, boresight = +x.
        ArrayPositions = [ 0 -0.0125 -0.0125
                           0  0.0125 -0.0125
                           0 -0.0125  0.0125
                           0  0.0125  0.0125 ]
        SampleRateHz = 2e9          % 4.000 GSPS / RFDC decimation 2 (V04)
        CenterFrequencyHz = 3e9     % V04 default RF centre
        CalibrationGain_dB = [0 0 0 0]
        CalibrationPhase_deg = [0 0 0 0]
        DetectionOffset_dB = 10     % detection threshold above the median bin
        MinClusterBins = 3
        MaxEmitters = 1
        EnableSlopeDiagnostic = true
        FixedPointMode = false
    end
    
    properties (Constant)
        LightSpeed = 299792458
        BaselinePairs = [1 2; 1 3; 1 4; 2 3; 2 4; 3 4]
        AccumulatorFractionBits = 17   % Q3.17 calibrated value (>>14 like the IP)
    end
    
    properties (Access=private)
        BaselineYZ
    end
    
    methods
        function obj = PhaseInterferometryEstimator(varargin)
            setProperties(obj, nargin, varargin{:});
        end
    end
    
    methods (Access=protected)
        function setupImpl(obj, spectra) %#ok<INUSD>
            validateattributes(obj.ArrayPositions, {'numeric'}, ...
                {'size',[4 3],'real','finite'}, mfilename, 'ArrayPositions');
            validateattributes(obj.SampleRateHz, {'numeric'}, ...
                {'scalar','positive','finite'}, mfilename, 'SampleRateHz');
            
            pairs = obj.BaselinePairs;
            baseline = zeros(6,2);
            for pair = 1:6
                difference = obj.ArrayPositions(pairs(pair,2),:) - ...
                             obj.ArrayPositions(pairs(pair,1),:);
                baseline(pair,:) = difference(2:3);
            end
            obj.BaselineYZ = baseline;
        end
        
        function detections = stepImpl(obj, spectra)
            validateattributes(spectra, {'numeric'}, {'2d','ncols',4}, ...
                mfilename, 'spectra');
            numberOfBins = size(spectra,1);
            
            % --- per-channel calibration -----------------------------------
            gain = 10.^(obj.CalibrationGain_dB(:)/20) .* ...
                   exp(1j*deg2rad(obj.CalibrationPhase_deg(:)));
            calibrated = spectra .* gain.';
            
            if obj.FixedPointMode
                calibrateScale = 2^obj.AccumulatorFractionBits;
                calibrated = round(real(calibrated)*calibrateScale)/calibrateScale + ...
                    1j*round(imag(calibrated)*calibrateScale)/calibrateScale;
            end
            
            % --- frequency axis --------------------------------------------
            binHz = obj.SampleRateHz / numberOfBins;
            baseband = ((0:numberOfBins-1).' - numberOfBins/2) * binHz;
            rfHz = obj.CenterFrequencyHz + baseband;
            
            % --- per-bin cross-spectra and sum beam -------------------------
            pairs = obj.BaselinePairs;
            crossSpectrum = complex(zeros(numberOfBins,6));
            for pair = 1:6
                crossSpectrum(:,pair) = calibrated(:,pairs(pair,1)) .* ...
                                        conj(calibrated(:,pairs(pair,2)));
            end
            if obj.FixedPointMode
                scale = 2^obj.AccumulatorFractionBits;
                crossSpectrum = round(real(crossSpectrum)*scale)/scale + ...
                    1j*round(imag(crossSpectrum)*scale)/scale;
            end
            sumBeam = abs(sum(calibrated,2)).^2;
            
            % --- detection: median threshold plus contiguous clustering -----
            threshold = median(sumBeam) * 10^(obj.DetectionOffset_dB/10);
            above = sumBeam > threshold;
            edges = diff([false; above(:); false]);
            starts = find(edges == 1);
            stops = find(edges == -1) - 1;
            keep = (stops - starts + 1) >= obj.MinClusterBins;
            starts = starts(keep);
            stops = stops(keep);
            
            detections = struct('Azimuth_deg',{},'Elevation_deg',{},'Uy',{}, ...
                'Uz',{},'CenterFrequencyHz',{},'Coherence',{},'Snr_dB',{}, ...
                'Bins',{},'Estimator',{},'SlopeAzimuth_deg',{}, ...
                'SlopeElevation_deg',{},'Ambiguous',{},'PowerBalance_dB',{});
            
            for cluster = 1:min(numel(starts), obj.MaxEmitters)
                bins = (starts(cluster):stops(cluster)).';
                detection = obj.estimateCluster(calibrated, crossSpectrum, ...
                    sumBeam, rfHz, bins);
                detections(end+1) = detection; %#ok<AGROW>
            end
        end
        
        function detection = estimateCluster(obj, calibrated, crossSpectrum, ...
                sumBeam, rfHz, bins)
            pairs = obj.BaselinePairs;
            baseline = obj.BaselineYZ;
            
            accumulated = sum(crossSpectrum(bins,:), 1);        % 1 x 6
            channelPower = sum(abs(calibrated(bins,:)).^2, 1);  % 1 x 4
            phase = angle(accumulated);
            
            if obj.FixedPointMode
                % Hardware format: Q3.17 calibrated integers, products and the
                % bin sum in exact integer arithmetic (|value| < 2^47 for 4096
                % bins, so both int64 and double hold it exactly), then the same
                % integer CORDIC the PL uses.  Snapshot accumulation inside the
                % PL is covered by scripts/phase_interf_verify.py.
                scale = 2^obj.AccumulatorFractionBits;
                q = round(real(calibrated(bins,:))*scale) + ...
                    1j*round(imag(calibrated(bins,:))*scale);
                qr = real(q);
                qi = imag(q);
                channelPower = sum(abs(q).^2, 1);
                for pair = 1:6
                    first = pairs(pair,1);
                    second = pairs(pair,2);
                    realAccumulator = sum(qr(:,first).*qr(:,second) + ...
                                          qi(:,first).*qi(:,second));
                    imagAccumulator = sum(qi(:,first).*qr(:,second) - ...
                                          qr(:,first).*qi(:,second));
                    accumulated(pair) = complex(realAccumulator, imagAccumulator);
                    phase(pair) = double(phase_from_cordic_q13(imagAccumulator, ...
                                                              realAccumulator))/8192;
                end
            end
            
            % --- coherence weights: |S|^2 / (P_a P_b) ----------------------
            coherence = abs(accumulated(:)).^2 ./ ...
                max(channelPower(pairs(:,1)).' .* channelPower(pairs(:,2)).', realmin);
            coherence = min(0.999, max(1e-6, coherence(:)));
            weights = coherence ./ (1 - coherence);
            
            % --- power-weighted centroid frequency of the cluster ---------
            binPower = mean(abs(calibrated(bins,:)).^2, 2);
            centerHz = sum(binPower .* rfHz(bins)) / max(sum(binPower), realmin);
            
            % --- weighted least squares for the direction cosines ---------
            waveNumber = 2*pi*centerHz/obj.LightSpeed;
            weightedBaseline = baseline .* weights;
            normalMatrix = baseline.' * weightedBaseline + 1e-12*eye(2);
            directionYZ = normalMatrix \ (weightedBaseline.' * phase(:)) / waveNumber;
            
            if norm(directionYZ) > 0.999999
                directionYZ = 0.999999 * directionYZ / norm(directionYZ);
            end
            ux = sqrt(max(1 - sum(directionYZ.^2), 0));
            
            detection.Azimuth_deg = atan2d(directionYZ(1), ux);
            detection.Elevation_deg = asind(min(1,max(-1,directionYZ(2))));
            detection.Uy = directionYZ(1);
            detection.Uz = directionYZ(2);
            detection.CenterFrequencyHz = centerHz;
            detection.Coherence = mean(coherence);
            detection.Bins = bins;
            detection.Estimator = 'coherent_wpi';
            detection.Snr_dB = 10*log10(max(sumBeam(bins)) / ...
                max(median(sumBeam), realmin));
            
            % Amplitude is a quadrant / dead-channel diagnostic only; it
            % cannot resolve an interferometer ambiguity (V07 section 5.5).
            detection.PowerBalance_dB = 10*log10(max(channelPower)/ ...
                max(min(channelPower), realmin));
            
            % Ambiguity at the cluster's own centre frequency.
            widest = max(sqrt(sum(baseline.^2,2)));
            sinLimit = obj.LightSpeed/(2*centerHz*widest);
            detection.Ambiguous = abs(detection.Uy) > sinLimit || ...
                                  abs(detection.Uz) > sinLimit;
            
            % --- diagnostic slope fit (never used for the angle) ----------
            detection.SlopeAzimuth_deg = NaN;
            detection.SlopeElevation_deg = NaN;
            if obj.EnableSlopeDiagnostic && numel(bins) >= 8
                [slopeY, slopeZ] = obj.slopeFit(crossSpectrum, rfHz, bins);
                direction = [slopeY; slopeZ];
                if all(isfinite(direction)) && norm(direction) <= 0.999999
                    uxSlope = sqrt(1 - sum(direction.^2));
                    detection.SlopeAzimuth_deg = atan2d(direction(1), uxSlope);
                    detection.SlopeElevation_deg = asind(direction(2));
                end
            end
        end
        
        function [uy, uz] = slopeFit(obj, crossSpectrum, rfHz, bins)
            % Multi-frequency phase-slope fit, kept as a diagnostic because the
            % external review proposed it as the primary estimator.  Weighted
            % unwrapped linear fit over the cluster's bins for the two axes.
            frequencies = rfHz(bins);
            spacing = [norm(obj.ArrayPositions(2,:)-obj.ArrayPositions(1,:)), ...
                       norm(obj.ArrayPositions(3,:)-obj.ArrayPositions(1,:))];
            
            if numel(bins) < 4
                uy = NaN; uz = NaN;
                return;
            end
            
            results = zeros(1,2);
            for axis = 1:2
                cross = crossSpectrum(bins, axis);
                magnitude = abs(cross);
                unwrapped = unwrap(angle(cross));
                weight = magnitude / max(sum(magnitude), realmin);
                meanFrequency = sum(weight .* frequencies);
                meanPhase = sum(weight .* unwrapped);
                denominator = sum(weight .* (frequencies - meanFrequency).^2);
                if denominator <= 0
                    uy = NaN; uz = NaN;
                    return;
                end
                slope = sum(weight .* (frequencies - meanFrequency) .* ...
                            (unwrapped - meanPhase)) / denominator;
                results(axis) = slope * obj.LightSpeed / (2*pi*spacing(axis));
            end
            uy = results(1);
            uz = results(2);
        end
        
        function sz = getOutputSizeImpl(~), sz = [1 1]; end
        function name = getInputNamesImpl(~), name = "spectra"; end
        function name = getOutputNamesImpl(~), name = "detections"; end
        function flag = isInputComplexityMutableImpl(~, ~), flag = false; end
        function flag = isInputSizeMutableImpl(~, ~), flag = false; end
        function flag = isOutputSizeMutableImpl(~, ~), flag = true; end
        function icon = getIconImpl(~), icon = "2x2 phase interferometry"; end
    end
end
