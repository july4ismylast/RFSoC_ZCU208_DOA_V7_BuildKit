function budget=step2_fixed_point_budget()
%STEP2_FIXED_POINT_BUDGET Does the PL's fixed point fit the 0.5 deg budget?
%   The kernel ip/custom/phase_interf_4ch accumulates a cross-spectrum and takes
%   one CORDIC phase per baseline record (16 words = 32 bits per phase).  This
%   file answers, with numbers, what each quantisation step costs in degrees:
%
%     phase LSB  dphi = 2*pi*2^-b                      (b = bits of the phase)
%     angle LSB  dtheta = dphi * lambda/(2*pi*d)       (d = 25 mm, f = 4 GHz)
%     accumulator  worst-case power = 4096 * |x|^2 * 2^30 (Q15 input, 12-bit ADC)
%
%   BUDGET.FIELDS: bits, phase_lsb_rad, angle_lsb_deg, angle_lsb_over_budget,
%   accumulator_bits, leaves_headroom (logical)

c=299792458.0;
fc_hz=4.0e9;
baseline_m=0.025;
wavelength=c/fc_hz;
budget_deg=0.5;

bits=[8 10 12 13 14 16];
phase_lsb=2*pi*2.^(-bits);
angle_lsb=phase_lsb*wavelength/(2*pi*baseline_m)*180/pi;

% 4096 snapshots, Q15 samples, worst case every sample at full scale
input_lsb=2^-15;
worst_power=4096*(1/input_lsb)^2;
accumulator_bits=ceil(log2(worst_power))+1;

budget=struct();
budget.bits=bits;
budget.phase_lsb_rad=phase_lsb;
budget.angle_lsb_deg=angle_lsb;
budget.budget_deg=budget_deg;
budget.verdict=angle_lsb<budget_deg;
budget.accumulator_bits=accumulator_bits;
budget.accumulator_fits_int64=accumulator_bits<=63;

fprintf('phase quantisation at %.1f GHz on a %.0f mm baseline\n', ...
        fc_hz/1e9,baseline_m*1e3);
for index=1:numel(bits)
    if budget.verdict(index)
        verdict='inside 0.5 deg';
    else
        verdict='ABOVE 0.5 deg';
    end
    fprintf('  Q%-2d  lsb %.2e rad   %.4f deg   %s\n', ...
            bits(index),phase_lsb(index),angle_lsb(index),verdict);
end
fprintf('worst-case accumulator: %.1f bits (4096 x Q15 full scale) -> int64 %s\n', ...
        accumulator_bits,string(budget.accumulator_fits_int64));
end
