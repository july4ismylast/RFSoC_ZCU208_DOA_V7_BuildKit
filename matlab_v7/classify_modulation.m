function [index, label, margin, features] = classify_modulation(x, sps)
%CLASSIFY_MODULATION  Automatic modulation classification for the R5F.
%
%   [index, label, margin, features] = classify_modulation(x, sps)
%
%   x     complex column, the carrier-recovered burst for one detection
%   sps   samples per symbol (4 in this build kit)
%   index 1..5, label 'BPSK'|'QPSK'|'8PSK'|'16QAM'|'4FSK'
%   margin runner-up distance minus best distance, in standardised units:
%          large means "the label is decided", small means "two classes are
%          close and the caller should fall back to the previous label"
%          (V07 section 18.4: a vote, not a fresh label, is what a track needs)
%
%   This is the function Embedded Coder compiles into the static library the
%   RPU links. It is deliberately the same arithmetic as
%   firmware/amc_r5/amc.c, which is the version verified on the host against
%   scripts/modulation_clustering.py:
%
%     features -> standardise by centre/spread -> nearest class mean
%
%   Nearest class mean, not a network: six features, five classes, 30 stored
%   constants, no training at run time. Section 18 measures what it costs in
%   accuracy (100 % at 10 dB, chance at 0 dB) and section 20 says what the
%   firmware may and may not claim.
%
%   See also AMC_FEATURES, AMC_MODEL_PARAMS, BUILD_AMC_R5, VERIFY_AMC_VECTORS.

%#codegen

[centre, spread, means, labels] = amc_model_params();

features = amc_features(x, sps);
z = (features - centre) ./ spread;

distance = sqrt(sum((means - z.').^2, 2));
[sorted, order] = sort(distance);

index = order(1);
label = labels{index};
if numel(sorted) > 1
    margin = sorted(2) - sorted(1);
else
    margin = inf;
end
end
