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
