function phaseQ13 = phase_from_cordic_q13(imagPart, realPart)
%PHASE_FROM_CORDIC_Q13 Integer CORDIC atan2, bit-identical to the PL block.
%
%   phaseQ13 = phase_from_cordic_q13(y, x) returns the angle of x + j*y as a
%   signed 16-bit Q3.13 value (radians * 8192), using the same 16-iteration
%   vectoring CORDIC, the same Q2.30 arctangent table and the same integer
%   shifts as ip/custom/phase_interf_4ch/src/phase_interf_core.hpp.  It is the
%   MATLAB twin of pir::atan2_q13 and exists so the reference can reproduce the
%   hardware's quantisation exactly, not approximately.
%
%   Inputs are the int64 cross-spectrum accumulators (real/imaginary parts of
%   sum(X_a * conj(X_b))).  Output range is +-4.0 rad, LSB 1.2207e-4 rad.
%
%   See also PhaseInterferometryEstimator, verify_phase_interferometry_2x2.

persistent atanTable
if isempty(atanTable)
    atanTable = int64(round(atan(2.^-(0:15)) * 2^30));   % Q2.30, 16 entries
end

y = int64(round(imagPart));
x = int64(round(realPart));

if x == 0 && y == 0
    phaseQ13 = int16(0);
    return;
end

% Scale so the larger magnitude lands in [2^28, 2^29): same normalisation as
% the HDL, so the shift-recurrence keeps full precision in 32-bit.
big = max(abs(x), abs(y));
shift = 0;
while big >= 2^29
    big = bitshift(big, -1);
    shift = shift + 1;
end
while big < 2^28
    big = bitshift(big, 1);
    shift = shift - 1;
end
if shift >= 0
    xs = bitshift(x, -shift);   % arithmetic right shift, as in the HDL
    ys = bitshift(y, -shift);
else
    xs = bitshift(x, -shift);   % -shift > 0: left shift
    ys = bitshift(y, -shift);
end

% Vectoring CORDIC covers the right half plane only.
halfTurn = int64(0);
if xs < 0
    xs = -xs;
    ys = -ys;
    if y >= 0
        halfTurn = int64(6746518852);    % +pi in Q2.31
    else
        halfTurn = int64(-6746518852);
    end
end

z = int64(0);
for index = 1:16
    dx = bitshift(ys, -(index-1));
    dy = bitshift(xs, -(index-1));
    if ys < 0
        xs = xs - dx;
        ys = ys + dy;
        z = z - atanTable(index);
    else
        xs = xs + dx;
        ys = ys - dy;
        z = z + atanTable(index);
    end
end

angleQ30 = z + bitshift(halfTurn, -1);
phaseQ13 = int16(bitshift(angleQ30, -17));
end
