# MATLAB/DSP HDL SSR channelizer generation harness

> **Stage V06 status:** Gates 0 and 1 passed on MATLAB R2024a for one
> 1024-band / SSR-8 fixed-point `dsphdl.Channelizer` with
> `Normalize=false`, exact peak bin 192, signed 26-bit/fraction-24
> output, and 1760-cycle latency. HDL Coder generated the
> `Channelizer_DUT` top and 227 Verilog files with no HDL-check errors,
> warnings or messages. Gate-2 one-channel OOC synthesis returned
> script PASS at 4.0 ns (setup WNS +1.630 ns), but four systolic
> channels alone extrapolate to 83.27% of CLB LUTs. Hierarchy review
> found 55,952 SRLs inside the 63,439-LUT FilterBank and no BRAM use.
> Gate-2R then resynthesized the same RTL with
> `AreaMapLargeShiftRegToBRAM`; it completed with script PASS but
> exactly zero resource change, still 0 BRAM, so that route is closed.
> Gate-2T's isolated transposed A/B has now completed with
> `RESOURCE_IMPROVEMENT_MATERIAL=1`: 35,902 LUTs, 1,718 SRL LUTs,
> 58,626 registers, 176 RAMB36, 312 DSPs, 351-cycle latency, and setup
> WNS +1.829 ns for one channel. At x4 that is 143,608 LUTs
> (33.7679%) but 704/1080 BRAM tiles (65.1852%). The actual routed
> MTS base has now been extracted at 42,263 LUTs, 47,760 registers,
> 50.5 BRAM Tiles, 20 URAM and 3 DSPs; MTS + 4× transposed closes
> the crude arithmetic screen at 43.7056% LUTs and 69.8611% BRAM
> Tiles. The same screen with systolic would be 93.2089% LUTs, so
> transposed is the provisional Plan-A winner and systolic is not a
> credible integrated fallback. Gate-3 numerics are the next gate:
>
> ```bash
> make -C ip/matlab/channelizer_hdl gate3-transposed
> cat build/output/v06_gate3_transposed_numerics.rpt
> ```
>
> Do not treat one-channel OOC synthesis or crude MTS+x4 addition as
> integrated placement/routing/timing proof or production
> architecture selection.

Use DSP HDL Toolbox `dsphdl.Channelizer` rather than the simulation-oriented
`dsp.Channelizer` for synthesizable hardware. `build_model.m` now reads
the production values exported by `config.mk` (1024 bands, eight complex
samples/cycle, 12 taps/band, 100 dB stopband target,
`CHANNELIZER_NORMALIZE=0`, and
`CHANNELIZER_FILTER_STRUCTURE=systolic` by default). It supplies an
eight-element complex `fixdt(1,16,15)` column vector per valid cycle
and uses `tf()` to store the 12,288 prototype coefficients as a
model-workspace constant. The legacy 64-band/four-lane configuration
remains reproducible only by explicit environment overrides. The
wrapper passes the selected `Direct form systolic` or
`Direct form transposed` value to `dsphdl.Channelizer`; systolic is
the preserved Gate-2 baseline, while transposed has completed the
isolated Gate-2T A/B and is the provisional resource winner. It is not
yet the production default. The output vector is the same size as the input;
with `Normalize=false`, both the systolic Gate 0 and the transposed
probe measured the output type as signed 26-bit/fraction-24. Their
latencies differ: 1760 cycles systolic versus 351 cycles transposed.

MATLAB R2024a does not support the `PreservePhase` property. This design does
not use it. Gate 3 uses the documented 1023-zero sample alignment only as a
measurement construction and records the external per-bin phase correction
needed to match `dsp.Channelizer`. Every antenna channel must use an identical
channelizer; the deterministic per-bin phase rotation is then common to all
four receiver channels and cancels in cross-channel phase and covariance
measurements. Verify this again in the four-channel HIL test.

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
not overwrite baseline evidence. The next target is
`make gate3-transposed`, a MATLAB-only comparison of the exact
`ZU48DRChannelizer` wrapper against floating-point
`dsp.Channelizer`. It collects 40 snapshots, discards startup
snapshots, and must freeze serialized bin order, alignment, scaling
and common per-bin phase before production selection. `make hdl`
remains the underlying generation file-target form. Packaging is
intentionally blocked during V06
(`ALLOW_CHANNELIZER_PACKAGE=1` is required to unlock the old package
targets) because the generated DUT is still a raw data/valid
subsystem, not the frozen AXI4-Stream production wrapper. Do not
bypass that guard until Gate 3 selects the architecture and the
wrapper stage is reached. The existing packaging path still refers
to the baseline `hdl_prj/hdlsrc/zu48dr_channelizer_ip` tree;
transposed RTL is not a packaging candidate until Gate 3 passes and
the production generation/packaging path is changed coherently.

The Makefile launches MATLAB through `scripts/run_matlab_clean.sh`. This keeps
the real user home and MATLAB licence configuration, copies MATLAB's factory
`bin/.matlab7rc.sh` into a temporary startup directory, bypasses a legacy
Xilinx-created `$HOME/.matlab7rc.sh`, and removes inherited loader/Qt variables
for that process. Copying the factory file is important because it initializes
the release-specific `ARCH` value. The wrapper prevents Linux `ld.so` TLS
assertions when MATLAB R2024a is invoked from a Vivado or Model Composer
configured shell, without modifying or deleting the user's startup file.
