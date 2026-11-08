# Model Composer: building and exporting the channelizer IP by hand

Everything below is done in the Vitis Model Composer GUI. No script, no command beyond
starting MATLAB: the two things the scripted path could not get right — the Hub's
subsystem selection and the point at which the tool decides the design is valid — are
ordinary clicks here.

AMD's example is used as the starting model only because its Hub is already configured
for this install (clock 200 MHz, clock enables, `Tclk` defined). The design inside it is
replaced entirely.

---

## 0. Prepare and start

```bash
cd /media/joshua/Linux/Vivado_prj/Doc1/seek/FP/RFSoC_ZCU208_DOA_V7_BuildKit_STEP05_PACKAGE_FIX_V5/RFSoC_ZCU208_DOA_V7_BuildKit
make mc-example        # downloads AMD's SSRDDC.slx to build/mc_examples/
make mc-gui            # MATLAB R2023.2 with the Model Composer paths
```

`make mc-example` fetches `Examples/HDL/RFSoC/SSR_Digital_Down_Conversion/SSRDDC.slx`
from `Xilinx/Vitis_Model_Composer`, branch 2023.2. It is AMD's file, kept out of git.

## 1. Make a writable copy and open it

In MATLAB:

```matlab
src = fullfile(pwd, 'build', 'mc_examples', 'SSRDDC.slx');
dst = fullfile(pwd, 'build', 'mc_gui');
if ~isfolder(dst), mkdir(dst); end
copyfile(src, fullfile(dst, 'SSRDDC.slx'));
cd(dst)
open_system('SSRDDC')
```

Accept the "saved in an earlier version" prompt. Do **not** work on the file under
`build/mc_examples`.

## 2. Clear the testbench at the root

In the model window, keep exactly two blocks and delete everything else:

- `Vitis Model Composer Hub`
- `DDC_DUT`

Delete the ADC, the scopes, the constants, the signal generators. `Ctrl+A` then
shift-click those two, or delete them one by one. The root must end up with those two
blocks and **no signal lines at all**. If Simulink leaves a stub of line behind, select
it and delete it — a leftover line here becomes `Unconnected line found` later.

## 3. Empty the design subsystem

Open `DDC_DUT` (double-click). Select everything inside and delete it. You now have an
empty subsystem with 3 inputs and 2 outputs; the ports will be removed as the blocks that
created them disappear — that is expected.

## 4. Build one channel, then copy it three times

Inside `DDC_DUT`, from the **Library Browser** (not by typing commands):

| block | where it is in the browser |
|---|---|
| `Inport` | Simulink → Sources |
| `Gateway In` | Model Composer → HDL → Basic Elements |
| `Delay` | Model Composer → HDL → Basic Elements |
| `Gateway Out` | Model Composer → HDL → Basic Elements |
| `Outport` | Simulink → Sinks |

Wire them left to right:

```
Inport1 → Gateway In1 → Delay1 → Gateway Out1 → Outport1
```

Set the parameters by double-clicking each block:

| block | parameter | value |
|---|---|---|
| Gateway In | Number of bits | `16` |
| Gateway In | Binary point | `14` |
| Gateway In | Sample period | `Tclk` |
| Gateway In | Quantization | `Truncate` |
| Gateway In | Overflow | `Wrap` |
| Delay | Latency | `4` |

`Tclk` works because this model's `PreLoadFcn` defines it (`clk = 500e6`,
`Tclk = 1/clk`). If MATLAB complains that `Tclk` is undefined, run `clk = 500e6;` and
`Tclk = 1/clk;` in the command window first.

Now select your five blocks, copy (`Ctrl+C`), paste three times, and fix the wiring of
channels 2, 3 and 4. You want **four** independent `Inport → Gateway In → Delay →
Gateway Out → Outport` chains, giving the subsystem 4 inputs and 4 outputs.

## 5. Give the subsystem's ports something outside

Back at the root:

- one `Constant` (Simulink → Sources) for each of the four inputs: value `0`,
  sample time `Tclk`;
- one `Terminator` (Simulink → Sinks) on each of the four outputs.

Wire each Constant into one input, and each output into one Terminator. Nothing else is
needed — the gateways are the IP's interface; these blocks only satisfy Simulink.

## 6. Configure the Hub

Double-click `Vitis Model Composer Hub` and set, on the main tab:

| field | value |
|---|---|
| Export type | **IP Catalog** |
| Part | `xczu48dr-fsvg1517-2-e` |
| Target directory | absolute path, e.g. `/media/.../RFSoC_ZCU208_DOA_V7_BuildKit/build/mc_gui/code` |
| Netlist directory (`directory`) | absolute path, e.g. `.../build/mc_gui/netlist` |
| Clock frequency | leave at `200` |
| Subsystem | **select `DDC_DUT` from the selector** — this is the field that was empty and produced `ERROR-XMC-2001: Did not find top level subsystem ''` |

Press **Apply**. The two directories must exist and be writable — create them from the
command window if needed:

```matlab
mkdir(fullfile(pwd, 'code')); mkdir(fullfile(pwd, 'netlist'));
```

## 7. Validate before generating

Menu: **Simulation → Update Diagram** (`Ctrl+D`).

No dialog may appear. This is the check that caught every broken model in the scripted
runs: an unconnected port, a leftover line, a vector/scalar mismatch all show up here in
words. Fix whatever it names before going on.

## 8. Generate

Press **Generate** in the Hub dialog (label varies by release: *Generate*, *Apply and
Generate*, or the arrow button). Watch the MATLAB command window.

What you are hoping for, in order:

```
### Generating code for DDC_DUT
...
IP_Flow 19-1486 Integrity check passed
```

then a `component.xml` appears under the netlist directory, e.g.

```
build/mc_gui/netlist/ip/DDC_DUT/DDC_DUT.srcs/sources_1/ip/.../component.xml
```

Find it with:

```matlab
d = dir(fullfile(pwd, '**', 'component.xml'));
for k = 1:numel(d), fprintf('%s\n', fullfile(d(k).folder, d(k).name)); end
```

## 9. Put it where the build expects it

```bash
IP_REPO=$(grep -m1 '^IP_REPO' config.mk | cut -d= -f2- | tr -d ' ')
# pick the directory printed in step 8 and copy its parent into the IP repository:
mkdir -p "$IP_REPO/model_composer_channelizer"
cp -r <that ip directory>/* "$IP_REPO/model_composer_channelizer/"
python3 scripts/check_ip_component.py "$IP_REPO/model_composer_channelizer/component.xml" --any-ports
```

`check_ip_component.py` prints the VLNV and the port list; set the VLNV fields in the Hub
(`IpVendor`, `IpLibrary`, `IpVersion`) before generating if you want
`doa.v7:model_composer:channelizer:1.0` rather than AMD's defaults.

---

## What each error means, from this project's runs

| message | cause | action |
|---|---|---|
| `ERROR-XMC-2001: Did not find top level subsystem '' specified in the Model Composer Hub` | no subsystem chosen in the Hub | step 6: select `DDC_DUT` in the selector, press Apply |
| `ERROR-XMC-2002: Unsupported block ... for code generation` | this check belongs to the HLS code-generation flow (`IpLibrary = hls`), which rejects every HDL block — AMD's own design fails it too | keep Export type = **IP Catalog**; do not press any "generate code" button |
| `Index exceeds the number of array elements` | the tool indexing the empty subsystem name — same root cause as XMC-2001 | same fix as the first row |
| `Unconnected line found in 'SSRDDC'` | a line stub left after deleting the testbench | delete the stub at the root; `Ctrl+D` until clean |
| `Invalid setting for input port dimensions ... Demux` | a scalar wired into AMD's vector (`Vector Real Gateway Out`) block | use the plain `Gateway Out`, as in step 4 |
| `Invalid parameterization: Sample period ... must be greater than 0` | sample period set to `-1` | set it to `Tclk` |
| generation stops after `Generating code` with nothing more | engine finished, GUI did not hand back | check for `component.xml` before believing it failed |

## If the IP Catalog export still refuses the design

Two fallbacks, in order of cost:

1. **Prove the flow first.** Export `Gateway In → Gateway Out` only (no delay), with the
   same Hub settings. If that writes a `component.xml`, the flow works and the delay block
   is what this install's checker objects to; add the delay back afterwards and, if it is
   still refused, implement the four-clock latency in your own HDL instead.
2. **Use the verified IP.** `make ip-from-hdl` writes
   `$(IP_REPO)/channelizer_ip/component.xml` as `doa.v7:model_composer:channelizer:1.0`
   from `rtl/channelizer/channelizer_dut.v`, and `make ip-equivalence` measures it against
   this kit's Model Composer model:

   ```
   bit-exact: 16384 samples, 4 channels, depth 4: MATCH
   gateway error 6.103e-05 = 1.000 LSB
   RESULT=PASS
   ```

## What the GUI has that the script did not

The scripted runs spent a day on four defects that a person never makes:

- it wrote the subsystem's name into `IPInfoJsonString` and never into `hub.SubsystemName`,
  the field the compiler actually reads — the dialog's selector writes both;
- it deleted AMD's testbench blocks and left seventeen line stubs behind, which broke the
  pre-export simulation;
- it set the gateway sample period to `1`, then to `-1` (refused), before `Tclk` — the
  dialog refuses invalid values as you type;
- it called `xmcGenerateButtonPressed`, which drives the HLS code-generation check and
  rejects every HDL block, AMD's included.

The model those runs ended with — four `Inport → Gateway In (16.14, Tclk) → Delay (4) →
Gateway Out → Outport` chains, root holding only the Hub and the design, 0 unconnected
ports, `Ctrl+D` clean — is exactly what steps 3–7 above build by hand.
