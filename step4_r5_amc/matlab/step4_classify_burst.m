function result=step4_classify_burst(x,sps)
%STEP4_CLASSIFY_BURST One burst -> the AMC label, margin and features.
%   RESULT=STEP4_CLASSIFY_BURST(X, SPS) runs the same two functions that
%   Embedded Coder turns into the R5 library, on one complex column X:
%
%       [index,label,margin,features]=classify_modulation(X, SPS)
%
%   RESULT.INDEX / LABEL / MARGIN / FEATURES are the four values the PS
%   receives per detection.  Compare FEATURES against
%   firmware/amc_r5/test_amc.c for the same burst: they must agree to 1e-6
%   (double) which is exactly what scripts/amc_port_check.py checks as P2.

if nargin<2
    sps=4;
end
here=fileparts(mfilename('fullpath'));
addpath(fullfile(here,'..','..','matlab_v7'));

x=x(:);
[index,label,margin,features]=classify_modulation(x,sps);

result=struct();
result.index=index;
result.label=label;
result.margin=margin;
result.features=features;
result.samples=numel(x);
fprintf('step4: %d samples -> class %d (%s), margin %.3f\n', ...
        numel(x),index,label,margin);
fprintf('       features:');
fprintf(' %.4f',features);
fprintf('\n');
end
