# MATLAB/DSP HDL four-lane channelizer generation harness
Use DSP HDL Toolbox `dsphdl.Channelizer` rather than the simulation-oriented
`dsp.Channelizer` for synthesizable hardware. The generated model supplies a
four-element complex `fixdt(1,16,15)` column vector per valid cycle and a scalar
Boolean valid signal. `build_model.m` uses `dsp.Channelizer` at model-build time
to create a 64-band, 12-taps-per-band prototype with 80 dB stopband attenuation,
then stores those 768 coefficients as a constant in the model workspace. The
HDL object uses a direct-form-systolic polyphase filter, a four-sample streaming
output, and normalized FFT stages.

MATLAB R2024a does not support the `PreservePhase` property. This design does
not use it. Every antenna channel must use an identical channelizer; the
deterministic per-bin phase rotation is then common to all four receiver
channels and cancels in cross-channel phase and covariance measurements. Verify
this again in the four-channel HIL test.

The four-sample input is an architecture choice, not a timing proof. Verify the
generated utilization, latency, and achieved clock rate for the ZCU208 build.

`Channelizer_DUT` is an explicit atomic Simulink Subsystem. Its internal
`ChannelizerCore` MATLAB System block contains the `dsphdl.Channelizer` object.
This hierarchy is required because `makehdl` accepts a model, subsystem, or
model reference as its DUT; it does not accept the leaf MATLAB System block as
the DUT path.

`make hdl` generates RTL. `make package TOP=<actual_generated_top>` packages
the generated RTL. The HDL top can differ by MATLAB release, so inspect
`hdl_prj/hdlsrc` before packaging.

The local Makefile tracks the generated top RTL and packaged `component.xml`
as real file targets. If HDL generation succeeds but Vivado packaging fails,
fix the Tcl and run `make package` or `make package-only`; the existing RTL is
reused. The packaging Tcl searches recursively because R2024a writes files
under `hdl_prj/hdlsrc/zu48dr_channelizer_ip`.

The Makefile launches MATLAB through `scripts/run_matlab_clean.sh`. This keeps
the real user home and MATLAB licence configuration, copies MATLAB's factory
`bin/.matlab7rc.sh` into a temporary startup directory, bypasses a legacy
Xilinx-created `$HOME/.matlab7rc.sh`, and removes inherited loader/Qt variables
for that process. Copying the factory file is important because it initializes
the release-specific `ARCH` value. The wrapper prevents Linux `ld.so` TLS
assertions when MATLAB R2024a is invoked from a Vivado or Model Composer
configured shell, without modifying or deleting the user's startup file.
