# Model Composer / System Generator channelizer route

An alternative to `ip/matlab/channelizer_hdl`, not another datapath copy.

## There is no `.slx` in this directory, on purpose

A `.slx` is a zip of XML plus binary arrays: it cannot be reviewed, diffed, or
merged. So the model for this kit is **code**:

| file | what it is |
|---|---|
| `make_channelizer_model.m` | builds the model from nothing: `new_system`, `add_block`, `add_line`, `save_system` |
| `channelizer.slx` | the result, generated — not committed |
| `mc_batch_export.m` | runs inside MATLAB R2022b, adds the Model Composer paths, exports the IP |
| `export_model_composer_ip.m` | finds the generate block, asks for IP Catalog, copies `component.xml` |

## What a real run taught this builder (2026-11-07, ZCU208 host)

The first run in a live Model Composer GUI got as far as saving the model, then
stopped with:

```
Target hardware is not selected.  Please select the target hardware in the
'Hardware Selection' tab of the Vitis Model Composer Hub block.
```

Setting `part` alone is not enough — the Hub needs the whole device identity, the
same set a working 2023.2 model carries:

| Hub parameter | value here | where it comes from |
|---|---|---|
| `ProjDevice`, `ProjDevicePart` | `xczu48dr-fsvg1517-2-e` | `PART` in `config.mk` |
| `part` / `package` / `speed` | `xczu48dr` / `fsvg1517` / `-2-e` | parsed from `PART` |
| `xilinxfamily` | `zynquplus` | derived from the device |
| `ExportType` | `IP Catalog` | chosen from the popup's own options |
| `IpVendor` / `IpLibrary` / `IpVersion` | `doa.v7` / `model_composer` / `1.0` | fixed |
| `IPInfoJsonString` | `{"HDLSubsystem":{...}}` | names the generated IP |

`MC_PART` is how the device gets in: the Makefile passes `$(PART)` to
`make mc-scratch` and to the GUI launcher, which writes it into `startup.m`.

Two smaller things the same run exposed, both fixed:

* `arith_type = Signed (2's comp)` was rejected.  Popup values are not guessed
  any more: `applyPopup` reads the block's mask options and picks the entry that
  matches `Signed`, printing the full option list when nothing does.
* `Gateway Out` has no `period` parameter — that call is gone.

## Guards, because two runs were lost to bugs in the glue

The model work was right long before the export worked; the failures were in the
small helpers around it (`strjoin` on a numeric argument, a Hub field left
empty). Those cannot be exercised without Model Composer, but the helpers can:

`mc_gui_build` now runs `mc_selftest` first -- one second, no toolbox:

```
MC_SELFTEST_OK
```

It checks the part parser (`xczu48dr-fsvg1517-2-e` → device/package/speed/family),
the argument formatter used for log lines, and that the generate-entry discovery
returns a usable name and list. On failure it prints `MC_SELFTEST_FAILED` and the
failing check, so a helper bug no longer waits for a full rebuild to appear.

## Root cause found: `SubsystemName` and `IpName` were empty

`help xmcGenerate` (protected `.p`, but its help is readable) settled the
argument question:

```
xmcGenerate('MyModel')                              % uses the Hub block settings
status = xmcGenerate('MyModel', 'MyModel_hubInfo.json')
status = xmcGenerate('MyModel', 'closeProgressWindow', 1)
```

and the Hub dump from the same run named the culprit:

```
EMPTY  SubsystemName
EMPTY  IpName
```

`IPInfoJsonString` was correct, but the Hub keeps `SubsystemName` and `IpName`
as their own parameters, and `xmcGenerate` indexes the (empty) cell it builds
from them: *Index exceeds the number of array elements.*  `configureHub` now
writes

```matlab
set_param(hub, 'SubsystemName', 'channelizer_dut');
set_param(hub, 'IpName',        'channelizer_dut');
```

and the call is `xmcGenerate(model, 'closeProgressWindow', 1)`, because a failed
run left a wait box open ("Close Wait Box due to exception") that blocked the
next attempt -- `mc_call_generator` now closes it before retrying, prints the
returned `status`, and skips printing the binary contents of `.p` files in the
source window.

## `xmcGenerate('channelizer')` is the documented call, and it went inside AMD's code

UG1259 shows exactly the call this builder makes:

```matlab
open_system('MoC_design');
xmcGenerate('MoC_design');
```

On the real install it failed with:

```
calling xmcGenerate(channelizer)
  xmcGenerate failed: Index exceeds the number of array elements. Index must not exceed 0.
calling xmcGenerate(channelizer, ExportType, IP Catalog)
  xmcGenerate failed: 'ExportType' is not a recognized parameter.
```

Nothing in that message names a parameter, so the builder now does three things
instead of guessing:

1. **Sets what a real Generate sets first.** The example Hub ships with
   `CodeGeneration = off` and `TargetDirectory = ./code`; both are written before
   generating (`CodeGeneration = on`).
2. **Focuses the model** (`open_system` + `set(0,'CurrentFigure',handle)`), then
   tries the entry points in order: the model-named API call, then
   `xlGenerateButton()` with **no arguments** (that is how the GUI button behaves:
   it acts on the current figure), then the rest.
3. **Reports, when all fail**: every Hub parameter with the empty ones flagged, the
   source window around the line that raised the index error
   (`mc_source_context`), and the entry point's own `help` text. One run then
   answers "which field is empty" instead of producing another symptom.

## The template route works, and the API is `xmcGenerate`

With the Hub taken from AMD's example the model builds cleanly and the update
passes -- no more "Target hardware is not selected".  What the run then showed:

```
generate block: channelizer/Vitis Model Composer Hub
export target:  IP Catalog
generate entry: xmcGenerate: yes        <- the supported API
Warning: the System Generator block and xlGenerateButton API are deprecated
         and no longer supported. Use the Vitis Model Composer hub block and
         xmcGenerate API.
ERROR: No block diagram name specified.   (from xlGenerateButton, via xlFindSgFig)
```

Two mistakes of mine, both fixed:

| mistake | fix |
|---|---|
| I tried `xlGenerateButton` first (it existed, so it won) | `mc_generate_function` now prefers **`xmcGenerate`** → `xmcGenerateIP` → `xmcGenerateCode` → `xmcHubGenerate` → `xlGenerate` → `xlGenerateButton` |
| I passed the **Hub's block path** as the argument | `mc_call_generator` passes the **block diagram name**, and tries the argument shapes the entry point declares (`nargin`), printing each failure |

Also: `save_system` renames the model, so the Hub's old path stopped resolving
(`Invalid Simulink object name: 'SSRDDC/...'` in the log) -- the device settings
are now reported by looking the Hub up again in the saved model.  And the export
waits for `component.xml` instead of assuming generation finished when the call
returned, ignoring copies left by earlier runs.

## Two routes, and why the template one is preferred

A Hub created with `add_block` on a fresh model is *not* the same object as a Hub
dragged into a model by the GUI: on a real run, with `ProjDevice`, `part`,
`package`, `speed`, `xilinxfamily`, `ExportType` and `IPInfoJsonString` all
confirmed set, every `sysgen` block still reported

```
Target hardware is not selected.  Please select the target hardware in the
'Hardware Selection' tab of the Vitis Model Composer Hub block.
```

So the builder now has two routes and prefers the second:

| route | when | how |
|---|---|---|
| from scratch | no template available | Hub from `vmcUtilities`, channels added |
| **template** | `build/mc_examples/*.slx` exists (`make mc-example`) or `MC_TEMPLATE` is set | Hub **taken from AMD's example** (already initialised: its S-function knows the hardware machinery), everything else deleted, our four channels added, device re-pointed at `MC_PART` |

The generated model contains only library blocks and our wiring — no AMD design
survives the deletion — so what is committed is this repository's own model.

`make mc-example` downloads AMD's 2023.2 example into `build/` (ignored by git;
that repository has no LICENSE file, so it is reference material, never
committed). `make mc-scratch` tells you when no template is present.

## A stale `.slx` is a trap: `mc_gui_build` rebuilds it

`make mc-gui-build` used to reuse whatever `channelizer.slx` was on disk. After
the device-selection fix the copy left by the previous run was still the old,
half-configured model, so the next run failed inside the model update with

```
mc_gui_build failed: Error due to multiple causes.
```

The model is generated from `make_channelizer_model.m`, so a copy on disk is
stale by definition: **`mc_gui_build` now deletes and regenerates it** (pass
`mc_gui_build(path, false)` to export an existing model untouched).

MATLAB hides the real reason behind "multiple causes"; every failure is now
printed with `mc_report_error`, which walks `err.cause` and prints the block and
the parameter, then dumps what the Hub believes the device is:

```
model update failed: Error due to multiple causes.
  - Target hardware is not selected ...
Hub channelizer/Vitis Model Composer Hub:
  ExportType     = IP Catalog
  ProjDevice     = xczu48dr-fsvg1517-2-e
  part           = xczu48dr
  ...
```

## Starting a build without the Generate button

The old scripted entry point `xlGenerateButton` may not exist in a 2023.2
install (the run printed `xlGenerateButton: no`). `mc_generate_function` checks
`xlGenerateButton`, `xmcGenerateButton`, `xmcGenerate`, `xmcHubGenerate`,
`xmcGenerateIP`, `xmcGenerateCode`, `xlGenerate` and reports which are present;
the exporter calls the first that exists. When none exists the message is
explicit: click **Generate** in the Hub, then `make mc-verify` — that collects
the `component.xml` the Hub wrote and installs it in `$(IP_REPO)`.

To see exactly what an installation offers:

```bash
make mc-probe     # libraries, generate entry points, every Hub mask parameter
```

## If a block library is not found

A batch `matlab -batch` session does **not** know Model Composer: the libraries
(`vmcUtilities`, `hdlBasic`, ...) are `.slx`/`.mdl` files inside the installation
and only the GUI launcher adds their folders. So:

```text
Error using make_channelizer_model
There is no block named 'vmcUtilities/Vitis Model Composer Hub'
Caused by: Unable to load block diagram 'vmcUtilities'
```

is not a wrong block name — it is a missing path. `make_channelizer_model`
therefore calls `mc_paths.m` **first**, which:

1. adds the Vivado `scripts/sysgen/matlab` paths and `sysgen.jar`;
2. adds the Model Composer `simulink` folders;
3. looks for `vmcUtilities.slx`, `hdlBasic.slx`, `hdlSSR.slx`, `hdlUtilities.slx`
   (`.slx` **or** `.mdl`) — cheap guesses first, one recursive scan only if
   needed, with the answer cached in `build/mc_libs.txt` so later runs are fast;
4. calls `xmcStart` only if `xlGenerateButton` is still missing;
5. **fails before creating any model**, printing the roots it used and the
   library files it did find, plus the list of blocks in a library when
   `add_block` rejects a name.

The environment variables are a convenience, not a requirement: in a Model
Composer GUI they are usually empty, and `mc_paths` then derives the roots from
what is already on the MATLAB path (`.../Model_Composer/2023.2`,
`.../Vivado/2023.2`) or from `which('xlGenerateButton')`. Only a library that is
missing *and* cannot be located is an error. `make mc-gui` also writes
`MC_ROOT`, `MC_VIVADO_ROOT`, `IP_REPO` and `MC_LIBS_CACHE` into the session's
`startup.m`, so a GUI started by hand still has them.

Diagnose with:

```bash
make mc-libs     # the same search, nothing built
```

If the batch session still cannot see the libraries, the GUI can — and the same
code runs there, so the two routes cannot drift apart:

```bash
make mc-gui         # GUI, with the helpers already on the MATLAB path
make mc-gui-build   # GUI, and it runs the build + export itself on startup
```

How the path gets there: `scripts/launch_model_composer.sh` writes
`build/mc_startup/startup.m` containing `addpath('<repo>/ip/model_composer/channelizer')`
and passes that folder as MATLAB's startup directory (`-sd`), which is a single
plain path argument, so the launcher's `eval` cannot mangle it. MATLAB runs
`startup.m` when the session opens, so `mc_gui_build` is defined before you type
anything.

### A path with `…` in it is not a path

Documentation in chat or in a tutorial may abbreviate a directory as
`/media/.../RFSoC_ZCU208_DOA_V7_BuildKit`. Pasted into a shell that is a literal
directory named `…`, and MATLAB says:

```
Warning: Name is nonexistent or not a directory: /media/.../…/.../channelizer
Unrecognized function or variable 'mc_gui_build'.
```

Never edit a path — print it:

```bash
make mc-shell-help     # every command for THIS checkout, paths filled in
make mc-eval CODE="mc_gui_build"
```

### Lines that look like errors but are not

```
libva error: vaGetDriverNameByIndex() failed
MESA-LOADER: failed to open iris_dri.so / swrast_dri.so
qt.qpa.plugin: Could not find the Qt platform plugin "wayland" in ""
MATLAB is selecting SOFTWARE rendering.
```

These are graphics-driver messages: no hardware GL in the session, so MATLAB
renders in software. They appear on a run that works. The real result is the
last line (`MC_GUI_BUILD_DONE …`) or an `Error using …`.

### `Unrecognized function or variable 'mc_gui_build'`

That means the helper folder is not on the path in the session you are typing
in — the GUI was started without `-sd`, or it is a plain `matlab` window. Paste
one line, with the absolute path:

```matlab
addpath('/media/joshua/Linux/Vivado_prj/.../RFSoC_ZCU208_DOA_V7_BuildKit/ip/model_composer/channelizer'); mc_gui_build
```

`make mc-gui` prints that exact line for your checkout when it exits.

### Running a `.m` file from the Ubuntu shell

```bash
# a function that needs no arguments, batch, exits when done
matlab -batch "addpath('/abs/dir'); mc_gui_build"

# a script file
matlab -batch "run('/abs/dir/my_script.m')"

# keep MATLAB open afterwards (GUI-less), e.g. to look around
matlab -r "addpath('/abs/dir'); mc_gui_build"
```

The two `make` targets above do the same thing through the Model Composer
launcher, which is the only way to get the Model Composer libraries loaded by
the GUI.

## Three ways to get a model

```bash
make mc-scratch     # 1. from scratch, no GUI, R2022b, ~30 s
make mc-gui         # 2. open Model Composer and build it by hand
make mc-example     # 3. download AMD's 2023.2 RFSoC SSR-DDC example for reference
```

`make mc-example` writes to `build/mc_examples/` and is **never committed**:
`Xilinx/Vitis_Model_Composer` has no LICENSE file, so those models are all rights
reserved. The script is the artifact; the model is a reference to read.

## What `make mc-scratch` builds

Four channels of 16-bit signed fixed point (`Q2.14`), each a four-clock delay, at
200 MHz, with the Hub asking for an IP Catalog IP. The block paths are the
2023.2 ones, read out of a real 2023.2 model
(`Examples/HDL/RFSoC/SSR_Digital_Down_Conversion/SSRDDC.slx`):

| block | library path | parameters set |
|---|---|---|
| Hub | `vmcUtilities/Vitis Model Composer Hub` | `ExportType=IP Catalog`, `IpVendor`, `IpLibrary`, `IpVersion`, `IpHWLanguage=Verilog`, `part=xczu208`, `xilinxfamily=zynquplus`, `sysclk_period` |
| input | `hdlBasic/Gateway In` | `gui_display_data_type=Fixed-point`, `arith_type=Signed (2's comp)`, `n_bits=16`, `bin_pt=14`, `quantization=Truncate`, `overflow=Wrap`, `period=1` |
| datapath | `hdlBasic/Delay` | `latency=4` |
| output | `hdlBasic/Gateway Out` | `period=1` |

Structure is the one UG1483 requires: **Hub at the top level**, Gateways as the
ports, everything between them is what becomes the IP. Every `set_param` goes
through a helper that prints whether it took and never aborts, because mask
parameter names move between releases; the log then says
`skipped In1.n_bits = 16 (...)` instead of silently building half a model. When
a parameter is skipped, open `make mc-gui`, set it on the block by hand, save.

The datapath is deliberately a skeleton: a delay is not a channelizer. It is a
model that **compiles**, so the toolchain is proven end to end, and each channel
is then replaced block by block with the real polyphase filter (the design in
`step05_hls_phase_interf` is the reference). Replace `Delay_k` with the filter
subsystem, keep the gateways and the Hub, and `make mc` still works.

## Building the IP

```bash
make mc             # = make step05_channelizer CHANNELIZER_FLOW=model_composer
```

which runs `scripts/build_model_composer_ip.sh`: R2022b in `-batch`, Model
Composer and System Generator paths added inside MATLAB, `xlGenerateButton` on
the Hub, newest `component.xml` copied to `$(IP_REPO)/model_composer_channelizer`,
then a `verify` step that fails the stage if the file is missing or older than
the model.

The Model Composer **launcher** is not used: it evals its arguments and appends
its own `-r`, so a `-batch` payload dies with
`syntax error near unexpected token '('`
(see `docs/evidence/2026-11-07-host-probe/model_composer_launcher_eval_bug.txt`).

## The Hub, not the old token

Model Composer 2023.2 generates from the **Hub** block. `export_model_composer_ip.m`
therefore looks for, in order:

1. `SourceBlock = vmcUtilities/Vitis Model Composer Hub`
2. `SourceType = VMC Hub`
3. `MaskType = Xilinx System Generator` (the pre-2023 token, still common in
   tutorials and in models people copy in)

and sets `ExportType` by trying `IP Catalog`, `IP catalog`, `IPCatalog`, then
reading the value back and printing it. Nothing is assumed about the popup
string.
