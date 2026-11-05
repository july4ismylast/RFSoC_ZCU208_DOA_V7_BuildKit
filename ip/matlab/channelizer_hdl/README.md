# MATLAB/DSP HDL SSR channelizer generation harness

> **Stage V06 status:** Transposed Gates 0T/1T/2T/3T passed on the
> user PC (MATLAB R2022b). Gate 3 matched all 16 test bins in natural
> order; with the documented phase correction, steady-state NRMSE was
> 0.000183, correlation 0.999999983, global gain magnitude 1.00000205
> and phase −0.0002925°. Transposed is selected as the Plan-A core and
> `config.mk` default (one channel: 35,902 LUTs, 176 RAMB36, 351-cycle
> latency in Gate 2T). This is **not** packaged IP or a bitstream: the
> generated core has raw vector/data-valid ports. The isolated AXI4-Stream
> wrapper candidate passed Gate-4 OOC synthesis (0 errors; 232 warnings,
> including missing OOC `HD.CLK_SRC` timing context). Gate-4B XSim
> handshake/framing verification is the next gate. Packaging, four-channel
> mapping, and routed implementation remain unfinished. Gate-3 evidence is
> committed at `docs/debug-logs/20261105T134543Z-matlab_hdl/`; Gate-4
> evidence is at `docs/debug-logs/20261105T141754Z-matlab_hdl/`.

Use DSP HDL Toolbox `dsphdl.Channelizer` rather than the simulation-oriented
`dsp.Channelizer` for synthesizable hardware. `build_model.m` now reads
the production values exported by `config.mk` (1024 bands, eight complex
samples/cycle, 12 taps/band, 100 dB stopband target,
`CHANNELIZER_NORMALIZE=0`, and
`CHANNELIZER_FILTER_STRUCTURE=transposed` by default). It supplies an
eight-element complex `fixdt(1,16,15)` column vector per valid cycle
and uses `tf()` to store the 12,288 prototype coefficients as a
model-workspace constant. The legacy 64-band/four-lane configuration
remains reproducible only by explicit environment overrides. The
wrapper passes the selected `Direct form systolic` or
`Direct form transposed` value to `dsphdl.Channelizer`; systolic is
the preserved Gate-2 baseline, while transposed passed Gate 2T and Gate 3
and is selected as the Plan-A core/default. An isolated wrapper candidate is
implemented; packaging remains blocked until its handshake/frame behavior is
verified and the package path is validated. The output vector is the same size as the input;
with `Normalize=false`, both the systolic Gate 0 and the transposed
probe measured the output type as signed 26-bit/fraction-24. Their
latencies differ: 1760 cycles systolic versus 351 cycles transposed.

Gate 3 records the `dsphdl.Channelizer` phase relation against
`dsp.Channelizer` using the documented 1023-zero sample alignment as a
measurement construction. No production phase correction is selected here.
Every antenna channel must use an identical channelizer; the deterministic
per-bin phase rotation is common to all four receiver channels and cancels in
cross-channel phase/covariance measurements, but this must be verified again
in the four-channel HIL test.

SSR-8 at 250 MHz is the production-rate architecture choice. Gate 2
and Gate 2T have each verified one channel out-of-context at 4.0 ns on
the ZCU208 part (systolic WNS +1.630 ns; transposed +1.829 ns), but
that is still not integrated four-channel fit, routed timing, hold,
congestion or power proof.

`Channelizer_DUT` is an explicit atomic Simulink Subsystem. Its internal
`ChannelizerCore` MATLAB System block contains the `dsphdl.Channelizer` object.
This hierarchy is required because `makehdl` accepts a model, subsystem, or
model reference as its DUT; it does not accept the leaf MATLAB System block as
the DUT path.

`make gate1` is the systolic V06 HDL-generation entry point,
`make gate2` is the proved default-directive one-channel OOC baseline,
and `make gate2r-bram` is retained only as the completed zero-change
BRAM-directive record. The completed transposed resource sequence was
`make probe-transposed`, `make gate1-transposed`, then
`make gate2t-transposed`; those targets use separate
`*_transposed` reports and `hdl_prj/hdlsrc_transposed/` RTL so they do
not overwrite baseline evidence. Gate 3 (`make gate3-transposed`) has passed: it compared the exact
`ZU48DRChannelizer` wrapper against floating-point `dsp.Channelizer`,
collected 40 snapshots, discarded startup snapshots, and froze the tested
bin order/alignment/scaling/phase relation. Gate 4 OOC synthesis has now
passed. The next runnable step is wrapper behavior verification:
`make debug-channelizer-gate GATE=gate4-axis-wrapper-sim`. It captures the
XSim transcript and Gate-4B report in the standard debug snapshot and locally
commits it for GitHub Desktop Push origin. Gate 4B checks backpressure hold
and TLAST framing; package validation, four-channel BD integration, and
routed timing remain later work. `make hdl` remains the underlying generation
file-target form.
Packaging remains intentionally blocked; do not set
`ALLOW_CHANNELIZER_PACKAGE=1` to bypass the guard. The package target follows
the selected structure's HDL directory (transposed by default), but that raw
core is not itself a production IP candidate.

The Makefile launches MATLAB through `scripts/run_matlab_clean.sh`. This keeps
the real user home and MATLAB licence configuration, copies MATLAB's factory
`bin/.matlab7rc.sh` into a temporary startup directory, bypasses a legacy
Xilinx-created `$HOME/.matlab7rc.sh`, and removes inherited loader/Qt variables
for that process. Copying the factory file is important because it initializes
the release-specific `ARCH` value. The wrapper prevents Linux `ld.so` TLS
assertions when MATLAB R2024a is invoked from a Vivado or Model Composer
configured shell, without modifying or deleting the user's startup file.
