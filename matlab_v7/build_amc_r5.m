function build_amc_r5(outdir)
%BUILD_AMC_R5  Embedded Coder: the modulation classifier as an R5F library.
%
%   build_amc_r5            writes build/amc_r5_codegen
%   build_amc_r5(outdir)    writes to outdir
%
%   WHAT THIS PRODUCES
%     a static library (libclassify_modulation.a or the sources for one) plus
%     the generated headers, built from matlab_v7/classify_modulation.m and
%     matlab_v7/amc_features.m, with the constants from amc_model_params.m.
%     The RPU links it into the bare-metal application; nothing in the library
%     allocates, and every loop has a bound the generated code can prove.
%
%   REQUIRES
%     MATLAB R2023a or newer, Embedded Coder, and the ARM Cortex-R support
%     package (Simulink Coder + Embedded Coder licences). None of that exists
%     in the repository's CI, which is why V07 section 20 lists this as gate
%     G8b -- written, not run.
%
%   BEFORE THE FIRST BUILD
%     1. python3 scripts/amc_export.py     (regenerates amc_model_params.m and
%                                           the C header from the same fit)
%     2. python3 scripts/amc_port_check.py (verifies the C port on the host)
%   If (2) is not PASS, codegen is not the next step: the algorithm is wrong.
%
%   AFTER THE BUILD
%     Run matlab_v7/verify_amc_vectors.m (MATLAB against the shared vectors),
%     then link the library on the target and run gate G8c (cycles and the
%     frame deadline). Until G8c passes, no timing claim may be quoted.
%
%   See also CLASSIFY_MODULATION, AMC_FEATURES, VERIFY_AMC_VECTORS.

if nargin < 1 || isempty(outdir)
    root = fileparts(fileparts(mfilename('fullpath')));
    outdir = fullfile(root, 'build', 'amc_r5_codegen');
end
if exist(outdir, 'dir') ~= 7
    mkdir(outdir);
end

cfg = coder.config('lib');
cfg.TargetLang = 'C';
cfg.GenCodeOnly = true;              % Embedded Coder: sources + makefile

% The target is the ZynqMP RPU: Cortex-R5F, little endian, single-precision FPU
% only. Double arithmetic is soft-float there, which is why the default build
% of firmware/amc_r5 uses float accumulators.
cfg.HardwareImplementation.ProdHWDeviceType = 'ARM Compatible->ARM Cortex-R';
cfg.HardwareImplementation.ProdEndianess = 'LittleEndian';
cfg.HardwareImplementation.ProdBitPerChar = 8;
cfg.HardwareImplementation.ProdBitPerShort = 16;
cfg.HardwareImplementation.ProdBitPerInt = 32;
cfg.HardwareImplementation.ProdBitPerLong = 32;
cfg.HardwareImplementation.ProdBitPerFloat = 32;
cfg.HardwareImplementation.ProdBitPerDouble = 64;
cfg.HardwareImplementation.ProdIntDivRoundTo = 'Zero';
cfg.SupportNonFinite = false;        % a NaN label is worse than a wrong label

% One fixed-size burst. 1024 samples of complex single = 8 kB of input.
burst = coder.typeof(single(complex(0, 0)), [1024 1], [0 1]);
arg = {burst, coder.Constant(int32(4))};

fprintf('Embedded Coder -> %s\n', outdir);
codegen('-config', cfg, 'classify_modulation', '-args', arg, ...
        '-d', outdir, '-report');

fprintf('\nGenerated files are in %s/codegen/lib/classify_modulation.\n', outdir);
fprintf('RPU compile flags used by the build kit:\n');
fprintf(['  armr5-none-eabi-gcc -mcpu=cortex-r5 -mfloat-abi=hard ' ...
         '-mfpu=vfpv3-d16 -O2 -ffunction-sections -fdata-sections\n']);
fprintf(['Link:  -Wl,--gc-sections  |  Stack: the largest frame is one ' ...
         '1024-point FFT, about 16 kB.\n']);
end
