# Stage V06 — wideband channelizer feasibility

**Status after V04/V05:** the RFDC configuration transaction is proven in
scratch (4 GSPS, Fine Real→I/Q DDC, decimation 2, MTS persisted), and
`rfdc_repack4` is accepted in Vitis HLS. **V06 Gates 0 and 1 passed on
the user PC (MATLAB R2024a, 2026-11-03)**: the one-channel SSR-8/1024
`dsphdl.Channelizer` object configuration works in fixed point, and HDL
Coder generated the corresponding one-channel Verilog with no HDL-check
errors, warnings or messages. **Gate-2 one-channel OOC synthesis also
returned script PASS**, with strong post-synthesis setup slack, but the
four-channel LUT extrapolation is a major integration risk. The
hierarchical review identifies the mechanism: the polyphase FilterBank
uses 63,439 of 88,534 LUTs, including 55,952 SRL delay LUTs, while the
FFT uses 25,095 LUTs and the whole channelizer uses no BRAM. **Gate 2R
has now run and is a dead end:** the same-RTL
`AreaMapLargeShiftRegToBRAM` synthesis completed with script PASS but
produced exactly zero resource change and still used no BRAM.
**Gate 2T is therefore the current experiment:** regenerate the same
production-size object with `Direct form transposed`, keep its reports
and RTL isolated from the systolic baseline, and run the same
one-channel OOC synthesis. Its transposed probe has passed with a
351-cycle latency and the same signed 26/24 output; the corrected
Gate-1/Gate-2T rerun is the immediate step. Plan A is not selected yet;
Gate-2T, the
actual MTS-base utilization, the integrated x4 budget and Gate-3
numerical ordering remain before any V07/`step08` integration is
attempted.

## 1. One-channel target contract

| Item | V06 requirement |
|---|---|
| Input, one antenna channel | SSR-8 complex stream from V05 `rfdc_repack4`: 8 × `{Q[15:0], I[15:0]}` per 250 MHz cycle = 2.000 GS/s |
| Channelizer | critically sampled PFB/FFT, **1024 bands**, prototype **12 taps/band** (12,288 coefficients), production reference stopband target 100 dB |
| Output snapshot | 1024 complex bins per 1024 input samples; with SSR-8 serialized output this is 128 output beats/snapshot |
| Snapshot/bin spacing | 2.000 GHz / 1024 = **1.953125 MHz** |
| Clock gate | one channel must synthesize for `xczu48dr-fsvg1517-2-e` at **4.0 ns** with non-negative slack before x4 extrapolation is reviewed |
| Coherence gate | all four production channels must be identical instances with identical latency, scaling and bin ordering |

The existing `ip/matlab/channelizer_hdl` harness originated as a legacy
**64-band, four-sample/cycle** model. Gate 1 parameterized that code to
the `config.mk` production values and generated one-channel RTL on
MATLAB R2024a. That is generation evidence only, not synthesis/timing
evidence. Its packaged IP must not be used as the production
channelizer; packaging is blocked in the local Makefile until the
AXI4-Stream wrapper contract is frozen.

## 2. Candidate comparison

| Candidate | Why it is considered | Main risk / adaptation | V06 order |
|---|---|---|---|
| **MathWorks `dsphdl.Channelizer`** | Already used by the repo harness and shares the `dsp.Channelizer` prototype used by the MATLAB reference. MathWorks documents power-of-two vector inputs in the 2–64 range and FFT lengths up to 2^16 for HDL, so SSR-8/1024 is inside the documented envelope: <https://www.mathworks.com/help/dsphdl/ref/dsphdl.channelizer-system-object.html>. Gate-0 probe v2 passed in R2024a with `Normalize=false`, exact peak bin 192, signed 26-bit/fraction-24 output and 1760-cycle latency; Gate-1 generated 227 Verilog files; Gate-2 one-channel OOC synthesis met setup timing at 4.0 ns (WNS +1.630 ns) | Four systolic channels alone extrapolate to **83.27% of CLB LUTs**, leaving only 71,144 LUTs for the MTS base, V05, serializer, DOA/control logic and routing margin. Hierarchical utilization shows the FilterBank is 63,439 LUTs (55,952 SRLs), versus 25,095 LUTs for the FFT; steady-state scaling/phase and complete bin ordering also remain unproven | **Plan A candidate — Gate-2R BRAM directive rejected (zero change); Gate-2T probe PASS at 351 cycles, corrected Gate-1/Gate-2T rerun current** |
| **MazinLab RFSoC_OPFB** | Real RFSoC SSR polyphase filter-bank ecosystem; pinned adapters already exist under `ip/upstream_opfb/`. This is also the user's selected **step05/step06 IP-collection flow** (always pass `CHANNELIZER_FLOW=opfb` on the user PC) | Upstream FFT is fixed **16-way × 4096-point** (`ssrfft_16x4096_axis`) and the surrounding HLS/IP interfaces do not match our SSR-8/1024 contract without redesign or a contract change | Plan B if Plan A fails API/scaling/resource/timing; collection alone does not close V06 |
| **AMD FIR Compiler + AMD FFT, hand-assembled SSR PFB** | FIR Compiler 7.2 is already pinned; AMD IP would be native to Vivado 2023.2 | AMD FFT VLNV/version is not yet checked or pinned (required by the V00 rule); commutator, coefficient banks, scaling and SSR ordering become custom design work | Plan C |
| **Custom HLS/RTL PFB** | Maximum control over interface and scaling | No exact SSR-8/1024 implementation exists in the audited repos; highest verification and timing-closure risk | Last resort |

The other audited upstream projects (RFSoC-MTS, PYNQ, SAM, SPEAR) are RFDC,
clocking or beamforming references; none supplies a suitable 1024-band
SSR-8 PFB channelizer for this stage.

## 3. V06 gates

### Gate 0 — MATLAB API/vector probe (PASS, 2026-11-03)

**Attempt 1 result (user PC, MATLAB R2024a, 2026-11-03): FAIL, with the
API portion proven.** The 1024-band × 12-tap/band prototype had 12,288
coefficients, `dsphdl.Channelizer` constructed, fixed-point SSR-8 input
was accepted, the output was 8×1, and `getLatency` and the measured
first-valid latency both equalled **1760 cycles**. The overall probe
failed only at `V06:ToneNotConcentrated`: with `Normalize=true`, the
output type was signed 16-bit/fraction-length-24 and the peak magnitude
was `1.33280037493e-07` (about **2.2 output LSBs**), giving
`TOP1_ENERGY_FRACTION=0.00925925925926` and
`TOP5_ENERGY_FRACTION=0.0388888888889`. That is a fixed-point
scaling/quantization failure of the tested settings, not evidence that
SSR-8/1024 exceeds the object envelope. Preserve the attempt-1 report
before rerunning, for example as
`build/output/v06_channelizer_probe_attempt1_normtrue_FAIL.rpt`.

Probe **v2** changes only the scaling investigation, not the production
contract. Its defaults are `Normalize=false` (the setting in the
MathWorks `dsp.Channelizer` vs `dsphdl.Channelizer` comparison example),
coefficients from `tf()` (the MathWorks HDL example path), the existing
`Direct form systolic` structure, and four collected snapshots with the
assertion applied to the last one. It also logs `coeffs()`/`tf()`
max/sum/difference and output magnitudes in LSBs so a second failure
identifies whether coefficient extraction, filter-output casting or FFT
scaling is responsible. `V06_NORMALIZE=1` reproduces attempt 1 if ever
needed; do not use it for the v2 gate run.

**Attempt 2 / probe v2 result: PASS.** `coeffs()` and `tf()` were
exactly identical (`COEFFS_TF_MAX_ABS_DIFF=0`, maximum coefficient
`0.0009765625 = 1/1024`, coefficient sum `1.00001110531`). With
`Normalize=false`, the output type became signed
**26-bit/fraction-length-24**; the object produced 512 valid SSR-8 beats
(4096 outputs) after the same 1760-cycle latency. Every collected
snapshot peaked at serial index **192**, exactly the nominal tone bin.
The asserted fourth snapshot had peak magnitude
`0.00666898489238` (**111887 output LSBs**),
`TOP1_ENERGY_FRACTION=0.792960089099` and
`TOP5_ENERGY_FRACTION=0.997469835074`, ending in
`V06 CHANNELIZER PROBE RESULT=PASS`. Gate 0 is closed. The peak
magnitude was still increasing over snapshots 1–4, so this result does
not freeze steady-state gain; Gate 3 must run beyond the 12-snapshot
prototype-fill interval before comparing absolute gain and phase.

Run exactly (regression/reproduction only):

```bash
make -C ip/matlab/channelizer_hdl probe
```

This executes `v06_probe_ssr8_1024.m`. It must prove, in the installed
MATLAB/DSP HDL release and without generating HDL:

- the 1024-band × 12-tap/band prototype has 12,288 coefficients and the
  `coeffs()`/`tf()` coefficient statistics are recorded;
- `dsphdl.Channelizer` constructs with the selected coefficients;
- fixed-point `fi(...,1,16,15)` complex data is accepted as 8×1 vectors;
- `OutputSize='Same as input size'` returns 8×1 data;
- `getLatency` (if available), measured first-valid cycle, output type and
  valid-beat count are recorded;
- one deterministic tone produces a dominant channel in the last
  collected 1024-output snapshot, with peak/RMS magnitudes far above one
  output LSB.

Expected final line in `build/output/v06_channelizer_probe.rpt`:

```text
V06 CHANNELIZER PROBE RESULT=PASS
```

A Gate-0 PASS proves only the MATLAB object/configuration path. It does
**not** prove HDL generation, FPGA resources, timing, AXI4-Stream
packaging, exact bin order, or numerical equivalence to the reference.

This probe is independent of the user's OPFB IP-collection selection.
For step05/step06 on the user PC, do **not** rely on the repository
default; use the OPFB override recorded in
`ip/upstream_opfb/README.md`:

```bash
make rebuild STEP=step06_collect_ip CHANNELIZER_FLOW=opfb
```

If probe v2 fails, stop. Do not run `make hdl`, `make package` or
`step08`; return the full v2 probe report for diagnosis.

### Gate 1 — parameterize the Simulink/HDL harness (PASS, 2026-11-03)

**Attempt 1 (2026-11-03): harness FAIL before HDL generation.** The
Gate-0 report was valid, but `report_value` used a MATLAB regexp
capture `(.*)`; because MATLAB `.` matches newlines by default, the
parser captured the remainder of the Gate-0 report as the
`PROBE_VERSION` value and raised `V06:Gate1Gate0Mismatch` before
`HDL_GENERATION_STARTED`. This attempt proves nothing about HDL Coder.
The parser is now strict line-by-line key/value parsing; preserve the
attempt-1 report as
`build/output/v06_gate1_hdl_generation_attempt1_parser_FAIL.rpt` before
rerunning.

**Attempt 2 result: PASS.** HDL generation took **91.491 s** and HDL
check completed with **0 errors, 0 warnings and 0 messages**. The
generated top is `Channelizer_DUT` (8976 bytes, 234 lines, 38 port
declarations), with `clk`, `reset`, `clk_enable`, `validIn`, eight
signed-16 real inputs and eight signed-16 imaginary inputs
(`sfix16_En15`), eight signed-26 real outputs and eight signed-26
imaginary outputs (`sfix26_En24`), `ce_out`, and `validOut`. The
generated tree contains 258 files / 5,294,271 bytes, including **227
Verilog files** and 23 report/HTML/text files. Preserve the successful
report as `build/output/v06_gate1_hdl_generation_PASS.rpt` before any
future Gate-1 rerun. Gate 1 is closed.

The harness code is parameterized from `config.mk`:
`CHANNELIZER_NUM_BANDS=1024`, `WIDEBAND_SAMPLES_PER_CLOCK=8`,
`CHANNELIZER_TAPS_PER_BAND=12`, `CHANNELIZER_STOPBAND_DB=100`, and
`CHANNELIZER_NORMALIZE=0`. `ZU48DRChannelizer.NormalizeFFT` carries the
proved scaling choice into the Simulink MATLAB System block, while
`build_model.m` creates an 8×1 complex `fixdt(1,16,15)` input and the
12,288-coefficient prototype through `tf()`.

Run exactly (regression/reproduction only):

```bash
make -C ip/matlab/channelizer_hdl gate1
cat build/output/v06_gate1_hdl_generation.rpt
```

`v06_gate1_generate_hdl.m` first requires the preserved Gate-0 PASS
report to match the production settings, exact tone/peak bin and
26/24 output type. It then rebuilds the model and calls HDL Coder for
one channel only. The report must record:

- generated top path and module name (`Channelizer_DUT`);
- generated top size/line count and every top-level port declaration
  (up to the script's 250-line logging cap);
- generated-file count/total bytes and HDL Coder report/log filenames;
- Gate-0 latency (1760 cycles) and output type (signed 26/24);
- `PACKAGING_PERFORMED=0`; and
- final `V06 GATE1 HDL GENERATION RESULT=PASS`.

This gate proves only that HDL Coder can emit one-channel RTL for the
proved object settings. It does not prove Vivado synthesis, timing,
resources, numerical equivalence, or an AXI4-Stream interface. Do not
run `make package`, `make package-only`, `step05_channelizer` with the
MATLAB flow, or `step08` from a Gate-1 pass. The local package targets
are intentionally blocked unless a later wrapper stage explicitly sets
`ALLOW_CHANNELIZER_PACKAGE=1`. Gate 2 will synthesize the generated
one-channel RTL out-of-context before any packaging decision.

### Gate 2 — one-channel Vivado OOC synthesis (script PASS; hierarchy reviewed)

**One-channel result (user PC, Vivado 2023.2, 2026-11-03): PASS by the
predefined setup/resource script criteria.** Synthesis of the 227
Gate-1 Verilog files completed in 306 s. Post-synthesis setup timing at
4.000 ns was **WNS +1.630 ns, TNS 0.000 ns, 0/270030 failing
endpoints**. The same summary recorded post-synthesis hold estimates
**WHS −0.075 ns, THS −19.523 ns, 265/270030 failing endpoints**; this
is not a routed hold signoff result and was not a Gate-2 script
criterion, but integrated implementation must eventually close hold as
well as setup.

| Resource | One systolic channel | x4 extrapolation | Remaining after x4 |
|---|---:|---:|---:|
| CLB LUTs | 88,534 / 425,280 (20.82%) | 354,136 (83.27%) | **71,144 (16.73%)** |
| CLB registers | 74,573 / 850,560 (8.77%) | 298,292 (35.07%) | 552,268 (64.93%) |
| Block RAM Tile | 0 / 1080 | 0 | 1080 |
| URAM | 0 / 80 | 0 | 80 |
| DSPs | 312 / 4272 (7.30%) | 1248 (29.21%) | 3024 (70.79%) |

The detailed reports supplied on 2026-11-03 split the one-channel LUT
use as follows:

| Block / LUT class | LUTs | Share of 88,534 | Interpretation |
|---|---:|---:|---|
| `u_FilterBank` | 63,439 | 71.65% | Dominant block; 7,487 logic LUTs, **55,952 SRLs**, 31,002 FFs, 192 DSPs |
| `u_FFT` | 25,095 | 28.35% | 19,553 logic LUTs, 3,824 LUTRAM, 1,718 SRLs, 43,571 FFs, 120 DSPs |
| LUT as Logic (whole DUT) | 27,040 | 30.54% | Not the main problem |
| LUT as Memory (whole DUT) | 61,494 | 69.46% | 3,824 distributed RAM + **57,670 SRLs** |
| Block RAM / URAM | 0 / 0 | — | The long FilterBank histories were not mapped to dedicated RAM by default synthesis |

Each of the 16 real/imaginary `subFilter` instances uses about 3,850
LUTs, of which 3,497 are SRLs, plus 12 DSPs. Thus the first resource
experiment should target the FilterBank delay implementation, not a
narrower FFT datapath. A `Direct form transposed` A/B remains a valid
later test, but it would confound architecture and delay-mapping
changes if run before the synthesis-only BRAM test in Gate 2R.

**Review status: amber/red on LUT capacity.** Four generated
channelizers alone would leave only 71,144 LUTs for the MTS base that
remains after V04/V07 edits, V05 `rfdc_repack4`, the SSR-8-to-serial
snapshot logic, AXI/control/DMA logic, all DOA/search blocks, and
routing margin. Do not treat the script PASS as proof that the complete
four-channel design fits. Gate 2R below has already rejected the
BRAM-directive route; Gate 2T is the current controlled test.
The implemented V03 MTS utilization is still needed for the final x4
budget; the first grep attempt matched only one row because Vivado
pads utilization labels to different column widths, so it is not MTS
evidence yet.

The Gate-2 detailed evidence already collected is:

```bash
sed -n '1,180p' build/output/v06_gate2_utilization.rpt
sed -n '1,220p' build/output/v06_gate2_utilization_hierarchical.rpt
```

Run exactly (regression/reproduction only):

```bash
make -C ip/matlab/channelizer_hdl gate2
cat build/output/v06_gate2_ooc_synthesis.rpt
```

`v06_gate2_ooc_synth.tcl` sources `config/ip_versions.tcl`, enforces the
Vivado 2023.2 lock and pinned part
(`xczu48dr-fsvg1517-2-e`), and requires the Gate-1 PASS report and its
exact generated top. It recursively reads the Gate-1 HDL, applies
`v06_gate2_ooc.xdc`, and runs non-project
`synth_design -mode out_of_context -flatten_hierarchy rebuilt` for one
`Channelizer_DUT` only. It does not run implementation, package IP, or
touch the MTS/DOA block design.

The OOC XDC uses the `config.mk` **4.000 ns** clock, zero input/output
delays for the continuous 250 MHz data/valid boundary, constant
`clk_enable=1`, and a false path from the standalone `reset` port. It
is an internal-module feasibility constraint set, not production BD
constraints.

The summary at `build/output/v06_gate2_ooc_synthesis.rpt` must record
the Vivado version, synthesis elapsed time, checkpoint path, CLB
LUT/register, Block RAM Tile, URAM and DSP used/available values, a
crude x4 extrapolation against the whole part, and WNS/TNS/failing
endpoints. Detailed evidence is written to
`v06_gate2_utilization.rpt`,
`v06_gate2_utilization_hierarchical.rpt`,
`v06_gate2_timing_summary.rpt`, `v06_gate2_timing_paths.rpt`,
`v06_gate2_clocks.rpt`, and `v06_gate2_check_timing.rpt`; the synthesis
checkpoint is `build/v06_gate2_ooc/Channelizer_DUT_ooc_synth.dcp`.

The script returns PASS only if synthesis completes, setup **WNS ≥ 0**,
**TNS = 0** with no failing setup endpoints, and no crude x4 resource
total already exceeds the whole part. A PASS still requires the
follow-on assistant review of x4 channels plus the V03 MTS base, V05
gearbox, search/DOA logic and routing margin; it is not production
timing closure and does not authorize packaging or `step08`.

### Gate 2R — BRAM shift-register A/B on the same RTL (completed; rejected)

**User-PC result (2026-11-03): script PASS, resource hypothesis
rejected.** The 296 s run met the same post-synthesis setup result
(WNS +1.630 ns, TNS 0), but every reported utilization value and delta
was identical to the systolic Gate-2 baseline: 88,534 total LUTs,
27,040 LUT-as-Logic, 61,494 LUT-as-Memory, 3,824 distributed-RAM LUTs,
57,670 shift-register LUTs, 74,573 registers, 312 DSPs, and **0 Block
RAM Tile / RAMB36 / RAMB18 / URAM**. Consequently
`RESOURCE_IMPROVEMENT_MATERIAL=0`; do not rerun this directive as the
V06 resource fix.

The completed experiment was run as:

```bash
make -C ip/matlab/channelizer_hdl gate2r-bram
cat build/output/v06_gate2r_bram_ooc_synthesis.rpt
```

This is deliberately a **one-variable synthesis experiment**. The Tcl
requires the same Gate-1 systolic PASS report and generated top, reads
the same generated Verilog, uses the same pinned part and
`v06_gate2_ooc.xdc`, and changes only:

```tcl
synth_design ... -directive AreaMapLargeShiftRegToBRAM
```

All outputs are isolated under the `v06_gate2r_bram_` prefix and
`build/v06_gate2r_bram_ooc/`; the Gate-2 baseline reports/checkpoint
are not overwritten. No MATLAB model, generated RTL, filter structure,
coefficients, scaling, part, clock, XDC, block design or packaged IP is
changed.

The Gate-2R summary records total and x4 resources and timing exactly
as Gate 2, plus LUT-as-Logic, LUT-as-Memory, distributed-RAM,
shift-register, RAMB36 and RAMB18 rows and deltas against the Gate-2
baseline. Its script PASS kept the Gate-2 meaning—synthesis completed,
post-synthesis setup WNS/TNS passed, and no crude x4 resource exceeded
the whole part—but `RESOURCE_IMPROVEMENT_MATERIAL` separately required
BRAM Tile > 0, at least 20% total-LUT reduction, and an SRL reduction.
All three failed. This disproves the directive for the exact generated
systolic RTL; it does not prove that a different filter architecture or
a custom RAM-based PFB cannot work. Gate 2T below is the next
controlled Plan-A test.

### Gate 2T — Direct-form-transposed A/B (current experiment)

Run these in order, stopping on the first failure:

```bash
make -C ip/matlab/channelizer_hdl probe-transposed
cat build/output/v06_channelizer_probe_transposed.rpt

make -C ip/matlab/channelizer_hdl gate1-transposed
cat build/output/v06_gate1_hdl_generation_transposed.rpt

make -C ip/matlab/channelizer_hdl gate2t-transposed
cat build/output/v06_gate2t_transposed_ooc_synthesis.rpt
sed -n '1,180p' build/output/v06_gate2t_transposed_utilization.rpt
sed -n '1,220p' build/output/v06_gate2t_transposed_utilization_hierarchical.rpt
```

**Attempt status (user PC, MATLAB R2024a, 2026-11-03): transposed
probe PASS; Gate-1 attempts 1–2 failed in the harness and have been
corrected.** The probe kept the exact 12,288-coefficient design
(`COEFFS_TF_MAX_ABS_DIFF=0`), produced an 8×1 signed
26-bit/fraction-24 output, collected 512 valid beats / 4096 outputs,
and peaked at serialized index 192 in every snapshot. Both
`getLatency` and measured first-valid latency were **351 cycles**
(first valid cycle 352), versus 1760 cycles for systolic. The fourth
snapshot again reached 111887 output LSBs with
`TOP1_ENERGY_FRACTION=0.792960089099` and
`TOP5_ENERGY_FRACTION=0.997469835074`; these four startup snapshots are
encouraging but do not replace Gate-3 steady-state ordering/gain/phase
proof.

Gate-1 attempt 1 stopped before HDL generation at `build_model.m`
with `SimulinkBlock:Foundation:BadSetParamValue` / “Option specified
is not valid” for `FilterStructure`. The finite-option MATLAB System
mask does not resolve the former model-workspace variable name
`doaChannelizerFilterStructure` as an option. The correction passes
the exact selected option (`Direct form transposed` or
`Direct form systolic`) directly to `set_param` and removes that
workspace variable. Gate 2T correctly refused to run because the
Gate-1 report was FAIL, so its missing synthesis/utilization reports
in attempt 1 are expected.

Gate-1 attempt 2 passed that `set_param` point but failed during the
model update at `build_model.m:133`: Simulink code generation rejected
the wrapper validator's string array
`["Direct form systolic", "Direct form transposed"]` and explicitly
requested a cell array of character vectors. The accompanying
`validIn` port-width message is a downstream consequence of the core
not compiling, not a new wiring error. The second correction therefore
keeps the property as `char` but changes the validator set to
`{'Direct form systolic', 'Direct form transposed'}`. After pulling
the latest correction, do **not** rerun the already-passed probe;
resume at `gate1-transposed`, then run `gate2t-transposed` only if
Gate 1 passes.

This is an isolated architecture A/B, not a production selection.
`config.mk` still defaults `CHANNELIZER_FILTER_STRUCTURE` to
`systolic`; only the three dedicated targets explicitly select
`transposed`. The probe keeps the proved 1024-band / SSR-8 /
12-tap-per-band / 100 dB / `Normalize=false` contract and writes
`v06_channelizer_probe_transposed.rpt`. Gate 1 then requires that
matching transposed Gate-0 PASS report, verifies that its
`getLatency` value is a positive integer equal to the measured
first-valid latency, and writes RTL below
`ip/matlab/channelizer_hdl/hdl_prj/hdlsrc_transposed/`. The systolic
1760-cycle value is deliberately **not** imposed on transposed because
MathWorks documents latency as architecture-dependent; the A/B still
requires the same signed 26-bit/fraction-24 output and checks the
generated top for sixteen signed 16-bit data inputs and sixteen signed
26-bit data outputs.

Gate 2T consumes only the transposed Gate-1 report/RTL, uses the
default Vivado synthesis directive, and otherwise keeps the pinned
part, 4.000 ns OOC XDC and one-channel scope from Gate 2. Its summary
retains the detailed LUT-logic/memory, distributed-RAM, SRL,
RAMB36/RAMB18 and URAM deltas, and reports
`GATE2T_CLB_LUT_REDUCTION_PERCENT` and
`GATE2T_SRL_LUT_REDUCTION_PERCENT` against the 88,534-LUT /
57,670-SRL systolic baseline. Script PASS has the usual limited
meaning (synthesis completed, post-synthesis setup WNS/TNS passed, and
no crude x4 total exceeded the whole part).
`RESOURCE_IMPROVEMENT_MATERIAL=1` is a separate marker requiring at
least 20% total-LUT reduction plus an SRL reduction; BRAM use is not
required because a transposed implementation could legitimately trade
SRL storage for registers/DSP pipeline state. Even then, FF/DSP
growth, hierarchy, timing, actual V03 MTS-base utilization and the
integrated x4 budget must be reviewed before selecting either Plan-A
architecture. If Gate 2T is not credibly better, do not proceed to
Gate 3 on an unfittable candidate; close the integrated budget with
the real MTS utilization and move to the OPFB / AMD-IP feasibility
path as required.

### Gate 3 — numerical ordering and phase

Compare the HDL-oriented object/RTL against the floating-point
`dsp.Channelizer` reference after latency alignment. Run beyond the
12-snapshot prototype-fill interval and discard startup snapshots
before measuring steady-state gain/phase. Freeze:

- output scalar order over the 128 SSR-8 beats of one snapshot;
- bin index → baseband/RF frequency mapping;
- scaling, saturation/rounding and output word length;
- common per-bin phase rotation (acceptable for cross-channel DOA only
  if bit-identical across all four channels).

Only after Gates 0–3 pass is Plan A selected for V07. If Gate 2 or 3
fails, the same feasibility gates are applied to the MazinLab OPFB
Plan B before any production BD work resumes.
