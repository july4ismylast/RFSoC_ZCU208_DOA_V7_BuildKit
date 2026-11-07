function f = amc_features(x, sps)
%AMC_FEATURES  The six features of V07 section 18, in MATLAB.
%
%   f = amc_features(x, sps) returns a 6x1 single vector for the complex burst
%   x (a column), with sps samples per symbol.
%
%   Features, in the order the model expects:
%     [1] |C40|      fourth-order cumulant, the BPSK/QPSK discriminator
%     [2] C42        fourth-order moment of the amplitude, the QAM discriminator
%     [3] sigma_ap   amplitude variation, the QAM/PSK discriminator
%     [4] gamma_max  peak of the amplitude-ripple spectrum
%     [5] freq_std   spread of the phase increment, separates FSK
%     [6] spike      fraction of phase increments above a quarter turn
%
%   This file is the Embedded Coder source for the R5F library. It must agree
%   with three other implementations to the last bit of single precision:
%     scripts/modulation_clustering.py   (the model, V07 section 18)
%     firmware/amc_r5/amc.c              (the host-verified C port)
%     matlab_v7/amc_model_params.m       (the generated constants)
%   matlab_v7/verify_amc_vectors.m runs that comparison on the shared vectors.
%
%   Codegen notes: fixed size, no allocation, no dynamic strings. `std(... , 1)`
%   is the population standard deviation -- NumPy's default, not MATLAB's.
%
%   See also CLASSIFY_MODULATION, BUILD_AMC_R5, AMC_MODEL_PARAMS.

%#codegen

n = numel(x);
power = mean(abs(x).^2);

c20 = mean(x.^2) / power;
c40 = abs(mean(x.^4) - 3.0 * c20^2) / power;
c42 = mean(abs(x).^4) / power^2;

a = abs(x);
mean_a = mean(a);
sigma_ap = std(a, 1) / mean_a;

centred = a / mean_a - 1.0;
spectrum = abs(fft(centred)).^2;
gamma_max = max(spectrum) / n;

phase = unwrap(angle(x));
step = diff(phase) / (2.0 * pi);
freq_std = std(step, 1) * sps;
spike = mean(abs(step) * sps > 0.25);

f = single([c40; c42; sigma_ap; gamma_max; freq_std; spike]);
end
