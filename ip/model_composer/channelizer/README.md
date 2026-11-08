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

## Building AMD's example to IP: what it answers, what it does not

`make mc-example-ip` copies `build/mc_examples/SSRDDC.slx`, sets
`ExportType = IP Catalog`, generates it twice -- once with the example's own part,
once retargeted to `$(PART)` -- and writes
`docs/progress/model_composer_example_report.md`: every Hub parameter, every block
with its mask type and source block, the model callbacks, the workspace variables.

Two questions, two answers:

| question | how the run answers it |
|---|---|
| Does Model Composer produce an **IP Catalog component for our part** in this install? | the second generation is retargeted to `xczu48dr-fsvg1517-2-e`; its verdict line says `generated` or `failed` |
| What does a model that **does** generate look like? | the report, written by the tool, committed to `docs/progress/` |

What it does **not** answer: why our assembled model is refused. Copying the
example's parameters has already been tried (the graft route sets the same 53
parameters), and the refusal comes from a protected `.p` file. If the retargeted
example does generate, the next step is to rebuild around the example's **exact
block topology** instead of recreating its subsystem; if it does not, Model
Composer's IP Catalog export is unusable for this part here and the Verilog route
(`make ip-from-hdl`) remains the deliverable.

## What the saved example actually says (read without MATLAB)

A `.slx` is a zip. `scripts/slx_hub_params.py` unzips one and prints the Hub's
stored `InstanceData`, so a saved model can be interrogated on a machine that has
no Model Composer. `make mc-hub-dump` is that script; the dump of AMD's example
is committed as `docs/evidence/2026-11-08-hub-parameters/ssr_example_hub.txt`.

Three things that dump says, each of which contradicts an earlier note in this
file:

| earlier claim | what the file says |
|---|---|
| the Hub exports to `IP Catalog` by default, it is one popup away | `ExportType = System Generator` |
| `SubsystemName` and `IpName` are Hub parameters; empty ones caused the failure | there is **no** such parameter. The exported block and the VLNV live in `IPInfoJsonString`, e.g. `{"HDLSubsystem":{"SubsystemName":"DDC_DUT",...,"IPVendor":"User Company"}}` |
| the example is a ZCU208 design | `ProjDevice = xcku11p-ffva1156-1-e`, family `kintexuplus`, `part = xcku11p`, `package = ffva1156` |

It also shows what the example feeds the rate machinery from: a `PreLoadFcn` that
defines `clk = 500e6`, `sample_rate`, `SSR`, `Tclk`, `Ts`, which is why its
`sysclk_period` reads `(1e+9)/clk` and `simulink_period` reads `1/clk`.

### The bug this exposed, and two wrong diagnoses before the right one

`make mc-bisect` died on its first write:

```
mc_bisect failed: Reference block does not have a parameter named 'ExportType'
```

**First diagnosis (wrong):** `mc_find_hub` searched with `FollowLinks` on and must
have returned the library's reference block. The next run disproved it: the block
path was `SSRDDC/Vitis Model Composer Hub`, which is in the model.

**What that run actually printed:**

```
hub SSRDDC/Vitis Model Composer Hub: ExportType=, device=
block ..., BlockType=Reference, ReferenceBlock=, SourceBlock=vmcUtilities/...
MaskType=
no mask parameters are visible on this block
Warning: Cannot find library called 'vmcUtilities'.
Warning: Cannot find library called 'hdlUtilities'.
```

Empty reads, empty `MaskType`, empty `ReferenceBlock`, no mask parameters, and two
libraries that cannot be found. That is not a parameter-name problem and not a
library-block problem either: **the link does not resolve, because the library is
not on the path of this session, so the masked block has no parameters at all.**
`set_param` reports the missing parameter, which sends you looking at the name.

**Second diagnosis (right):** the payload runs from `build/mc_startup/startup.m`,
before or without Model Composer's own path setup. The fix is to load the
libraries *before* any model is opened -- a link that failed once stays unresolved
until the model is reopened:

* `mc_require_libraries` calls the existing `mc_paths`, then loads
  `vmcUtilities`, `hdlBasic`, `hdlUtilities`, `xilinxUtilities`, and prints what is
  still missing together with the root it searched.
* `mc_bisect` refuses to run when that fails: with no parameters to set there is
  nothing to bisect, and a report would blame the design.
* `make_channelizer_model`, `mc_graft_model`, `mc_example_ip` and
  `export_model_composer_ip` call it before they open a model.
* `mc_hub_set` now says what an empty mask means instead of only listing nothing.

The `FollowLinks 'off'` + "must be inside the model" filter in `mc_find_hub` stays
as hardening -- it was not the cause, but writing to a block in another model is
never right.

That run then went one step further and stopped on a library that does not exist:

```
the Model Composer block libraries are not on this path:
  xilinxUtilities (No system or file called 'xilinxUtilities' found.)
```

`vmcUtilities`, `hdlBasic` and `hdlUtilities` had been found -- only
`xilinxUtilities` was missing, and it is not part of Model Composer 2023.2 at all.
A hard-coded list of four names was therefore the wrong test: it refused a session
that was ready. So the list now marks `vmcUtilities` and `hdlBasic` required (the
Hub and the gateway/delay blocks this kit uses), tries and reports the rest, and
the real test is moved to where it belongs:

* `mc_require_libraries` -- path repair, required libraries loaded, the rest
  reported as absent, which is not an error.
* `mc_resolve_links` -- called immediately after every `open_system` /
  `load_system`. It finds the blocks whose link is still `unresolved`, loads the
  library each one names in its own `SourceBlock`, and asks Simulink to resolve
  that link. This uses what the model links to instead of a guessed list of
  library names, which is what the failure actually needed.
* `mc_bisect` still refuses to continue when `vmcUtilities` or `hdlBasic` cannot be
  loaded, because then the Hub really has nothing to write.

Still unverified: whether `mc_resolve_links` is enough on this install, or the
model has to be closed and reopened after the libraries are on the path. If the
Hub still reads empty after both, run `make mc-libs` for the paths `mc_paths`
searched and set `MC_ROOT` to `Model_Composer/<version>`.

## The bisect ran: three steps generate, and two were the script's fault

First real run of `make mc-bisect` (2026-11-08, ZCU208 host, Model Composer 2023.2):

| step | result | what it settles |
|---|---|---|
| 1 | **generated** | IP Catalog export works on this install at all |
| 2 | **generated** | ... and for `xczu48dr-fsvg1517-2-e`, an RFSoC part, not the example's `xcku11p` |
| 3 | **generated** | ... and with `doa.v7:model_composer:...:1.0` written into `IPInfoJsonString` |
| 4 | *no-op* | the script's fault, not a verdict -- see below |

That is the answer to "can it work?" for the engine and the part: yes, at least for
AMD's model retargeted. What is still open is step 6, our block topology.

Two faults in the ladder, both now fixed:

**`MaskType` is empty on a linked instance.** Step 4 searched
`'MaskType','Gateway In'` and matched nothing -- the same trap as the Hub, where
the mask lives in the library and the instance only carries `SourceBlock`. The
selector now uses `SourceBlock`/`ReferenceBlock` against `hdlBasic`, `hdlSSR` and
`xilinxUtilities`, and when nothing matches it prints every library block the
model *does* contain, so a failed selector is visible instead of silent.

**`exportedSubsystem` fell back to "the first subsystem".** Step 3 therefore
exported AMD's test-bench block `ADC 1.5GSPS` -- a name containing a line break --
and generation still succeeded, which says the *name* was never a blocker. The
fallback is now: the name in `IPInfoJsonString`, else `DDC_DUT`, else the
subsystem that actually contains Gateway In blocks, and the choice is printed.

A step that changes nothing no longer produces a result row: it is reported as
`no-op: the step matched no block` and the run stops there, because a step that
tested nothing cannot accuse the design.

`make mc-bisect-ips` prints the VLNV and ports of everything the bisect generated,
so the artifacts of steps 1..3 can be read without Model Composer.

### The rerun stalled in step 2, and that was the tool's fault too

The second run reached step 2 and then showed "generation in progress" for more
than ten minutes with nothing printed. Two things were wrong with that, neither of
them Model Composer's:

* the wait was a fixed 900 s with **no output**, so a synthesis that legitimately
  takes minutes is indistinguishable from a hang. It now prints a line every 30 s:
  the newest file in the work folder and its age, and how many `vivado` processes
  are alive (`pgrep -c vivado`). A real synthesis shows a fresh file and a Vivado
  process; a hang shows neither.
* steps 1..3 had already generated in the previous run, and the rerun repeated
  them anyway -- roughly ten minutes spent re-proving what is on disk. Each step
  whose `$(IP_REPO)/ssr_bisect_step<N>/component.xml` is newer than the example is
  now reported as `generated earlier (<date>)` and skipped. `MC_BISECT_FRESH=1`
  forces a rerun of those steps.

The timeout is now `MC_GENERATE_TIMEOUT` seconds, default 3600, and on expiry the
run prints the tail of `model_composer_hdl.log` instead of a bare verdict.

If a run stalls again, the two questions the log now answers without a rerun:

| symptom | reading |
|---|---|
| newest file keeps changing, `1 Vivado process(es)` | real synthesis -- let it finish, or raise `MC_GENERATE_TIMEOUT` |
| nothing written for minutes, `0 Vivado process(es)` | hung in the engine -- Ctrl-C, then `make mc-bisect MC_BISECT_FRESH=1` for that step |

### It stalls on every generation, and the cache stopped helping

After the first cancel, every session hung again at the same place -- and the rerun
regenerated step 1 even though its artifact was on disk, so the ten minutes were
spent twice. Two separate causes, two separate fixes.

**The cache was silent about missing.** A step regenerates when the artifact is
absent, older than the example, named in a way that cannot be an IP, or when
`MC_BISECT_FRESH=1`. None of that was printed, so a run that repeated step 1 looked
identical to one that had nothing cached. Every step now says which of those it is:

```
  step 1: generating (the example is newer than the artifact (08-Nov-2026 13:05:11))
```

**A cancelled session leaves SysGen state behind.** Model Composer keeps a
per-session temp tree (`/tmp/sysgentmp-<user>/<pid>/`) and a shared-memory proxy
(`/dev/shm/sgproxy*`, `vivado_shmem.sh`, `SgWaveformServer.tcl`). A cancel does not
remove them, and the next session's hand-back can wait on them for ever -- which is
exactly the shape of the hang: the first session generates three steps fine, later
sessions hang on the second. `launch_model_composer.sh` now clears both **only when
no `matlab` or `model_composer` process is running**, and says so:

```
cleared stale SysGen temp state (no MATLAB was running)
```

**And the ladder can start where the proof stopped.** `MC_BISECT_FROM=4` marks
steps 1..3 as `skipped (MC_BISECT_FROM=4)` without generating them; those steps are
still applied to the model, so step 4 is generated from a model that carries changes
1..4. Steps 1..3 are already proven by two runs, and the fixed step-3 code (the
exported block named in `IPInfoJsonString`) is exercised inside step 4's chain.

`make mc-bisect-clean` drops `build/mc_bisect/netlist` and `code` -- the engine's
litter, never the collected artifacts in `$(IP_REPO)`.

### The GUI hung after the engine had finished

The next run sat in "generation in progress" while, on disk, the engine was long
done: `build/mc_bisect/netlist/model_composer.log` ended with `exit`, and
`netlist/ip/DDC_DUT/src/vivado.log` ended with

```
INFO: [Ipptcl 7-1486] check_integrity: Integrity check passed.
INFO: [Common 17-206] Exiting Vivado at Sun Nov  8 13:08:43 2026...
```

Forty-seven minutes later the window still said "generation in progress", and the
only live processes were `SgWaveformServer.tcl` and the SysGen shared-memory proxy
(`vivado_shmem.sh`, `start_sharedmemory ... sgproxy<pid>_<id>`). Those are idle
servers, not synthesis: the hand-back over shared memory never completed. The IP was
packaged and sitting on disk the whole time.

Three changes, all of them about not losing work the engine already did:

* when `xmcGenerate` throws -- cancelled, interrupted, or a timeout -- `mc_bisect`
  looks for a `component.xml` written since the step began, and adopts it instead of
  calling the step failed. A cancelled call is not a failed step.
* `make mc-bisect-harvest` (`scripts/mc_bisect_harvest.py`) lists every
  `component.xml` the run left under `build/mc_bisect`, with VLNV and age;
  `INSTALL=step2` copies the newest into `build/ip_repo/ssr_bisect_step2`.
* a cached artifact whose component name is not an identifier is not reused: the
  old step-3 artifact is named `ADC 1.5GSPS` (with a line break), which cannot be
  the IP this kit exports, so that step regenerates instead of silently counting as
  proven.

### `make mc-bisect-watch`, for the terminal that is not busy

While Model Composer sits in "generation in progress", the useful evidence lives
outside it. `make mc-bisect-watch` (or `scripts/mc_watch.sh <folder>`) prints, with
no MATLAB involved: the live `vivado` processes with their elapsed time, the newest
files under the work folder, the age of the newest log, whether anything has been
written for more than five minutes, and which `component.xml` files exist already.

The engine's log is **not** where the earlier code looked. A real run had it at
`build/mc_bisect/netlist/model_composer.log` (723 bytes) while `mc_hdl_log_tail`
searched only for `model_composer_hdl.log` in the model folder and reported "no
log". It now tries `<folder>`, `<folder>/netlist` and `<folder>/code` for the known
names, and falls back to the newest `*.log` anywhere below `<folder>`.

That run's process table was the decisive evidence: three `vivado` processes, two of
them running `SgWaveformServer.tcl` -- System Generator's simulation data server,
which `xmcGenerate` starts because it simulates the model before synthesising. So
the engine was inside its own work, not deadlocked on a dialog.


## Which change breaks it? `make mc-bisect`

`make mc-example-ip` says whether the example survives at all. `make mc-bisect`
answers the narrower question: **which of the changes that turn AMD's example into
our design is the one the engine refuses?**

`ip/model_composer/channelizer/mc_bisect.m` starts from a **fresh copy of
`build/mc_examples/SSRDDC.slx` every time**, applies our changes in order
(1..k), and generates:

| step | change | what a pass proves |
|---|---|---|
| 1 | `ExportType` from `System Generator` to `IP Catalog` | IP Catalog export works for this install at all |
| 2 | device retargeted to `MC_PART` | the xczu208 part is not the blocker |
| 3 | exported subsystem named `channelizer`, VLNV set to `doa.v7:model_composer:channelizer:1.0` | `SubsystemName`/`IpName` being empty was not the blocker |
| 4 | every `Gateway In` set to sfix16_En14 (found by `SourceBlock`, not `MaskType`) | our **sample format** is not the blocker |
| 5 | every `Delay` set to latency 4 (same selector) | our **pipeline length** is not the blocker |
| 6 | the design inside the exported subsystem replaced by our four channels | our **block topology** is not the blocker |

The run stops at the first failing step and prints that step's Hub parameters, so
the culprit is named by the output instead of guessed at. If all six generate, our
topology was never the problem and the difference lies in the model that this
builder *assembles* (the copy of the Hub, the callbacks, the workspace) -- which is
what the earlier attempts already point at.

Two limits, stated rather than hidden: this route needs a Model Composer install
(so it says nothing on a machine that has none), and it mutates only a scratch copy
under `build/mc_bisect/` -- the example in `build/mc_examples/` is never modified,
because it is reference material that must stay pristine for the next comparison.
Results land in `docs/progress/model_composer_bisect.md`; the console prints
`MC_BISECT_DONE`. If all six steps generated, the last artifact **is** our design
built by Model Composer: `make mc-adopt-bisect` copies
`$(IP_REPO)/ssr_bisect_step6` to `$(IP_REPO)/model_composer_channelizer` (the name
`make step06_collect_ip` expects) and runs the same component check as the Verilog
route, so the two are compared by the same test, not by my word.

```bash
make mc-example       # once, if build/mc_examples/SSRDDC.slx is absent
make mc-example-ip    # does the example generate at all here?
make mc-bisect        # which of our six changes breaks it?
```

## Is the hand-written IP the same as the model? Same datapath, different interface

`make ip-equivalence` answers it with numbers instead of opinion
(`testbench/compare_hdl_vs_model.py`):

```
bit-exact: 16384 samples, 4 channels, depth 4: MATCH
latency measured from an impulse: 4 clocks (declared 4)
gateway quantisation: worst error 6.103e-05 = 1.000 LSB (LSB = 0.000061)
RESULT=PASS
```

| property | `channelizer.slx` | `channelizer_dut.v` | equal |
|---|---|---|---|
| channels | 4 | 4 | yes |
| sample format | `sfix16_En14`, Truncate, Wrap | 16-bit two's complement, LSB 2^-14 | yes (gateway error measured: 1.000 LSB) |
| delay per channel | `Delay` latency 4 | four pipeline registers | yes, measured 4 clocks |
| rate | one sample per clock, 200 MHz | one sample per clock | yes |
| reset / enable | none in the design | none | yes |
| data ports | `In1..In4`, `Out1..Out4`, 16 bits each | `din[63:0]`, `dout[63:0]` | **no** -- same data, different packing |
| clock | `clk` | `clk` | yes |
| clock enable | `ce` (Hub `clock_wrapper = Clock Enables`) | absent | **no** |
| exported files | Model Composer wrapper, `component.xml`, Verilog per `IpHWLanguage` | one Verilog module, `component.xml` from `ipx::package_project` | different tools, same interface class |

So: the **arithmetic is the same** -- verified bit-exact on 16 384 samples per
channel, with the latency measured rather than assumed -- and the **interfaces are
not identical**: port packing and the optional clock enable differ, as the table
says.

Unproven, and stated as such: no Model Composer export of this design exists to
diff against, because its scripted generation is blocked here. The comparison is
between the behaviour the `.slx` describes and the Verilog in this repository, not
between two `component.xml` files. If generation ever succeeds, the check to run is
the port list: `diff` the `<spirit:ports>` sections, and expect exactly the `ce`
and the packing differences above.

## `make ip-from-hdl` was run and it produced the IP

Measured on the build machine, not expected:

```
INFO: [Ipptcl 7-1486] check_integrity: Integrity check passed.
IP_PACKAGE_OK …/build/ip_repo/channelizer_ip/component.xml
```

That is the deliverable: a Vivado IP Catalog core for the same datapath the model
describes. Changes after that first run, all from its warnings:

| warning in that log | change |
|---|---|
| `CRITICAL WARNING: [Ipptcl 7-1601] ipx::package_project in non project mode is not supported` | the script now creates a real project (`build/ip_repo/_ipbuild_channelizer`), packages inside it, and removes it afterwards |
| `WARNING: [IP_Flow 19-11770] Clock interface 'clk' has no FREQ_HZ parameter` | `FREQ_HZ` is set to 200 000 000 on the `clk` interface |
| `WARNING: [Ipptcl 7-1467] compile order set manually` | `-force_update_compile_order` |
| nothing verified the output | `scripts/check_ip_component.py` prints the VLNV and every port and fails if `clk`, `din` or `dout` is missing |

`make step06_collect_ip` now accepts either route: `model_composer_channelizer`
from Model Composer, or `channelizer_ip` with the pinned VLNV
`doa.v7:model_composer:channelizer:1.0`.

## A path that does not depend on Model Composer: `make ip-from-hdl`

Model Composer's scripted call (`xmcGenerate`) works on AMD's own model in this
install and refuses every model this builder produces -- with an error raised
inside a protected `.p` file that names nothing. Ten rounds have gone into that
one call. So there is now a second, independent way to the same deliverable:

| | Model Composer path | `make ip-from-hdl` |
|---|---|---|
| source | `channelizer.slx` (generated by `make mc-scratch`) | `channelizer_dut.v` (this repository) |
| tool | Model Composer 2023.2 `xmcGenerate` | Vivado 2023.2 `ipx::package_project` |
| output | `build/ip_repo/model_composer_channelizer/component.xml` | `build/ip_repo/channelizer_ip/component.xml` |
| status | blocked by the engine error | depends only on Vivado, which this install demonstrably runs (it compiled AMD's example) |

`channelizer_dut.v` is the same datapath the model describes: four channels,
`sfix16_En14`, four-clock delay, one sample per clock at 200 MHz. The Makefile
target creates a project in memory for `$(PART)`, packages the module with vendor
`doa.v7`, library `model_composer`, version `1.0`, checks integrity, and prints
`IP_PACKAGE_OK <component.xml>`.

```bash
make ip-from-hdl
```

Both paths describe one design; neither is a substitute for the other in the
documentation. The model stays the reviewable source of the Model Composer flow,
and this target guarantees an IP Catalog component that step06 can consume.

## AMD's example generates; ours does not -- so the difference is ours

The last run finally reached a verdict that can be acted on:

```
the example generated
--- verdict ---
  AMD's example generates and ours does not, so the difference is in our model.
```

and Model Composer's own log named two differences:

| log line | meaning | fix |
|---|---|---|
| `CodeGeneration = off` in the Hub dump although the model was saved with `on` | opening the dialog / failed attempts reset it | re-asserted before every generate attempt |
| *The "Simulink system period" setting ... is smaller than required* (`1/5e+08`, "a more efficient setting would be 1") | the grafted model inherited the example's `(1e+9)/clk` / `1/clk` expressions while our gateways run at period 1 and 200 MHz | `sysclk_period = 5`, `simulink_period = 1` written explicitly |
| the exported subsystem had **no Inport/Outport blocks** | AMD's `DDC_DUT` has three Inports and two Outports; a subsystem made only of gateways has none, and the engine walks that port list -- an **empty list is the index error** every round reported | each channel is now `Inport -> Gateway In -> Delay -> Gateway Out -> Outport` |

The subsystem keeps the example's name `DDC_DUT`, because that is the name its Hub's
`SubsystemName` refers to; the design inside it is ours.

## Two facts from AMD's example, and a change of base model

Running the example produced two facts that settled the design of this builder:

1. **The engine writes into `./netlist` relative to the working directory.** Even
   with `Hub.directory` set to an absolute path, the compiler reported
   `ERROR-XMC-1002: Failed to create and open file ./netlist/ip/Makefile`. So the
   generation must run **from the model's folder**, with `netlist/ip` and `code`
   created -- both `export_model_composer_ip` and `mc_diagnose` now do that.
2. **The example reaches the HDL compiler** (`vmcGenerateCode/generateHDLCode` ->
   `XilinxCompiler`), while a model assembled around a *copied* Hub dies earlier
   inside `vmcGenerate.p`. A copied Hub is therefore not equivalent to the one AMD
   ships.

Because of (2) the model is no longer assembled around a copied block: the
**example itself is the base model**, and only its design is replaced.

| step | what happens |
|---|---|
| base | copy `build/mc_examples/SSRDDC.slx` to `channelizer.slx`, open it (its `PreLoadFcn` defines `clk`) |
| keep | the Hub instance and the exported subsystem (`DDC_DUT`) |
| replace | the subsystem's contents: four `Gateway In -> Delay -> Gateway Out` channels |
| delete | every other top-level block of AMD's design |
| retarget | device `xczu48dr-fsvg1517-2-e`, `ExportType = IP Catalog`, absolute netlist/code dirs, `SubsystemName`/`IpName` = the subsystem name |

Nothing of AMD's signal chain survives; what is reused is the model machinery the
engine expects. `make_channelizer_model` reports `route: graft onto …` when this
path runs, and falls back to building from scratch when no example is present.

## The actual generator error: `./netlist/make.sh`

Running AMD's own example through the same call was decisive -- it changed the
message from an index error to the engine's real complaint:

```
ERROR-XMC-1002: Failed to create and open file ./netlist/make.sh
ERROR-XMC-5001: Compilation HDL failed during code generation.
```

The Hub's netlist and target directories are **resolved against the MATLAB working
directory**, and both were relative (`./netlist`, `./code`). Where the engine looked
there was no such folder, so it could not write `make.sh`; nothing was generated,
and the empty intermediate it expected to read afterwards is what `vmcGenerate.p`
indexed as `element 1 of 0`.

So the fix, applied in both places:

| where | what |
|---|---|
| `make_channelizer_model` | the Hub's `directory` and `TargetDirectory` are set to `<model folder>/netlist` and `<model folder>/code`, and those folders are created before generation |
| `export_model_composer_ip` | before generating, a relative `directory` / `TargetDirectory` is rewritten to the model folder and created -- this also repairs a model built by an earlier version |
| `mc_diagnose` | the same for AMD's example, so the comparison run is fair |

`MC_SELFTEST_OK` and the model build are unchanged; only where the engine writes
has changed.

## Stop guessing: read the engine's log and cross-check AMD's example

Six rounds produced one repeated sentence from a protected `.p` file, and each
round answered it with a guess.  The builder now measures instead:

1. **The GUI's own entry points.** `xmcGenerateButtonPressed`, `xmcGenerateCallback`,
   `xmcHubInit`, `xmcApplyButtonClick` all exist in this install. A model built from
   code has never had the Hub's dialog opened, and the dialog is where the Hub
   builds the state the engine reads -- so the dialog is opened (`open_system(hub)`)
   and those callbacks are tried, with the generate call retried after each.
2. **Model Composer's own log.** `model_composer_hdl.log` sits next to the model and
   says why a run stopped. Every earlier round printed its path and never read it;
   `mc_hdl_log_tail` now prints its last 60 lines.
3. **AMD's unmodified example, through the same call.** `mc_diagnose` copies
   `build/mc_examples/SSRDDC.slx` and runs `xmcGenerate` on it. The verdict is one
   line:

   | result | meaning |
   |---|---|
   | `example-fails` | the toolchain, licence or session is at fault, not this model |
   | `example-works` | the difference is in our model, and both Hub dumps are on screen |

No more single-hypothesis rounds: one run now produces evidence that separates
the two possibilities.

## The real cause: the Hub exports a *named subsystem*, and ours did not exist

The platform attempts failed too (`Not Specified` and `Specify Platform`, with and
without the ZCU208 board).  What settled it was AMD's own example, opened as a
zip: its top level is

```
Vitis Model Composer Hub
DDC_DUT                 <- a subsystem
```

and its Hub says `SubsystemName = DDC_DUT`.  Model Composer exports **the block
named by that field**.  Our model had the gateways loose at the top level and
`SubsystemName = channelizer_dut` naming nothing, so the lookup returned an empty
array and the engine indexed it:

```
Index exceeds the number of array elements. Index must not exceed 0.
```

That is the same error in every run, whatever the device, platform, name or
arguments.

### The model shape now

```
channelizer.slx
  System Generator            Hub: device, IP Catalog, SubsystemName
  channelizer_dut             subsystem, same name as SubsystemName
    In1 -> Delay1 -> Out1
    ... four channels ...
```

`export_model_composer_ip` checks this before generating: if
`Hub.SubsystemName` is empty, or the model has no block of that name, it stops
with a sentence instead of letting the engine produce an index error.

## Next hypothesis, and the evidence for it

Renaming the block to `System Generator` did not change the index error, so the
name was not the whole story. What the same run left as evidence:

```
EMPTY  Platform
PlatformType = Not Specified
ProjDevice   = xczu48dr-fsvg1517-2-e     (Zynq UltraScale+ RFSoC)
```

The Hub example that works is a bare Kintex part (`xcku11p-ffva1156-1-e`) with
`PlatformType = Not Specified` -- no board, no PS. A ZU+ RFSoC design is the case
where Model Composer needs a **board** (platform) to know what the RFSoC is
attached to, and `Platform` is the parameter that is empty.

`mc_platform_attempts` therefore tries the selection variants the Hub itself
allows (read from the mask, never guessed): every `PlatformType` option, with and
without the board from `config.mk` (`BOARD_PART = xilinx.com:zcu208:part0:2.0`,
passed as `MC_BOARD`). The first combination that makes `xmcGenerate` return is
reported and saved into the model.

Whatever the outcome, the same run prints:

- `mc_hub_options` -- every popup parameter with its allowed strings;
- `mc_api_listing` -- the `xmc*` / `xl*` entry points that exist in this install,
  which is where a JSON-based variant (`xmcGenerate(model, 'model_hubInfo.json')`,
  documented in its own help) would come from.

## The generate block must be named `System Generator`

A real run ended with two seemingly unrelated symptoms, and they are the same
bug:

| where | message |
|---|---|
| error dialog | *the System Generator block must be named "System Generator"* |
| MATLAB | `xmcGenerate` → `vmcGenerate.p` → **Index exceeds the number of array elements** |

`vmcGenerate` collects the generate blocks in the model **by that name** and takes
element 1. A Hub dragged in from the library keeps its library name
(`Vitis Model Composer Hub`) — which is fine in the GUI, because the GUI keeps its
own reference — but a model built from code has nothing under the required name,
so the list is empty and element 1 does not exist. Hence the dialog and the index
error at the same time.

Fix: the builder renames the block, keeping the library link:

```matlab
set_param(hub, 'Name', 'System Generator');    % block path: channelizer/System Generator
```

The from-scratch route creates it under that name directly. Every log line then
shows `generate block: channelizer/System Generator`.

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
