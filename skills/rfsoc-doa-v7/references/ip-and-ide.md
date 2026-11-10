# IP, toolchain and the IDEs

Condensed from `config/ip_versions.tcl`, `config.mk`, the per-IP Makefiles/Tcl, and
`docs/BLOCK_GUIDE.md` Part 6 (which is the click-by-click version). Quote this file for identities
and settings; quote Part 6 for menu paths.

## 1. The eight custom IPs

| IP | VLNV | produced by | project folder |
|---|---|---|---|
| covariance | `openai:doa:doa_covariance_4ch_v4:7.1` | Vitis HLS | `ip/custom/doa_covariance_4ch_v4/doa_covariance_4ch_v4_prj` |
| spectrum | `openai:doa:spectrum_power4:2.0` | Vitis HLS | `ip/custom/spectrum_power4/spectrum_power4_hls` |
| candidate | `openai:doa:candidate_peak4:1.0` | Vitis HLS | `ip/custom/candidate_peak4/candidate_peak4_hls` |
| beam | `openai:doa:beam_weight_4ch:2.1` | Vitis HLS | `ip/custom/beam_weight_4ch/beam_weight_4ch_hls` |
| repack | `openai:doa:rfdc_repack4:1.0` | Vitis HLS | `ip/custom/rfdc_repack4/rfdc_repack4_hls` |
| channelizer | `openai:doa:matlab_channelizer:7.0` | MATLAB + HDL Coder | `ip/matlab/channelizer_hdl/` |
| bridge | `openai:doa:doa_subband_bridge_4ch:1.0` | Vivado IP packager | `ip/custom/doa_subband_bridge_4ch/` |
| phase interferometer | `openai:doa:phase_interf_4ch:1.0` | Vitis HLS | `ip/custom/phase_interf_4ch/phase_interf_4ch_prj` |

Vendor and library are `CUSTOM_IP_VENDOR=openai`, `CUSTOM_IP_LIBRARY=doa`. Versions are pinned in
`config/ip_versions.tcl` and `config.mk`; `common/scripts/check_component_vlnv.sh` fails a stage that
exports anything else. Two catalog IPs matter most: `usp_rf_data_converter:2.6` and
`zynq_ultra_ps_e:3.5` (3.4 → 3.5 is the controlled upgrade recorded in stage V03).

## 2. Clocks and parts, per IP

| IP | part | clock constraint | why |
|---|---|---|---|
| covariance, spectrum, candidate, beam | `xczu48dr-fsvg1517-2-e` | 7.8125 ns (`PL_CLOCK_PERIOD_NS`) | DOA side runs at 125 MHz |
| repack4, phase_interf | same | 4.0 ns (`WIDEBAND_CLOCK_PERIOD_NS`) | 250 MHz wideband domain |
| bridge | same | 4.0 ns OOC gate in `package_ip.tcl` | 250 MHz, verified out of context |
| channelizer | same | 4.000 ns in `v06_gate2_ooc.xdc` | 250 MHz; the XDC refuses another period |

## 3. Build and package, per IP kind

**HLS kernels** — `ip/custom/<kernel>/Makefile`: `all: hls install`, where `hls` runs
`vitis_hls -f build_hls.tcl` (open_project → set_top → add_files → open_solution → set_part →
create_clock → config_export → `csim_design; csynth_design; export_design`) and `install` validates
`<project>/solution1/impl/ip/component.xml` against the pinned VLNV, then copies it to
`build/ip_repo/<kernel>/`.

**Bridge** — `make step05_subband_bridge` → `package_ip.tcl`: Python golden-model check, self-checking
XSim bench, 4.000 ns OOC synthesis gate, `ipx::package_project`, explicit
`ASSOCIATED_BUSIF`/`ASSOCIATED_RESET`/`ACTIVE_LOW` on `aclk`/`aresetn`, 4096-byte address block, then
a throw-away block-design smoke test.

**Channelizer** — `make step05_channelizer` (`CHANNELIZER_FLOW=matlab_hdl` default), which builds the
model with `build_model.m`, generates RTL with `generate_hdl.m`, and packages through
`package_generated_rtl.tcl` behind `ALLOW_CHANNELIZER_PACKAGE=1`.

## 4. Opening things in an IDE

| what | command |
|---|---|
| an HLS project | `vitis_hls -p ip/custom/<kernel>/<project>` |
| the built design | `vivado build/vivado/doa_v7_zcu208/doa_v7_zcu208.xpr &` |
| MATLAB for the channelizer | `matlab -sd ip/matlab/channelizer_hdl` |
| Vitis, after the XSA exists | `vitis -w build/vitis_ws &` |

Panes that matter: Vitis HLS — Explorer (`Project Settings`, `Source`, `Test Bench`, `solution1`),
toolbar **C SIMULATION** / **C SYNTHESIS** / **C/RTL COSIMULATION** / **EXPORT RTL**, the log
console at the bottom, and the Analysis perspective for II. Vivado — the Flow Navigator sections
(Project Manager, IP Integrator, RTL Analysis, Synthesis, Implementation, Program and Debug), plus
`Reports → Report Utilisation` / `Report Timing Summary`. MATLAB — the **HDL Coder** app's Workflow
Advisor. Vitis — platform from the XSA, then an application per domain.

Toolbar **PACKAGE** in Vitis HLS belongs to the Vitis-kernel flow; it is *not* how an IP reaches
`build/ip_repo`. That copy is the `install` make target.

## 5. Test benches, by tool

| bench | file | runs in |
|---|---|---|
| six kernel C benches | `ip/custom/<kernel>/tb/<kernel>_tb.cpp` | Vitis HLS csim (inside `build_hls.tcl`) |
| bridge | `ip/custom/doa_subband_bridge_4ch/tb/tb_doa_subband_bridge_4ch.sv` | XSim (inside `package_ip.tcl`) |
| channelizer wrapper | `ip/matlab/channelizer_hdl/tb_channelizer_axis_wrapper*.sv` | XSim (`make -C ip/matlab/channelizer_hdl gate4-axis-wrapper-sim`) |
| channelizer model equivalence | `ip/model_composer/channelizer/testbench/compare_hdl_vs_model.py` | host python (`make ip-equivalence`) |
| step benches | `stepN_*/testbench/run_testbench.py` | host python (`make steps`) |

## 6. The Vitis side, honestly

There is **no Vitis project in the repository**. What exists is the XSA
(`build/output/doa_v7_zcu208.xsa`), the firmware sources (`firmware/amc_r5/amc.c`, `amc_model.h`), the
estimator (`step3_r5_doa/c/doa_core.c`), and the A53 supervisor (`step6_ps_linux/c/supervisor.cpp`),
which is built by its own Makefile (`make -C step6_ps_linux/c`, and `cross` for aarch64 with the
PetaLinux SDK). Creating the platform and applications is a documented procedure, not a recorded
result — G8b is open for exactly that reason.

## 7. What the assistant must not do with this file

- Do not invent versions; if a user has a different one, the pinned table is the contract and
  `check_component_vlnv.sh` is the enforcer.
- Do not describe the 7.8125 ns constraint as a 128 MHz clock.
- Do not claim the bridge or channelizer was exported by Vitis HLS: the bridge is packaged RTL, the
  channelizer comes from HDL Coder.
- Do not promise a GUI path that the repository's scripts do not mirror; the scripted `make` recipe wins.
