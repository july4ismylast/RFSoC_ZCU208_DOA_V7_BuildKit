# RFSoC_ZU48DR_BuildKit overlay

Copy `ip/custom/doa_covariance_4ch_v4` into the matching `ip/custom` directory
of the supplied build kit. Add
`$(MAKE) -C ip/custom/doa_covariance_4ch_v4 all` to its `custom-ips` target.

Place the core behind a candidate-triggered 4096-sample capture gate/FIFO. It
is not an always-on replacement for the continuous PFB/search stream: it
accepts the requested frame at II=1 and then emits its 16-word packet.

This is the V7 HLS-ready streaming calibration and covariance front end. It
consumes one 512-bit AXI beat containing four time lanes for four complex signed
16-bit channels. At 128 MHz, the four lanes sustain 512 MSPS/channel after the
documented RFDC decimation. It accumulates 4096 samples without frame RAM and
emits the 16 unique covariance quantities as signed 64-bit AXI beats:

1. four channel powers;
2. real parts of pairs 01, 02, 03, 12, 13, 23;
3. imaginary parts of those six pairs.

Calibration coefficients are packed complex Q2.14 (`real[15:0]`,
`imag[31:16]`). Input word index is `lane*4+channel`. WPI, bounded local ML/GN
and the unit-vector EKF run on the processor at one update per covariance frame;
they can move later without changing this compact interface. The legacy
128-bit scalar core remains only as a compatibility reference and cannot by
itself sustain the documented four-sample-per-clock boundary.

This overlay has not been synthesized in this environment. Run Vitis HLS and
Vivado 2023.2 in the user's verified ZCU208 RFDC/MTS shell before treating any
resource or timing estimate as final.
