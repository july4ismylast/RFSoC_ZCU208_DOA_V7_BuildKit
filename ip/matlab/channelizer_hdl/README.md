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
> The current Gate-2R experiment is:
>
> ```bash
> make -C ip/matlab/channelizer_hdl gate2r-bram
> cat build/output/v06_gate2r_bram_ooc_synthesis.rpt
> ```
>
> It resynthesizes the same Gate-1 RTL with only
> `AreaMapLargeShiftRegToBRAM` changed. Do not treat either one-channel
> PASS as integrated fit/timing proof.

Use DSP HDL Toolbox `dsphdl.Channelizer` rather than the simulation-oriented
`dsp.Channelizer` for synthesizable hardware. `build_model.m` now reads
the production values exported by `config.mk` (1024 bands, eight complex
samples/cycle, 12 taps/band, 100 dB stopband target, and
`CHANNELIZER_NORMALIZE=0`). It supplies an eight-element complex
`fixdt(1,16,15)` column vector per valid cycle and uses `tf()` to store
the 12,288 prototype coefficients as a model-workspace constant. The
legacy 64-band/four-lane configuration remains reproducible only by
explicit environment overrides. The HDL object uses a
direct-form-systolic polyphase filter and an output vector the same size
as the input; with `Normalize=false`, Gate 0 measured the output type as
signed 26-bit/fraction-24.

MATLAB R2024a does not support the `PreservePhase` property. This design does
not use it. Every antenna channel must use an identical channelizer; the
deterministic per-bin phase rotation is then common to all four receiver
channels and cancels in cross-channel phase and covariance measurements. Verify
this again in the four-channel HIL test.

SSR-8 at 250 MHz is the production-rate architecture choice, not a
timing proof. Gate 2 must still verify one-channel out-of-context
utilization and achieved clock rate for the ZCU208 part before any x4
extrapolation.

`Channelizer_DUT` is an explicit atomic Simulink Subsystem. Its internal
`ChannelizerCore` MATLAB System block contains the `dsphdl.Channelizer` object.
This hierarchy is required because `makehdl` accepts a model, subsystem, or
model reference as its DUT; it does not accept the leaf MATLAB System block as
the DUT path.

`make gate1` is the V06 HDL-generation entry point, `make gate2` is
the proved default-directive one-channel OOC baseline, and
`make gate2r-bram` is the current same-RTL BRAM shift-register A/B;
`make hdl` remains the underlying generation file-target form. Packaging is intentionally
blocked during V06 (`ALLOW_CHANNELIZER_PACKAGE=1` is required to unlock
the old package targets) because the generated DUT is still a raw
data/valid subsystem, not the frozen AXI4-Stream production wrapper.
Do not bypass that guard until the later wrapper stage. The packaging
Tcl remains available for that future stage and searches recursively
because R2024a writes files under
`hdl_prj/hdlsrc/zu48dr_channelizer_ip`.

The Makefile launches MATLAB through `scripts/run_matlab_clean.sh`. This keeps
the real user home and MATLAB licence configuration, copies MATLAB's factory
`bin/.matlab7rc.sh` into a temporary startup directory, bypasses a legacy
Xilinx-created `$HOME/.matlab7rc.sh`, and removes inherited loader/Qt variables
for that process. Copying the factory file is important because it initializes
the release-specific `ARCH` value. The wrapper prevents Linux `ld.so` TLS
assertions when MATLAB R2024a is invoked from a Vivado or Model Composer
configured shell, without modifying or deleting the user's startup file.
