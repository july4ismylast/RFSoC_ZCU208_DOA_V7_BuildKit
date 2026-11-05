# MATLAB/DSP HDL SSR channelizer generation harness

> **Stage V06 status:** Transposed Gates 0T, 1T, 2T, 3, 4 (OOC synth),
> 4B (handshake/framing sim), and **4C (bit-exact 416-bit RTL payload compare
> against MATLAB fixed-point golden)** have all passed on the user PC
> (`docs/debug-logs/20261105T150522Z-matlab_hdl/v06_gate4_axis_wrapper_rtl_sim.rpt`,
> commit `ac06c70`). `package_generated_rtl.tcl` now packages
> `channelizer_axis_wrapper.sv` + `Channelizer_DUT.v` (228 transposed files)
> as `openai:doa:matlab_channelizer:7.0` (`step05_channelizer` /
> `gate5-package`), reusing existing `hdl_prj/hdlsrc_transposed` RTL when
> already generated. Four-channel stream adaptation to `/doa_v7` is provided
> by `ip/custom/doa_subband_bridge_4ch` (`step05_subband_bridge`), and
> ZCU208 MTS Block Design wiring is implemented in `config/zcu208_bd_map.tcl`
> (`INTEGRATION_MODE=mapped`).

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
not overwrite baseline evidence. Gate 3 (`make gate3-transposed`), Gate 4 OOC synthesis (`make gate4-axis-wrapper`),
Gate 4B handshake/framing simulation (`make gate4-axis-wrapper-sim`), and Gate 4C
exact payload comparison (`make gate4-axis-wrapper-rtl-sim`) have all passed.
`make package` (or `make gate5-package` / `make step05_channelizer`) packages
`channelizer_axis_wrapper.sv` together with `Channelizer_DUT.v` and its 227
submodules as `openai:doa:matlab_channelizer:7.0` and smoke-tests BD
instantiation + VHDL target generation. `make hdl` reuses existing generated
RTL when present; `make hdl-regen` forces MATLAB HDL regeneration.

The Makefile launches MATLAB through `scripts/run_matlab_clean.sh`. This keeps
the real user home and MATLAB licence configuration, copies MATLAB's factory
`bin/.matlab7rc.sh` into a temporary startup directory, bypasses a legacy
Xilinx-created `$HOME/.matlab7rc.sh`, and removes inherited loader/Qt variables
for that process. Copying the factory file is important because it initializes
the release-specific `ARCH` value. The wrapper prevents Linux `ld.so` TLS
assertions when MATLAB R2024a is invoked from a Vivado or Model Composer
configured shell, without modifying or deleting the user's startup file.
