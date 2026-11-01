# Four-channel, four-sample-per-clock covariance IP

`doa_covariance_4ch_v4` accepts one 512-bit AXI4-Stream beat per 128 MHz
clock. Each beat contains four time samples for each of four complex channels:

`word = lane*4 + channel`, with signed real in bits 15:0 and signed imaginary
in bits 31:16.

At RFDC 2.048 GSPS, decimation by four produces 512 MSPS per complex channel;
four samples per 128 MHz clock therefore preserve the complete stream. The IP
applies four complex Q2.14 calibration coefficients, accumulates 4096 samples,
and emits 16 signed 64-bit values: four powers, six cross-product real parts,
and six cross-product imaginary parts.

This is a frame processor: it sustains II=1 during a 1024-beat capture and then
emits a 16-beat result. Place a candidate-triggered capture gate/FIFO before it.
The always-on RFDC/PFB search path must not depend on backpressure from this
core. Restart the HLS transaction for each requested DOA frame.

The HLS script runs C simulation, synthesis, and IP export for
`xczu48dr-fsvg1517-2-e`. Its deterministic self-checking testbench requires an
exact match on all 16 covariance words and `TLAST` before synthesis. Treat the
design as verified only after its generated
`csynth` report and the containing Vivado implementation both meet timing.
