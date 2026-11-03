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
> The current Gate-2T experiment is the isolated transposed A/B:
>
> ```bash
> make -C ip/matlab/channelizer_hdl probe-transposed
> cat build/output/v06_channelizer_probe_transposed.rpt
> make -C ip/matlab/channelizer_hdl gate1-transposed
> cat build/output/v06_gate1_hdl_generation_transposed.rpt
> make -C ip/matlab/channelizer_hdl gate2t-transposed
> cat build/output/v06_gate2t_transposed_ooc_synthesis.rpt
> ```
>
> Run them in that order and stop on the first failure. On the user
> PC the transposed probe has already passed with 351-cycle latency;
> Gate-1 attempt 1 then exposed that R2024a will not resolve a
> model-workspace variable for the finite-option `FilterStructure`
> mask parameter, and attempt 2 exposed that Simulink code generation
> rejects a string array in the wrapper validator. Attempt 3 generated
> the transposed HDL cleanly (0 errors/warnings/messages) but the new
> Gate-1 port-width regex missed HDL Coder's trailing `// sfix...`
> comments. `build_model.m` now passes the exact selected option
> directly, the validator uses a cell array of character vectors, and
> the port patterns allow those comments; after pulling those
> corrections resume at `gate1-transposed` rather than rerunning the
> probe. Do not treat a
> one-channel PASS as integrated fit/timing proof or production
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
`Direct form transposed` value to `dsphdl.Channelizer`; only systolic
has completed Gate-1/Gate-2, while transposed is currently restricted
to the Gate-2T A/B. The output vector is the same size as the input;
with `Normalize=false`, both the systolic Gate 0 and the transposed
probe measured the output type as signed 26-bit/fraction-24. Their
latencies differ: 1760 cycles systolic versus 351 cycles transposed.

MATLAB R2024a does not support the `PreservePhase` property. This design does
not use it. Every antenna channel must use an identical channelizer; the
deterministic per-bin phase rotation is then common to all four receiver
channels and cancels in cross-channel phase and covariance measurements. Verify
this again in the four-channel HIL test.

SSR-8 at 250 MHz is the production-rate architecture choice. Gate 2
has verified one systolic channel out-of-context at 4.0 ns on the
ZCU208 part, but that is still not integrated four-channel fit, routed
timing, hold, congestion or power proof.

`Channelizer_DUT` is an explicit atomic Simulink Subsystem. Its internal
`ChannelizerCore` MATLAB System block contains the `dsphdl.Channelizer` object.
This hierarchy is required because `makehdl` accepts a model, subsystem, or
model reference as its DUT; it does not accept the leaf MATLAB System block as
the DUT path.

`make gate1` is the systolic V06 HDL-generation entry point,
`make gate2` is the proved default-directive one-channel OOC baseline,
and `make gate2r-bram` is retained only as the completed zero-change
BRAM-directive record. The current sequence is
`make probe-transposed`, `make gate1-transposed`, then
`make gate2t-transposed`; those targets use separate
`*_transposed` reports and `hdl_prj/hdlsrc_transposed/` RTL so they do
not overwrite baseline evidence. `make hdl` remains the underlying
generation file-target form. Packaging is intentionally blocked during
V06 (`ALLOW_CHANNELIZER_PACKAGE=1` is required to unlock the old
package targets) because the generated DUT is still a raw data/valid
subsystem, not the frozen AXI4-Stream production wrapper. Do not
bypass that guard until an architecture is selected and the wrapper
stage is reached. The existing packaging path still refers to the
baseline `hdl_prj/hdlsrc/zu48dr_channelizer_ip` tree; transposed RTL
is not a packaging candidate unless Gate 2T and the later reviews
select it.

The Makefile launches MATLAB through `scripts/run_matlab_clean.sh`. This keeps
the real user home and MATLAB licence configuration, copies MATLAB's factory
`bin/.matlab7rc.sh` into a temporary startup directory, bypasses a legacy
Xilinx-created `$HOME/.matlab7rc.sh`, and removes inherited loader/Qt variables
for that process. Copying the factory file is important because it initializes
the release-specific `ARCH` value. The wrapper prevents Linux `ld.so` TLS
assertions when MATLAB R2024a is invoked from a Vivado or Model Composer
configured shell, without modifying or deleting the user's startup file.
