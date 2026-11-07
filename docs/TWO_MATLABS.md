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
| **`make mc`, `CHANNELIZER_FLOW=model_composer`** | **2022b, run directly in `-batch`** (not the launcher) | `xlGenerateButton` only exists once Model Composer's paths are added |

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

The GUI is not the deliverable — the IP is.

```bash
make mc-scratch  # 1. create the model from scratch (no GUI, R2022b, from text)
make mc-path     # the exact absolute path this checkout uses, and whether it exists
make mc          # 2. build the IP from it -- no argument needed
```

`make mc-gui` starts the GUI with `-sd build/mc_startup`, whose `startup.m` does
`addpath('<repo>/ip/model_composer/channelizer')` — so `mc_gui_build` exists in
that window without you typing an `addpath`. `make mc-gui-build` goes further and
runs the build on startup. To run a `.m` file from the shell instead:

```bash
matlab -batch "addpath('/abs/dir'); mc_gui_build"    # function, exits when done
matlab -batch "run('/abs/dir/script.m')"             # script file
matlab -r      "addpath('/abs/dir'); mc_gui_build"   # stays open
```

If MATLAB reports `There is no block named 'vmcUtilities/...'`, that is a
missing path, not a wrong name: a batch session has none of Model Composer's
library folders. `mc_paths.m` finds and adds them (cached in `build/mc_libs.txt`),
`make mc-libs` reports what it found, and when only the GUI can see the
libraries, `make mc-gui` followed by `mc_gui_build` in the Command Window runs
the very same builder and exporter.

The model is generated from `ip/model_composer/channelizer/make_channelizer_model.m`
(a `.slx` cannot be reviewed in a diff, so the builder script is what lives in
git). `make mc-example` downloads AMD's 2023.2 RFSoC SSR-DDC model into `build/`
for reference — never committed, that repository has no LICENSE file.

Which file? The one place `make mc` looks by itself:

```
<repo>/ip/model_composer/channelizer/channelizer.slx
```

A `.slx` is a binary built once in the GUI, so **no `.slx` is committed** (check:
`git ls-files '*.slx'` is empty).  `make mc` with no model prints that exact
path for your checkout, `make mc-find` lists every `.slx` on the machine with
its date and the command to use it, and `make mc-path` prints the resolved path
plus whether it exists. If the file lives elsewhere, name it:

```bash
make mc MODEL_COMPOSER_MODEL=/wherever/you/saved/channelizer.slx
```

Same stage as `make step05_channelizer CHANNELIZER_FLOW=model_composer
MODEL_COMPOSER_MODEL=...`.

**It does not go through the Model Composer launcher**, and a real run on this
machine is why ([evidence](evidence/2026-11-07-host-probe/model_composer_launcher_eval_bug.txt)):

```text
modelcomposerArgs.sh: eval: line 856: syntax error near unexpected token `('
...`exec matlab -batch addpath(pwd); export_model_composer_ip('...') -r "...;;xmcStart;"`
```

The launcher evals `exec matlab <your args> -r "<its startup>"`. Two
consequences:

1. a MATLAB statement passed after `-batch` loses its quotes before the eval, so
   the first space splits it and the first `(` is a shell syntax error;
2. the launcher always appends `-r`, and MATLAB refuses `-batch` with `-r`.

So the build runs **R2022b directly, in batch**, adding the directories the
launcher's own banner lists:

| from the banner | added to the MATLAB path |
|---|---|
| Model Composer Bin Dir `.../Model_Composer/2023.2` | `simulink`, `simulink/aie`, `simulink/hls`, `lib/lnx64.o[+/Ubuntu[/22]]`, `data/examples` |
| System Generator Bin Dir `.../Vivado/2023.2` | `scripts/sysgen/matlab`, `.../plugins/compilation`, `lib/lnx64.o/matlab`, `lib/classes/sysgen.jar` |

Steps inside `make mc`:

1. `MC_MODEL` = `MODEL_COMPOSER_MODEL`, or the single `.slx` in
   `ip/model_composer/channelizer/`; it must be a real file, so a placeholder
   path stops immediately.
2. `scripts/build_model_composer_ip.sh` checks `MATLAB_2022B` really is R2022b
   (from `VersionInfo.xml`, no licence), finds the Model Composer and Vivado
   roots, checks `scripts/sysgen/matlab` exists, then runs
   `matlab -batch "mc_batch_export('<model>')"`.
3. `mc_batch_export.m` adds the paths and `sysgen.jar`, calls `xmcStart` **only
   if** `xlGenerateButton` is still missing, then calls
   `export_model_composer_ip.m`: load the model, assert a *Xilinx System
   Generator* token exists, run the token (compile to IP Catalog), copy the
   newest `component.xml` to `$(IP_REPO)/model_composer_channelizer`.
4. The `verify` step fails the stage if that `component.xml` is missing or older
   than the model — a run that exits 0 without producing IP is still a failure.

Output is the same as any other stage: `build/logs/step05_channelizer.log`, a
stamp, and the tracked page `docs/progress/step05_channelizer.md`.

**Unproven until you run it:** whether `xlGenerateButton` is available in a
plain `-batch` session after those paths, or whether only `xmcStart` can
initialise Model Composer. The success line is `MC_EXPORT_OK`. If the log says
`xlGenerateButton is still unavailable`, no stamp is written and nothing
downstream moves — use the fallback below.

## Fallback: compile in the GUI once, then collect

```bash
make mc-gui                    # R2022b GUI, logged, launch page written
#   in the GUI: open the token, target IP Catalog, Generate
#   (or in the Command Window: export_model_composer_ip('/abs/path/model.slx'))
make mc-verify MODEL_COMPOSER_MODEL=/abs/path/model.slx
```

`make mc-verify` copies the `component.xml` the token left next to the model
(preferring `<model>_ip/`) into `$(IP_REPO)` and runs the same artifact check.

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
make mc MODEL_COMPOSER_MODEL=/abs/x.slx      # 6. 2022b, builds the IP (batch)
```

The `run_matlab_clean.sh` wrapper (used for the 2024a calls inside the stages)
bypasses a `$HOME/.matlab7rc.sh` that Model Composer installs; the Model
Composer launcher is run directly, because it needs its own startup file.
