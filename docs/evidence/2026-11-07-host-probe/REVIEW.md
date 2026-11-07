# 2026-11-07 — host probe from the user's PC

**What this file is.** The output of `make tools` on the machine that will run
the gates, pasted by the user on 2026-11-07. It is the first evidence in this
repository that is about a *real* tool installation rather than the authoring
container.

**What it proves.**

| fact | consequence |
|---|---|
| Vivado 2023.2, Vitis HLS 2023.2, Vitis 2023.2 installed, on PATH | G2/G3/G4 are now blocked only by inputs, not by tools |
| `XILINX_VIVADO` and `XILINX_HLS` set | the Makefile defaults (`vivado`, `vitis_hls`) resolve |
| Model Composer 2023.2 at a known path, with MATLAB R2022b | `step05_channelizer CHANNELIZER_FLOW=model_composer` is runnable (2022b only) |
| MATLAB R2024a at `/usr/local/bin/matlab` | preflight, step14 and G8b use it (see `docs/TWO_MATLABS.md`) |
| `armr5-none-eabi-gcc` 12.2.0 (PetaLinux xsct) | the R5 link for G8b exists |
| numpy 1.21.5 / matplotlib 3.5.1 / python 3.10 | `make steps` and `make diagram` are inside their support range |
| `BASE_XPR` **does not exist** | G4 cannot start until stage V03 builds the MTS base |

**What it does NOT prove.** Nothing about a build, a synthesis, a bitstream, an
R5 cycle count or a capture. Every gate stays open until its own log exists —
that is the rule the diagram badges follow. `make tools` is a *map of the
machine*, not a measurement of the design.

**What it changed in the repository.** Two MATLABs are now first class:
`MODEL_COMPOSER` and `MATLAB_2022B` in `config.mk` (and `config.local.mk`, which
is not tracked), the Model Composer Makefile refuses to fall back to 2024a, the
tools probe reads each install's release from `VersionInfo.xml` without taking a
licence, and `build_amc_r5.m` falls back across device types instead of dying on
a missing support package.
