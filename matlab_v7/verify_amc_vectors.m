function verify_amc_vectors(path)
%VERIFY_AMC_VECTORS  MATLAB against the vectors the C port is verified on.
%
%   verify_amc_vectors                     reads build/amc/amc_vectors.bin
%   verify_amc_vectors(path)               reads another file
%
%   The file is written by scripts/amc_export.py and holds, for every burst:
%   the complex samples, the features the Python model measured, and the true
%   class. This function recomputes the features and the label in MATLAB and
%   prints the agreement, which is the MATLAB half of the equivalence test
%   whose C half is scripts/amc_port_check.py.
%
%   Run it before build_amc_r5.m: if MATLAB does not agree with the model, the
%   problem is in the algorithm, not in codegen.
%
%   See also CLASSIFY_MODULATION, AMC_FEATURES, BUILD_AMC_R5.

if nargin < 1 || isempty(path)
    root = fileparts(fileparts(mfilename('fullpath')));
    path = fullfile(root, 'build', 'amc', 'amc_vectors.bin');
end
if exist(path, 'file') ~= 2
    error('verify_amc_vectors:missing', ...
          'No vector file at %s. Run: python3 scripts/amc_export.py', path);
end

handle = fopen(path, 'r', 'ieee-le');
header = fread(handle, 4, 'int32=>double').';
magic = header(1);
count = header(2);
n = header(3);
nf = header(4);
if magic ~= hex2dec('414D4331')
    fclose(handle);
    error('verify_amc_vectors:magic', 'Not an AMC vector file.');
end
raw = fread(handle, count * n * 2, 'float32=>single');
raw = reshape(raw, 2, []).';
reference = reshape(fread(handle, count * nf, 'float32=>single'), nf, []).';
truth = fread(handle, count, 'int32=>double');
fclose(handle);

labels = {'BPSK', 'QPSK', '8PSK', '16QAM', '4FSK'};
agree_label = 0;
agree_feature = 0;
worst = 0;
accuracy = 0;

for index = 1:count
    burst = complex(raw((index - 1) * n + 1:index * n, 1), ...
                    raw((index - 1) * n + 1:index * n, 2));
    [~, ~, ~, features] = classify_modulation(burst, 4);
    error_here = max(abs(double(features) - double(reference(index, :)).'));
    worst = max(worst, error_here);
    if error_here < 1e-3
        agree_feature = agree_feature + 1;
    end
    [decided, ~] = classify_modulation(burst, 4);
    truth_label = labels{truth(index) + 1};
    if strcmp(decided, truth_label)
        accuracy = accuracy + 1;
    end
    % the model's own label, re-derived from its features
    [model_label, ~] = label_from_features(reference(index, :).');
    if strcmp(decided, model_label)
        agree_label = agree_label + 1;
    end
end

fprintf('bursts                 %d x %d samples\n', count, n);
fprintf('label agreement        %.1f %%  (MATLAB against the model)\n', ...
        100 * agree_label / count);
fprintf('feature agreement      %.1f %%  (max |error| %.2e)\n', ...
        100 * agree_feature / count, worst);
fprintf('accuracy vs truth      %.1f %%\n', 100 * accuracy / count);
if agree_label == count && agree_feature == count
    fprintf('PASS: MATLAB reproduces the model; codegen may proceed (G8b).\n');
else
    fprintf('FAIL: fix the algorithm before building for the RPU.\n');
end
end

function [label, margin] = label_from_features(vector)
[centre, spread, means, labels] = amc_model_params();
z = (single(vector(:)) - centre) ./ spread;
distance = sqrt(sum((means - z.').^2, 2));
[sorted, order] = sort(distance);
label = labels{order(1)};
margin = sorted(2) - sorted(1);
end
