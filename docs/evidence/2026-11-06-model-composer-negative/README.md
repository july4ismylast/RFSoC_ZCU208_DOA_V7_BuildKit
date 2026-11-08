# Model Composer refuses every replacement of the exported subsystem

Measured on the user's machine, Vitis Model Composer 2023.2 (build 4029153), AMD's
`SSRDDC.slx`, target `xczu48dr-fsvg1517-2-e`, ExportType = IP Catalog.

## What the engine accepts

Six bisect steps that change everything about the IP *except its contents* all
generated a component:

| step | change | verdict |
|---|---|---|
| 1 | ExportType -> IP Catalog | generated |
| 2 | device -> `xczu48dr-fsvg1517-2-e` | generated |
| 3 | VLNV -> `doa.v7:model_composer:DDC_DUT:1.0` | generated |
| 4 | every gateway `n_bits=16, bin_pt=14` (3 of them) | generated |
| 5 | every delay `latency=4` (7 of them) | generated |

So the export target, the RFSoC part, our IP identity, our sample format and our
pipeline length are all fine. Only the contents of `DDC_DUT` were still AMD's.

## What the engine refuses

Every attempt to put *our* datapath inside the exported subsystem died the same way,
with no compiler diagnostic at all:

```
  xmcGenerate threw: Index exceeds the number of array elements. Index must not exceed 0.

  | Generating code for DDC_DUT        <- the engine log, and then nothing
```

| variant | blocks | ports | testbench | verdict |
|---|---|---|---|---|
| 6 | `add_block('hdlBasic/Gateway In', ...)` | Inport/Outport around each chain | AMD's | failed |
| 6 | `add_block('hdlBasic/Gateway In', ...)` | none | AMD's | failed |
| 7 | copied instances of AMD's own blocks | none | AMD's | failed |
| 8 | copied instances of AMD's own blocks | none | removed, root = Hub + subsystem | failed |

Step 8 is the decisive one: the root held only `SSRDDC/DDC_DUT` and
`SSRDDC/Vitis Model Composer Hub`, the design was four `Gateway In -> Delay ->
Gateway Out` channels made from AMD's own block instances, and the error was unchanged.
Block provenance, port wrapping and the surrounding testbench are therefore all
excluded.

## What remains

`xmcGenerate` throws before the engine writes anything, so the failing code is the
MATLAB side of the tool, not the HDL compiler. Two explanations are consistent with
every observation above:

1. the engine will not compile a design whose only elements are gateways and a delay
   (nothing establishes a rate for it to index), or
2. `xmcGenerate` cannot drive a design that was assembled by script rather than by
   `xlGenerateButton` in the GUI.

The second is testable by hand in ten minutes and needs no new code: open the example
in the GUI, delete the contents of `DDC_DUT`, place four `Gateway In -> Delay ->
Gateway Out` chains from the palette, press Generate. If the GUI succeeds, the tool is
fine and this kit's scripting path is what fails; if the GUI fails identically, the
engine refuses the design.

## Consequence

`make ip-from-hdl` is the deliverable: it writes
`$(IP_REPO)/channelizer_ip/component.xml` as `doa.v7:model_composer:channelizer:1.0`
from `rtl/channelizer/channelizer_dut.v`, and `make ip-equivalence` measures that
Verilog against the Model Composer model -- `bit-exact: 16384 samples, 4 channels,
depth 4: MATCH`, gateway error 6.103e-05 = 1.000 LSB, `RESULT=PASS`.

The six steps that do generate are recorded in
`docs/progress/model_composer_bisect.md` and prove the part, the export type and the
IP identity are usable on this install; only the contents replacement is blocked.

## Three explanations from outside, checked against these runs

| claim | verdict |
|---|---|
| "the exported subsystem has no Simulink Inport/Outport, and that is the zero-index exception" | **falsified here**: the first shape of step 6 wrapped every channel in `Inport`/`Outport` and failed identically, byte for byte |
| "the Hub's inputs are left disconnected; `groundUnconnectedInputs` is not called" | **does not apply**: this example's Hub has no data ports at all -- `Ports = []` in `docs/evidence/2026-11-08-hub-parameters/ssr_example_hub.txt` -- so there is nothing to ground |
| "`MC_BISECT_FROM=8` skips steps 1-7, so the model was never conditioned" | **wrong**: a skipped step is still *applied*, only its generation is skipped. Run 8's log shows `3 gateway(s) set to 16.14`, `7 delay(s) set to latency 4`, `design replaced`, `4 channel(s) copied`, `21 block(s) removed` |
| "the R2021a model is auto-upgraded and corrupted, so generation cannot work" | **not sufficient**: the same auto-upgraded copy generates a component in steps 1-5 |
| "run the full flow once, without `MC_BISECT_FROM`" | would re-run the same nine steps in the same order; steps 1-5 already generate |
| "print the full stack trace instead of `err.message`; update the diagram before generating; re-select the Hub after editing the model" | **done**: every generation now prints the exported subsystem's inport/outport/child counts, the gateway counts, the Hub's port list, the result of a diagram update, and `getReport(err,'extended')` on failure. Step 9 re-asserts the Hub's export identity as the last edit. |

The first four are worth keeping: a reader who arrives with those intuitions can see
the measurement that rules each one out, instead of repeating it.

## The measurement that moves this forward: the model was invalid

Step 9 printed, from this repository's own diagnostics:

```
  hub ports: 0 in, 0 out
  SSRDDC/DDC_DUT: 0 inport(s), 0 outport(s), 13 child block(s)
  gateway blocks inside: 4 in, 4 out
  diagram update failed: Error due to multiple causes.
  xmcGenerate threw: Index exceeds the number of array elements. Index must not exceed 0.
  stack:
  Error using vmcGenerate
  Index exceeds the number of array elements. Index must not exceed 0.
  Error in xmcGenerate
```

Two things stand out.

1. The stack is **`vmcGenerate` itself**, called from `xmcGenerate`: the tool indexes an
   empty array on its own account, before any HDL exists. Nothing about the part,
   the export target or the fixed-point format can reach that line.
2. The diagram **does not update**. Replacing the subsystem's contents left the root
   holding line fragments whose blocks were gone -- the run had already said
   `note: cannot delete a line: Invalid Simulink line handle` twice -- and a model
   that does not update is exactly the state in which a port or rate lookup can come
   back empty.

So the next attempt rebuilds the root instead of patching it: copy the Hub and the
design to new names, delete the originals (Simulink removes the lines attached to a
block, so none can survive), rename the copies back, restore the Hub identity, and
generate. Step 10 does that, and every generation now prints the diagram-update result
and, if it fails, each of its causes.

## The causes, at last: my design was dimensionally wrong

Step 10 rebuilt the root successfully (`lines at the root: 0`) and then printed what
the diagram update objected to:

```
  SSRDDC/DDC_DUT: 0 inport(s), 0 outport(s), 13 child block(s)
  gateway blocks inside: 4 in, 4 out
  diagram update failed: Error due to multiple causes.
    cause 1: Invalid setting for input port dimensions of 'SSRDDC/DDC_DUT/Out1/Demux1'.
             The dimensions are being set to 1. This is not valid because the total
             number of input and output elements are not the same
    cause 2: Error in port widths or dimensions. 'Output Port 1' of
             'SSRDDC/DDC_DUT/Out1/In1' is a one dimensional vector with 1 elements.
```

`Out1` is not a leaf block: AMD's `Vector Real Gateway Out` is a **subsystem** that
demuxes a vector into several scalars. Feeding it a single scalar -- which is what our
channel does -- is a dimension error, and `vmcGenerate` reports dimension errors as
`Index exceeds the number of array elements`. The design was wrong, not the toolchain.

Two further errors of mine are visible in the same log and are fixed:

| error | why it mattered |
|---|---|
| `setIfPossible(inBlock, 'period', '1')` | 1 is one **second**; the Hub's period is 2 ns. The example's own gateways carry `-1` = inherit, and the design is now built with `-1` |
| step 7 copied AMD's blocks and *then* overwrote their period | two variables at once, so "step 7 rules out provenance" was never true. Step 7 now changes nothing in the blocks it copies |

`make mc-bisect MC_BISECT_FROM=10 MC_BISECT_CHECK=1` stops after the diagram update --
seconds per step instead of minutes -- so the model can be fixed in a loop that fails
cheaply and in words.

## Four things the check-only run measured

```
note: SSRDDC/DDC_DUT/In1: period = -1 (Error reported by S-function 'sysgen' ...:
      Sample period is set to a value of -1, but the value must be greater than 0.)
    SSRDDC/DDC_DUT/In1: MaskType=Gateway In Block, period=Tclk, n_bits=48, bin_pt=0
    SSRDDC/DDC_DUT/Delay1: MaskType=Delay Block, latency=3
    SSRDDC/DDC_DUT/Out1: MaskType=Xilinx Vector Gateway Out Block, latency=0
```

| measurement | consequence |
|---|---|
| `period = -1` is **refused**: "Sample period is set to a value of -1, but the value must be greater than 0" | the inherit value does not exist on this block. AMD's own gateways carry `Tclk`, so the design uses `Tclk` |
| AMD's `Gateway Out` is a **`Xilinx Vector Gateway Out Block`** that demuxes a vector | a scalar delay between two such gateways is a dimension error by construction; step 7 connects gateway to gateway |
| AMD's copied gateways are `n_bits=48, bin_pt=0` with `latency=3` delays | this model's datapath is 48-bit vector, not 16-bit scalar. A scalar channel is still buildable, but it must be built from the *scalar* library gateways, which is step 6 |
| copying the Hub raised **"a design can have one Vitis Model Composer Hub block"** and stopped the run until the dialog was dismissed | step 10 copies only the design, never the Hub |

The design step also removes the testbench as it builds, so a check at step 6 is a
verdict on the design and nothing else.

## Step 6 is valid: the model is right, the ladder ends there

```
=== step 6: our channels: gateway -> delay -> gateway ===
  hub.ClockFrequency = 200
  hub.clock_wrapper = Clock Enables
  SSRDDC/DDC_DUT: 0 inport(s), 0 outport(s), 13 child block(s)
  gateway blocks inside: 4 in, 4 out
  diagram update: ok
  -> model ok (not generated: MC_BISECT_CHECK=1)
```

Four `Gateway In (16.14, period = Tclk) -> Delay (latency 4) -> Gateway Out (scalar)`
channels inside the exported subsystem, root holding only the Hub and the design, is a
model Simulink accepts. The earlier failures came from three things that are now gone:
no library gateway (the first shape used `add_block` on a path that did not match), no
`period = 1`, no `period = -1`, and no 48-bit vector gateway taking a scalar.

Steps 7-10 were the AMD-vector detour and are removed from the ladder: a copied
`Xilinx Vector Gateway Out Block` demuxes a vector, so a 16-bit scalar channel is not
something it can be wired to. That is recorded above, not repeated on every run.

The ladder is six steps and ends at our design, which is what `make mc-adopt-bisect`
adopts as `$(IP_REPO)/model_composer_channelizer`.

## The interface shape is measured now, not argued about

A check run passed (`diagram update: ok`) and the generation still died in
`vmcGenerate`, which proves only that Simulink accepts the diagram. One open question
remained, and the repository had contradicted itself about it: does AMD's `DDC_DUT`
carry Simulink Inport/Outport blocks, or are its gateways the boundary?

It is not answered by reading. The design step therefore prints, on every run:

* `AMD's own SSRDDC/DDC_DUT: N in, M out (before the replacement)` -- their subsystem,
  before anything is touched;
* `gateway in: N in, M out; gateway out: N in, M out` -- whether a `Gateway In` accepts
  an incoming line at all;
* `the design is defined by Simulink Inport/Outport blocks` or `by the gateways
  themselves`.

and builds the channels to match what it measured, grounding each inport and
terminating each outport at the root when the design ends up port-wrapped.

The earlier "Inport/Outport was already tried" result is withdrawn: that run carried
`period = 1` and a vector `Gateway Out`, so it tested three wrong things at once and
proved nothing about ports.

## Two more measurements, and one construction that had never been tried

```
  AMD's own SSRDDC/DDC_DUT: 3 in, 2 out (before the replacement)
  gateway in: 1 in, 1 out; gateway out: 1 in, 1 out
  the design is defined by Simulink Inport/Outport blocks
```

The contested question is settled by number: this model defines a design by Simulink
**ports**, AMD's subsystem has 3 in and 2 out, and a `Gateway In` does accept an
incoming line. So `P -> Gateway In -> Delay -> Gateway Out -> Q` is the right shape, and
our 4 in / 4 out is the same convention one channel wider.

The same run also exposed a lie in this harness:

```
note: cannot wire Ground1/1 -> SSRDDC/DDC_DUT/1: Invalid Simulink object name
 4 inport(s) grounded, 4 outport(s) terminated at the root
```

`add_line('SSRDDC', ...)` takes names relative to that system (`DDC_DUT/1`), so every
grounding call failed while the loop reported success. Wiring is now verified
afterwards, a dangling port raises an error, and each `Constant` runs at `Tclk` instead
of a `Ground`'s infinite sample time.

Step 7 is the construction that had never been tried: build a **new** subsystem of our
own (`CHANNELIZER`), leave AMD's `DDC_DUT` alone until it is deleted, and point the
Hub's `IPInfoJsonString` at the new name. Every attempt before it edited AMD's
library-linked block -- broke the link, emptied it, refilled it -- which is not something
a GUI user ever does.

## The model is valid, and `xmcGenerate` still dies

Step 6's last run, with every earlier defect fixed:

```
  AMD's own SSRDDC/DDC_DUT: 3 in, 2 out (before the replacement)
  gateway in: 1 in, 1 out; gateway out: 1 in, 1 out
  the design is defined by Simulink Inport/Outport blocks
  4 inport(s) driven, 4 outport(s) terminated: 0 unconnected
  SSRDDC/DDC_DUT: 4 inport(s), 4 outport(s), 21 child block(s)
  unconnected ports on DDC_DUT: 0
    in 1: line 3.100049e+01   ... out 4: line 5.200049e+01
  diagram update: ok
  xmcGenerate threw: Index exceeds the number of array elements. Index must not exceed 0.
  stack:
  Error using vmcGenerate
```

No model defect is left to blame: the diagram updates, every port is wired, the gateways
carry 16.14 at `Tclk`, and the delay is latency 4. AMD's own design, with the same Hub,
the same part and the same export type, generates -- steps 1-5 did.

What remains different is **how the build is asked for**. Every run so far called
`xmcGenerate('SSRDDC')`. The installation also ships the GUI's own entry points
(`xmcGenerateButtonPressed`, `xmcGenerateCallback`, `xmcHubInit`), and the Hub's dialog is
where the state the engine reads is built, so `startGeneration` now tries them in order,
printing which one it used. A person pressing Generate runs that code; an API call may
not.

If all of them fail, the two possibilities left are (a) this engine will not compile a
design that is only gateways and a delay, or (b) its scripting entry points are broken on
this install. The GUI test in the README distinguishes them, and `make ip-from-hdl`
-- `doa.v7:model_composer:channelizer:1.0`, verified bit-exact against the model -- is
the deliverable either way.

## The GUI entry point simulates first, and the simulation was broken

`xmcGenerateButtonPressed` is the first call in twenty runs that starts real work. Its
stack shows what `vmcGenerate` does:

```
Warning: Unconnected line found in 'SSRDDC' (starts 80% from left and 35% from top of view)
  ...(seventeen of these)...
In Simulink.Simulation.internal.DesktopSimHelper.sim
In Simulink/SimulationInput/sim
In xmcGenerateImpl
In vmcGenerateImpl
In xmcGenerateButtonPressed
  xmcGenerateButtonPressed threw: Error due to multiple causes.
```

It **simulates the model before generating**, and the simulation failed. The seventeen
"Unconnected line" warnings are line fragments whose other end was deleted with AMD's
testbench -- the same fragments that produced `cannot delete a line: Invalid Simulink
line handle` in earlier runs. So the model that reached the engine still had a broken
diagram, and an exporter that inspects the simulation's port list would find it empty.
That is a far better explanation of "Index must not exceed 0" than any parameter.

Fixed in this round:

| defect | fix |
|---|---|
| orphaned line fragments survive `delete_block` | `purgeDanglingLines` deletes every root line whose source or sink port is gone, and the same inside the design, after each strip |
| a failed entry point printed only `Error due to multiple causes` | each failure now prints every `cause` and the full `getReport` stack |
| `xmcGenerateCallback` returns without generating, and looked like success | removed from the attempt list; the run then waited an hour for a file nothing was writing |
