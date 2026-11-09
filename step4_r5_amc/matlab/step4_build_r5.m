function outdir=step4_build_r5(outdir)
%STEP4_BUILD_R5 Gate G8b: turn the MATLAB classifier into an R5 library.
%   OUTDIR=STEP4_BUILD_R5() runs matlab_v7/build_amc_r5.m, which uses
%   MATLAB Coder / Embedded Coder to produce C for
%   matlab_v7/classify_modulation.m + amc_features.m.
%
%   Before you run this, the algorithm must already be green on the host:
%
%       python3 scripts/amc_export.py       % regenerate the tables
%       python3 scripts/amc_port_check.py   % G8a: C == model, 100 % labels
%
%   After it, run matlab_v7/verify_amc_vectors.m and then the on-target gate
%   G8c (cycles per burst).  Nothing in this file is a timing claim.

if nargin<1
    outdir=fullfile(fileparts(mfilename('fullpath')),'..','..','build','amc_r5_codegen');
end
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'..','..','matlab_v7'));

fprintf('step4: G8b -- MATLAB -> Embedded Coder -> C\n');
fprintf('       output: %s\n',outdir);
fprintf('       needs: Embedded Coder + Simulink Coder + ARM Cortex-R support\n');

tools=ver;
names={tools.Name};
for needed={'MATLAB Coder','Simulink Coder','Embedded Coder'}
    if any(strcmp(names,needed{1}))
        fprintf('       [ok]   %s\n',needed{1});
    else
        fprintf('       [MISS] %s -- codegen will fail\n',needed{1});
    end
end

outdir=build_amc_r5(outdir);
fprintf('step4: wrote %s\n',outdir);
end
