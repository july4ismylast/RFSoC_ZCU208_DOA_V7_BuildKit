# Stage V04 — RFDC-to-DOA contract (4 ADC, 2–4 GHz, 1.5 GHz realtime BW)

**Inputs locked before this stage:** Vivado/Vitis **2023.2** · base = Xilinx
**RFSoC‑MTS ZCU208** (stage V03 passed: unmodified base builds timing‑closed)
· part `xczu48dr-fsvg1517-2-e`, board `xilinx.com:zcu208:part0:2.0` ·
**4 ADC channels** (2×2 array) · RF operating range **2–4 GHz** ·
**realtime instantaneous bandwidth 1.5 GHz** (user, 2026‑11‑02).
All IP VLNVs stay pinned via `config/ip_versions.tcl`; all rates below are
mirrored as variables in `config.mk` (single source of truth).

This document is a *contract*, not yet a BD change. It fixes numbers that
V05 (gearbox), V06 (channelizer) and V07 (`bd_map` integration) must meet.
Nothing in the MTS clock/SYSREF tree (`clocktreeMTS`, CLK104 programming,
per-domain resets) is redesigned here.

---

## 1. What the MTS base gives us today (evidence, not assumption)

From the pinned `mts.tcl` (adapted only by V03's two recorded changes):

| Item | MTS value |
|---|---|
| ADC sampling | **4.000 GSPS**, direct clocking, `LMX2594_4000.0.txt` |
| SYSREF / PL ref | `LMK04828_500.0.txt`; `clocktreeMTS` MMCM → `clkRF` 500 MHz, `clkRFdiv2` 250 MHz |
| ADC tiles enabled | Tile 0 + Tile 1, `Multi_Tile_Sync=true`, sampling 4 GSPS, refclk 4000 MHz |
| ADC datapaths used | `m00_axis, m02_axis` (Tile 0) and `m10_axis, m12_axis` (Tile 1) — our 4 channels |
| Current datapath mode | Real output, decimation 1×, 8 samples/AXIS word → **128‑bit @ 500 MHz** per channel (proven by `deepCapture` DWC `S_TDATA_NUM_BYTES=16`) into BRAM/DDR capture hierarchies |
| DAC tiles | Enabled for MTS loopback test (kept for HIL; production disable is a V07 decision) |

The DOA side today assumes (MATLAB + HLS): complex samples, 512‑bit beats
(`word=lane*4+channel`, `{Q[31:16], I[15:0]}`), 1024‑band PFB reference at
`Fs=2.048 GHz`, 4096 snapshots. None of that matches 4 GSPS real MTS output
directly — reconciling it is exactly this stage.

## 2. Frequency plan — Nyquist Zone 2, 1.5 GHz instant band

At `Fs = 4.000 GSPS` the 2–4 GHz range is **Nyquist Zone 2**. A real RF
tone `f_RF ∈ [2,4] GHz` aliases to `f_a = Fs − f_RF ∈ [0,2] GHz` with the
spectrum inverted. The default tuned window is:

| Quantity | Value |
|---|---|
| Default RF centre `F_C` | **3.000 GHz** |
| Instantaneous band | **2.25 – 3.75 GHz** (1.5 GHz) |
| Alias centre `Fs − F_C` | 1.000 GHz |
| Alias band | 0.25 – 1.75 GHz (250 MHz guard to both zone edges) |
| RFDC DDC | fine mixer (Real→I/Q), NCO property **`-F_C` = -3.000 GHz** (PG269 absolute-NCO convention; effective sampled-domain shift +1.000 GHz), decimation **2×** |
| Complex output rate | **2.000 GS/s per channel** (≈1.6 GHz usable DDC passband ≥ 1.5 GHz band + guard) |
| Baseband frequency of a tone | `f_bb = f_RF − F_C` (normal, non-inverted axis) |
| RF frequency of FFT/PFB bin `k` | `f_RF(k) = F_C + f_bb(k)` |

Keeping the full 1.5 GHz inside both the Nyquist zone and the DDC passband
constrains the *tunable* centre to roughly **2.8 – 3.2 GHz**; outside that
range the usable instant bandwidth shrinks (zone/filter edges are physics,
not firmware). `F_C` is therefore a runtime variable (PS/RFdc driver NCO
update later), with 3.000 GHz as the BD default.

**Phase convention (must be honoured by the estimator):** the raw Zone‑2
alias is spectrally inverted, but the RFDC NCO sign selects which alias
image is translated to baseband. Following PG269's NCO example, setting the
absolute NCO to `-F_C` returns the **desired, non-inverted** complex
envelope. This contract therefore uses the normal Zone‑1 steering/covariance
convention at the actual RF frequency `f_RF(k)=F_C+f_bb(k)`. (Setting the
opposite effective sign would deliberately select the conjugated/inverted
image; do not do that.) The loopback‑tone HIL test still proves the sign on
hardware before the estimator is trusted. Per-frequency calibration already
exists in the MATLAB side (`estimate_multifrequency_calibration.m`). Array
geometry is owned by `config.mk` (`ARRAY_AXIS_SPACING_M`, 30 mm since V07 §11).
For a square 2×2 the wrap-free condition is `d·√2·sin θ ≤ λ/2`, i.e. a 62°
cone at 4 GHz — the declared ±55° scan. §11 of V07 carries the rule, the
measurement and the 25 mm fallback for a full ±90° field.

**Analog prerequisite:** a preselector/band‑pass in front of the 4 ADCs
must reject Zone‑1/Zone‑3 energy that would alias into the band; the
digital DDC filter cannot undo analog aliasing. ADC Nyquist‑zone and
calibration settings for Zone‑2 operation are applied with the RFDC
configuration (initial BD values + runtime driver where PG269 requires it).

## 3. RFDC target configuration (2023.2 property evidence)

The user-PC dumps (2026-11-02/03) proved RFDC VLNV
`xilinx.com:ip:usp_rf_data_converter:2.6`, cell
`/usp_rf_data_converter_1`, Tiles 0+1 at 4 GSPS/MTS, all eight datapath
slices `00..03/10..13` enabled, current streams only
`m00/m02/m10/m12_axis`, and the exact property spellings below. The
revised dump also extracted the enum labels from the installed RFDC 2.6
IP-XACT `component.xml` (2,789,086 bytes / 53,472 lines in Vivado
2023.2): Data Type `Real=0, I/Q=1`; Decimation values are the literal
factors (`2x=2`); Mixer Mode `Real->I/Q=0, I/Q->I/Q=1, Real->Real=2`;
Mixer Type `Bypassed=0, Coarse=1, Fine=2, Off=3`; Nyquist
`Zone 1=0, Zone 2=1`; Calibration `Mode1=0, Mode2=1, Autocal=2`.
(The first dump's `list_property_value` section is empty because BD
`CONFIG.*` properties are string-typed in Vivado — the IP-XACT choices
above are the authoritative labels. The numeric R2C pattern is also
independently proven by the pinned upstream SAM/PYNQ ZCU208 BD Tcl and
by AMD's RFdc driver constants.) The same run proved the current
streams are 128-bit (`TDATA_NUM_BYTES=16`, `HAS_TKEEP/TLAST/TSTRB=0`,
`HAS_TREADY=1`) on `MTSclkwiz_clk_out1` at 500 MHz, and that
`MTSclkwiz` already generates the needed 250 MHz on `clk_out2`
(`NUM_OUT_CLKS=2`, both outputs used).

Applied identically to the four physical 4 GSPS ADCs, whose GUI pair
indices are `00/02` (Tile 0) and `10/12` (Tile 1) — **identical settings
are a coherence requirement**; any per-channel difference is a DOA defect.
Following the upstream generated Tcl, the apply Tcl writes the even pair
indices and then *reads back* all eight slices plus the resulting stream
pins (odd slices are the Q legs of each pair); it must not assume the odd
values propagated.

| Property (per pair `XX` = 00,02,10,12) | MTS now | V04 target | Meaning |
|---|---:|---:|---|
| `CONFIG.ADC_Data_TypeXX` | 0 | **1** | Real → **I/Q** |
| `CONFIG.ADC_Decimation_ModeXX` | 1 | **2** | **2×** |
| `CONFIG.ADC_Mixer_ModeXX` | 2 | **0** | XML-proven: `Real->Real=2` → **`Real->I/Q=0`** (same value SAM/PYNQ R2C designs use) |
| `CONFIG.ADC_Mixer_TypeXX` | 1 | **2** | Coarse → **Fine** |
| `CONFIG.ADC_Data_WidthXX` | 8 | **8** | 8 samples/AXIS cycle per I and Q stream |
| `CONFIG.ADC_NCO_FreqXX` | 0.0 | **-3.0** | GHz, absolute `-F_C`; default centre 3.000 GHz |
| `CONFIG.ADC_NCO_PhaseXX` | 0 | **0** | identical phase; runtime SYSREF/tile-event reset still required |
| `CONFIG.ADC_NyquistXX` | 0 | **1** | XML-proven: `Zone 1=0` → **`Zone 2=1`** |
| `CONFIG.ADC_CalOpt_ModeXX` | 1 | **1 (no numeric change)** | XML-proven: `Mode1=0, Mode2=1, Autocal=2` — MTS already selects **Mode 2**, which is also the PG269 choice here (Mode 1 is only for inputs within ±10% of `Fs/2`; the 2.25–3.75 GHz band is otherwise). The scratch apply writes `1` explicitly so the intent is recorded, not inherited by luck. |
| `CONFIG.ADC0_Fabric_Freq`, `ADC1_Fabric_Freq` | 500.000 | **250.000 after validate** | required AXIS clock `2.0 GS/s ÷ 8`; `ADCn_Outclk_Freq` stays 250.000 |
| `CONFIG.ADC0_Multi_Tile_Sync`, `ADC1_Multi_Tile_Sync` | true | **true (hard invariant)** | MTS is what makes Tile 0/Tile 1 latency and digital-feature alignment deterministic; a persisted `false` is a V04 failure even if every datapath value is correct |
| `CONFIG.PL_Clock_Freq` (top level) | **100.0** live default (omitted from generated MTS Tcl) | **500.000** | common MTS PL clock: integer multiple of ADC AXIS 250 MHz and DAC AXIS 500 MHz. Write explicitly before the datapath transaction and restore MTS after it; leaving the 100 MHz default made the late ADC MTS restore fail in scratch v1.2, while 500 MHz made the same restore pass and persist in v1.3. Mirrored as `RFDC_PL_CLOCK_HZ` in `config.mk`. |

Sampling rate, clock source/distribution, MTS membership, dither and the
enabled-slice set stay as in the V03-proven MTS base; ADC tiles 2/3 stay
disabled. In R2C mode the stream set becomes, per physical channel,
even stream = **I** and next odd stream = **Q**:
`ch0=m00/m01`, `ch1=m02/m03`, `ch2=m10/m11`, `ch3=m12/m13`.
The MTS ADC BRAM/DDR capture hierarchies are built for the old 500 MHz
real contract, so V07 disconnects/removes them **in the work BD only**
(the base stays untouched), moves `m0/m1_axis_aclk` to `clkRFdiv2`
(250 MHz), and connects the DOA path instead.

**First scratch attempt (2026-11-03, script v1.0) — partial proof:**
every non-rate value above was accepted, **propagated automatically to
the odd Q slices**, persisted across save/reopen, the four Q streams
appeared, and full-BD validate passed (at still-1× the 500 MHz contract
stays self-consistent). Only the *individual* `Decimation_ModeXX=2`
writes were rejected (`[Common 17-39]`, underlying IP_Flow text not in
the v1.0 report), so `Fabric_Freq` correctly remained 500. Diagnosis:
both pairs in a tile share one fabric clock (PG269 System Clocking), so
a one-by-one change transiently demands 250 + 500 MHz in the same tile.

**Second scratch attempt (2026-11-03, script v1.1) — datapath proof,
MTS regression:** the staged atomic `set_property -dict` transactions
fixed the rate change exactly as designed. Persisted readback after
save/reopen showed all eight slices at the table values
(`Decimation_Mode=2`, Fine Real→I/Q, NCO `-3.0`, Zone 2, CalOpt Mode 2)
and both tiles at `Fabric_Freq=250.000`; full-BD validate also passed
in the scratch BD. **But** `ADC0_Multi_Tile_Sync` and
`ADC1_Multi_Tile_Sync` persisted as `false` although the before-state
(and v1.0 at 1×) had `true`. v1.1 printed PASS only because its
assertion set omitted MTS; that is an assertion hole, not V04 closure.
The RFDC configuration logic is known to clear MTS while settings are
being changed, so script **v1.2** checkpoints ADC/DAC MTS after every
stage, skips the direct `Fabric_Freq` write if 250 is already computed,
tests re-enabling ADC/DAC MTS as a late transaction (before validate and,
if necessary, after validate + a second validate), and hard-asserts
MTS plus captured tile clock/source/distribution invariants on the
persisted readback.

**Third scratch attempt (2026-11-03, script v1.2) — correctly FAIL:**
the checkpoint sequence localized the flip exactly. Before the apply and
after the stage-1 mode dict, ADC0/1 and DAC0/1 were all MTS `true` at
500 MHz fabric. After the stage-2 rate dict/retries
(`Data_Width=8` + `Decimation_Mode=2`, ADC fabric 250 MHz), ADC0/1 MTS
was `false`; DAC0/1 stayed `true` at 500 MHz. Stage 3 tuning and the
conditional `Fabric_Freq` step changed nothing. The pre-validate MTS
restore failed, full-BD validate #1 passed with ADC MTS still off, and
the post-validate restore also failed, so validate #2 was not entered.
Persisted state remained ADC MTS `false`/250 MHz and DAC MTS
`true`/500 MHz, with exactly six failures (two restores, two ADC MTS
assertions, two ADC MTS invariants) and no datapath assertion failures.
This eliminates the mixer-mode stage, tuning stage, direct
`Fabric_Freq` write and `validate_bd_design` as the *initial* trigger;
the blocker is the RFDC dependency evaluated by the ADC rate
transaction as a whole.

Script **v1.3** was therefore run as a recorded root-cause experiment,
not a blind retry. It enumerates the live RFDC sync/PL-clock properties
(generated Tcl can omit defaults such as `CONFIG.PL_Clock_Freq`), sets
`PL_Clock_Freq=500.000` before stage 2 if that property exists and is
not already 500 (500 MHz is the common integer multiple of ADC AXIS
250 MHz and DAC AXIS 500 MHz), and only if MTS still flips runs ordered
branches: the ordinary late restore; PL clock 500/250 with both MTS
groups forced through a real false→true transition; ADC-sole-group
sequencing; ADC `m0/m1_axis_aclk` moved to the existing 250 MHz
`clkRFdiv2` net; DAC interpolation 2×/fabric 250 MHz; and a temporary
ADC `Data_Width=4`/fabric 500 MHz probe.

**Fourth scratch attempt (2026-11-03, script v1.3) — PASS, root cause
found:** the live before-state had `CONFIG.PL_Clock_Freq={100.0}` even
though all four MTS flags were true at 500 MHz fabric. v1.3 set it to
`500.000` before stage 2. The stage-2 rate transaction **still**
transiently cleared ADC0/1 MTS (so the pre-write alone is not the whole
rule), but this time the ordinary `D0` late restore immediately after
the final datapath values **passed**. No D1–D6 branch was needed:
`adc_aclk_rewired_250=0`, DAC interpolation/fabric stayed 1×/500 MHz,
full-BD validate passed, and the persisted reopened state was ADC0/1
MTS `true` at 250 MHz, DAC0/1 MTS `true` at 500 MHz, and
`PL_Clock_Freq={500.000}`. The only review warning was that MTS had
been cleared during the apply and restored by diagnostics entry D0.
Compared with v1.2 on the same input BD, the controlled difference is
the explicit PL clock value: **100 MHz default → restore rejected;
500 MHz common PL clock → restore accepted and persisted**.

**Production RFDC transaction locked for V07:** (1) verify the pinned
RFDC 2.6 cell and captured MTS-base invariants; (2) write
`CONFIG.PL_Clock_Freq=500.000` explicitly (from
`RFDC_PL_CLOCK_HZ=500000000`); (3) apply the staged atomic mode, rate
and tuning dictionaries above; (4) re-enable ADC0/1 + DAC0/1
`Multi_Tile_Sync=true` as a late transaction after the final datapath
state; (5) validate, save, reopen and hard-assert MTS, PL clock,
datapath values, streams and `user_sysref_adc/dac` connectivity. This
proves the RFDC CONFIG transaction only: V07 still has to move the ADC
AXIS clocks/resets to 250 MHz, split PL-SYSREF capture by AXIS domain,
replace the old 500 MHz capture path, and connect the eight I/Q streams.

## 4. PL stream / clock contract

| Domain | Contract |
|---|---|
| RFDC output (per channel) | I stream 128‑bit (8×s16) + Q stream 128‑bit @ **250 MHz** → 2.0 GS/s complex |
| Gearbox output (V05 `rfdc_repack4`) | channel‑aligned complex SSR‑8 vectors @250 MHz (word = `{Q,I}`, lanes = consecutive time samples); search branch is never back‑pressured by the DOA capture branch |
| Channelizer (V06) | input SSR‑8 complex @250 MHz ×4 ch; **1024 bands** → spacing **1.953125 MHz**; one bin‑vector snapshot every 1024 input samples (snapshot rate **1.953125 MHz**) |
| Search (`spectrum`/`candidate`) | bins at SSR‑8 average rate; an 8‑lane version of the spectrum/candidate packing is a V06 decision with csynth proof (the current 4‑lane/512‑bit IPs remain the low‑rate DOA-side contract) |
| DOA capture (`covariance`) | bin selector packs 4 snapshots of the candidate bin into the existing **512‑bit lane‑major beat** in a **125 MHz** domain (`clkRFdiv2` ÷2, async FIFO crossing); 4096 snapshots = **2.097 ms** at the snapshot rate |
| Control | PS AXI‑Lite domain as in the MTS base; HLS `s_axi_ctrl` via SmartConnect (V07), separate reset per clock domain (upstream pattern) |
| MTS PL SYSREF | The MTS base generates one `UserSYSREF` in the 500 MHz `clkRF` domain and feeds both RFDC `user_sysref_adc` and `user_sysref_dac`. PG269 places `user_sysref_adc` in the `m0_axis_aclk` domain and `user_sysref_dac` in `s0_axis_aclk`; once ADC AXIS moves to 250 MHz while DAC remains 500 MHz, V07 must split the capture/transfer circuits by domain (or change the DAC fabric plan). The 500 MHz PL clock remains an integer multiple of both 250/500 MHz, and SYSREF must remain an integer submultiple of every PL clock sampling it. |
| Existing HLS IP clocks | IPs were synthesised against a 7.8125 ns (128 MHz) target; running them at 125 MHz is inside that constraint. New wideband IP (V05/V06) is constrained at 4.0 ns. |

**Feasibility gate (before V07 integration):** a single‑channel
SSR‑8 @250 MHz channelizer candidate must produce synthesis utilisation +
timing evidence, and the 4× extrapolation must fit the ZU48DR with margin.
Candidates, in order: MATLAB `dsphdl.Channelizer` vector form (Plan‑A),
Xilinx SSR FFT (windowed FFT channelizer), OPFB‑pattern SSR PFB (Plan‑B
architecture at our rates). The existing 64‑band scalar harness in
`ip/matlab/channelizer_hdl` does **not** meet this contract as‑is.

## 5. What deliberately does not change in V04

* MATLAB algorithm/reference models (they remain the numerical reference;
  hardware bin spacing becomes 1.953125 MHz instead of 2.000000 MHz — a
  parameter, recorded here and in `config.mk`).
* The four custom HLS IPs and their pinned VLNVs (any later lane‑width
  variant is a new IP version under the V00 lock).
* MTS DAC loopback structure (retained for bring‑up/HIL; removal is a
  separate, reviewed V07/V12 decision).
* Physical SMA/XM650 → antenna element order: default
  `ch0←vin0_01 (m00 I/m01 Q), ch1←vin0_23 (m02/m03),
  ch2←vin1_01 (m10/m11), ch3←vin1_23 (m12/m13)`; confirmed against the
  actual board wiring at calibration time, then frozen in `bd_map`.

## 6. V04 acceptance checklist

- [x] Centre/band/decimation/clock numbers locked above and mirrored in `config.mk`.
- [x] First `v04_dump_rfdc.tcl` run reviewed: RFDC 2.6 property names, current MTS values and stream set proven on the 2023.2 PC.
- [x] Revised dump run (2026-11-03, dump v2.1): IP-XACT choice labels for all V04 enums (`Zone 2=1`, `Mode2=1`, `Real->I/Q=0`, `Fine=2`, `I/Q=1`, `2x=2`), `MTSclkwiz` outputs (500/250 MHz, both used), RFDC streams 128-bit with no TKEEP/TLAST/TSTRB.
- [x] Scratch-copy apply proof (2026-11-03, script v1.3): candidate CONFIG diff accepted, odd Q streams appear, readback of all eight slices is identical in effect, full-BD validate passed, and ADC/DAC MTS persisted `true` after save/reopen. Root cause of the earlier MTS regression was the live default `CONFIG.PL_Clock_Freq={100.0}`: setting it explicitly to `500.000`, then restoring MTS after the stage-2 transient clear, gave `V04 SCRATCH CONFIG RESULT=PASS solution=BASELINE_RESTORE_AFTER_DATAPATH` with ADC fabric 250 MHz and DAC fabric 500 MHz. Evidence: user-PC `build/output/v04_rfdc_scratch_apply.rpt` from `common/vivado/v04_scratch_apply_rfdc.tcl` (scratch project only; production work BD untouched).
- [x] V05 gearbox implemented against §4 and accepted on Vitis HLS 2023.2 (2026-11-03: `step05_hls_repack` PASS — CSim bit-exact, csynth II=1/depth 2, estimated Fmax 500 MHz, VLNV `openai:doa:rfdc_repack4:1.0` verified; details in `V05_RFDC_REPACK4_SPEC.md`). Post-channelizer capture selector is specified with V06's output format.
- [ ] V06 channelizer feasibility evidence (1‑ch synth) before any step08 integration attempt — gated plan in `V06_CHANNELIZER_FEASIBILITY.md`; current Gate 0 is the MATLAB SSR‑8/1024 `dsphdl.Channelizer` probe (`make -C ip/matlab/channelizer_hdl probe`).

Next stages: **V05** `rfdc_repack4` + bin‑select/capture gate →
**V06** wideband channelizer → **V07** `bd_map` integration (RFDC apply
Tcl from the dump, SmartConnect, clocks/resets, addresses) → step08/09.
