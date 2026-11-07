# Two MATLABs, one kit — which command uses which

This machine has **MATLAB 2024a on the command line** and **MATLAB 2022b for
Model Composer**, and Model Composer 2023.2 only runs with 2022b. That is not a
problem to work around; it is a fact to encode. This page says which command
uses which install, and where to put the paths.

## The rule

| what you run | which MATLAB | why |
|---|---|---|
| `make step00_preflight` | `matlab` on `PATH` (2024a) | it only checks that MATLAB exists |
| `make tools MATLAB=1` | 2024a | it lists the toolboxes the codegen needs |
| `make step14_hil_vectors` | 2024a | `hil/matlab/generate_zcu208_hil_vectors.m`, no Model Composer |
| `matlab_v7/build_amc_r5.m` (G8b) | 2024a | `coder.config('lib')` + `GenCodeOnly`; the ARM build is `armr5-none-eabi-gcc` |
| `matlab_v7/verify_amc_vectors.m` | 2024a | pure MATLAB, no toolbox beyond Embedded Coder's tables |
| `make step05_channelizer CHANNELIZER_FLOW=matlab_hdl` | 2024a | HDL Coder (`dsphdl.Channelizer`) |
| **`make step05_channelizer CHANNELIZER_FLOW=model_composer`** | **2022b, through the Model Composer launcher** | `xlGenerateButton` only exists inside Model Composer |

The channelizer is the **only** stage that needs 2022b. Everything else — the
whole G2 chain, G3, G4, the codegen, the studies — uses the command-line 2024a.

## The two steps at a command prompt

This is the sequence that works on the ZCU208 host, verbatim:

```bash
# step 1 -- put MATLAB R2022b first on PATH, so "matlab" means R2022b
export PATH="/media/joshua/Linux/Programs/R2022b/bin:$PATH"

# step 2 -- start the Model Composer 2023.2 GUI (R2022b is already on PATH)
/media/joshua/Linux/Programs/X20232/Model_Composer/2023.2/bin/model_composer \
    2>&1 | tee build/output/v06_model_composer_launch.log
```

Check step 1 took effect before step 2 — `command -v matlab` must print the
R2022b path. If it still prints `/usr/local/bin/matlab`, step 2 starts the GUI
on R2024a and the export fails later with `xlGenerateButton unavailable`.

That pair only **opens the GUI**. It is needed once, to create or edit the
`.slx`; `make mc-gui` does exactly those two steps from `config.mk`, refuses to
start if `matlab` still resolves to another release, and writes
`docs/progress/model_composer_launch.md`.

## The build (what `make mc` does)

The GUI is not the deliverable — the IP is. To build:

```bash
make mc MODEL_COMPOSER_MODEL=/absolute/path/channelizer.slx
```

which is the same stage as:

```bash
make step05_channelizer CHANNELIZER_FLOW=model_composer \
     MODEL_COMPOSER_MODEL=/absolute/path/channelizer.slx
```

Steps inside:

1. `MC_MODEL` = `MODEL_COMPOSER_MODEL`, or the single `.slx` in
   `ip/model_composer/channelizer/`; it must exist, otherwise the target stops.
2. `ip/model_composer/channelizer/Makefile` puts the R2022b `bin/` first on
   `PATH` and runs `model_composer -batch "addpath(pwd);
   export_model_composer_ip('<model>')"` — **batch**, no GUI.
3. `export_model_composer_ip.m` loads the model, asserts a *Xilinx System
   Generator* token exists and that `xlGenerateButton` is available, runs the
   token (System Generator compiles the design to IP Catalog with Vivado), then
   copies the newest `component.xml` to `$(IP_REPO)/model_composer_channelizer`.
4. A `verify` step fails the stage if that `component.xml` is missing or older
   than the model — a launcher that exits 0 without producing IP is still a
   failure.

The build therefore produces, exactly like the other stages: `build/logs/`
`step05_channelizer.log`, a stamp, and the tracked page
`docs/progress/step05_channelizer.md`.

## How to set the paths

`config.mk` already carries this workstation's two paths (tracked, so a fresh
clone on the same host works without setup):

```make
MATLAB_2022B   ?= /media/joshua/Linux/Programs/R2022b/bin/matlab
MODEL_COMPOSER ?= /media/joshua/Linux/Programs/X20232/Model_Composer/2023.2/bin/model_composer
```

A different machine overrides them in `config.local.mk` (not tracked, see
`.gitignore`; use plain `=`, and the command line always wins):

```make
# config.local.mk
MATLAB         = /usr/local/bin/matlab
MATLAB_2022B   = /opt/MATLAB/R2022b/bin/matlab
MODEL_COMPOSER = /opt/Model_Composer/2023.2/bin/model_composer
```

or per command:

```bash
make step05_channelizer CHANNELIZER_FLOW=model_composer \
     MODEL_COMPOSER=/media/joshua/Linux/Programs/X20232/Model_Composer/2023.2/bin/model_composer \
     MODEL_COMPOSER_MODEL=/abs/path/to/your_channelizer.slx
```

`ip/model_composer/channelizer/Makefile` decides like this:

1. `MODEL_COMPOSER` set and executable → run **the Model Composer launcher**
   (it puts the MC / System Generator paths on the MATLAB path);
2. else `MATLAB_2022B` set → run `run_matlab_clean.sh "<that matlab>"`;
3. else → **stop** with the exact command to copy. It never silently uses 2024a,
   because the failure mode there is `xlGenerateButton is unavailable` three
   minutes into a build.

`make tools` prints both installs and their release, read from
`<matlabroot>/VersionInfo.xml`, so it costs no licence:

```
=== Model Composer  (its own MATLAB: 2022b in this kit)
  MODEL_COMPOSER             /media/.../Model_Composer/2023.2/bin/model_composer
    exists                   yes, Model Composer 2023.2
  MATLAB_2022B               /path/to/R2022b/bin/matlab
    release                  R2022b
```

## The toolbox question, answered by one command

```bash
make tools MATLAB=1
```

It starts MATLAB once (a licence checkout, ~40 s) and prints an explicit verdict
per product the codegen needs:

```
  [ok]   MATLAB Coder
  [ok]   Simulink
  [MISS] Simulink Coder
  [ok]   Embedded Coder
  [ok]   Fixed-Point Designer
  [ok]   HDL Coder
  ...
  all products: ... (the full list, in one line)
```

If `Simulink Coder` is `[MISS]`, `build_amc_r5.m` still has a path: the script
uses `coder.config('lib')` with `GenCodeOnly`, i.e. MATLAB Coder's library
configuration. `Simulink Coder` is only needed for the Simulink-model route.

## "Embedded Coder Support Package for ARM Cortex-R Processors"

This is **not** required for gate G8b, and it is usually missing. It adds
on-target deployment and processor-in-the-loop, i.e. code generation *and
running it on the R5 from MATLAB*. G8b only needs the C sources:

* `build_amc_r5.m` targets the generic device description
  `ARM Compatible->ARM Cortex-R` with `coder.config('lib')`,
* the ARM build itself is `armr5-none-eabi-gcc -mcpu=cortex-r5
  -mfloat-abi=hard -mfpu=vfpv3-d16 -O2`, which is already on this machine
  (`/home/joshua/Programs/peta20232/PetaLinux/2023.2/tools/xsct/gnu/armr5/.../`).

If a release refuses the device type, `build_amc_r5.m` now falls back in order
(`ARM Compatible->ARM Cortex-R` → `ARM Compatible->ARM Cortex` → generic 32-bit)
and prints which one it used, instead of stopping the build.

## The order that matters

```bash
make tools MATLAB=1                       # 1. both MATLABs + every toolbox, once
make steps                                # 2. 43 host checks, no licence
make step14_hil_vectors                   # 3. 2024a, HIL vectors
matlab -batch "cd matlab_v7; build_amc_r5"   # 4. 2024a, G8b
make hls-all                              # 5. 2023.2 HLS, all seven kernels
make step05_channelizer CHANNELIZER_FLOW=model_composer \
     MODEL_COMPOSER=... MODEL_COMPOSER_MODEL=...   # 6. 2022b, the only 2022b step
```

The `run_matlab_clean.sh` wrapper (used for the 2024a calls inside the stages)
bypasses a `$HOME/.matlab7rc.sh` that Model Composer installs; the Model
Composer launcher is run directly, because it needs its own startup file.
