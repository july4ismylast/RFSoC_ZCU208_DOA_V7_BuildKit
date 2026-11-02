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
exists in the MATLAB side (`estimate_multifrequency_calibration.m`); the
array remains unambiguous across the band: diagonal baseline 35.4 mm < λ/2
up to ≈4.24 GHz.

**Analog prerequisite:** a preselector/band‑pass in front of the 4 ADCs
must reject Zone‑1/Zone‑3 energy that would alias into the band; the
digital DDC filter cannot undo analog aliasing. ADC Nyquist‑zone and
calibration settings for Zone‑2 operation are applied with the RFDC
configuration (initial BD values + runtime driver where PG269 requires it).

## 3. RFDC target configuration (2023.2 property evidence)

The user-PC dump (2026-11-02) proved RFDC VLNV
`xilinx.com:ip:usp_rf_data_converter:2.6`, cell
`/usp_rf_data_converter_1`, Tiles 0+1 at 4 GSPS/MTS, all eight datapath
slices `00..03/10..13` enabled, current streams only
`m00/m02/m10/m12_axis`, and the exact property spellings below. (The
dump's `list_property_value` section is empty because BD `CONFIG.*`
properties are string-typed in Vivado; the enum labels live in the IP-XACT
`component.xml`, which the revised dump now extracts. The numeric R2C
pattern itself is independently proven by the pinned upstream SAM/PYNQ
ZCU208 BD Tcl and by AMD's RFdc driver constants.)

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
| `CONFIG.ADC_Mixer_ModeXX` | 2 | **0** | bypass/R2R encoding → **Real→I/Q** encoding used by SAM/PYNQ R2C designs |
| `CONFIG.ADC_Mixer_TypeXX` | 1 | **2** | Coarse → **Fine** |
| `CONFIG.ADC_Data_WidthXX` | 8 | **8** | 8 samples/AXIS cycle per I and Q stream |
| `CONFIG.ADC_NCO_FreqXX` | 0.0 | **-3.0** | GHz, absolute `-F_C`; default centre 3.000 GHz |
| `CONFIG.ADC_NCO_PhaseXX` | 0 | **0** | identical phase; runtime SYSREF/tile-event reset still required |
| `CONFIG.ADC_NyquistXX` | 0 | **even-zone XML choice** | Zone 2; numeric value is taken from the 2.6 `component.xml`, not guessed |
| `CONFIG.ADC_CalOpt_ModeXX` | 1 | **Mode 2 XML choice** | PG269: Mode 1 only within ±10% of `Fs/2`; the 2.25–3.75 GHz band is otherwise |
| `CONFIG.ADC0_Fabric_Freq`, `ADC1_Fabric_Freq` | 500.000 | **250.000 after validate** | required AXIS clock `2.0 GS/s ÷ 8`; `ADCn_Outclk_Freq` stays 250.000 |

Sampling rate, clock source/distribution, MTS membership, dither and the
enabled-slice set stay as in the V03-proven MTS base; ADC tiles 2/3 stay
disabled. In R2C mode the stream set becomes, per physical channel,
even stream = **I** and next odd stream = **Q**:
`ch0=m00/m01`, `ch1=m02/m03`, `ch2=m10/m11`, `ch3=m12/m13`.
The MTS ADC BRAM/DDR capture hierarchies are built for the old 500 MHz
real contract, so V07 disconnects/removes them **in the work BD only**
(the base stays untouched), moves `m0/m1_axis_aclk` to `clkRFdiv2`
(250 MHz), and connects the DOA path instead.

## 4. PL stream / clock contract

| Domain | Contract |
|---|---|
| RFDC output (per channel) | I stream 128‑bit (8×s16) + Q stream 128‑bit @ **250 MHz** → 2.0 GS/s complex |
| Gearbox output (V05 `rfdc_repack4`) | channel‑aligned complex SSR‑8 vectors @250 MHz (word = `{Q,I}`, lanes = consecutive time samples); search branch is never back‑pressured by the DOA capture branch |
| Channelizer (V06) | input SSR‑8 complex @250 MHz ×4 ch; **1024 bands** → spacing **1.953125 MHz**; one bin‑vector snapshot every 1024 input samples (snapshot rate **1.953125 MHz**) |
| Search (`spectrum`/`candidate`) | bins at SSR‑8 average rate; an 8‑lane version of the spectrum/candidate packing is a V06 decision with csynth proof (the current 4‑lane/512‑bit IPs remain the low‑rate DOA-side contract) |
| DOA capture (`covariance`) | bin selector packs 4 snapshots of the candidate bin into the existing **512‑bit lane‑major beat** in a **125 MHz** domain (`clkRFdiv2` ÷2, async FIFO crossing); 4096 snapshots = **2.097 ms** at the snapshot rate |
| Control | PS AXI‑Lite domain as in the MTS base; HLS `s_axi_ctrl` via SmartConnect (V07), separate reset per clock domain (upstream pattern) |
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
- [ ] Revised dump run: IP-XACT choice labels for `ADC_Nyquist00`/`ADC_CalOpt_Mode00` (and mixer/data enums), `MTSclkwiz` outputs, RFDC stream `TDATA` widths.
- [ ] Scratch-copy apply proof: candidate CONFIG diff accepted, odd Q streams appear, readback of all eight slices identical in effect.
- [x] V05 gearbox source/testbench implemented against §4 (`ip/custom/rfdc_repack4`, `V05_RFDC_REPACK4_SPEC.md`); Vitis HLS 2023.2 acceptance run is tracked by that spec's gates. Post-channelizer capture selector is specified with V06's output format.
- [ ] V06 channelizer feasibility evidence (1‑ch synth) before any step08 integration attempt.

Next stages: **V05** `rfdc_repack4` + bin‑select/capture gate →
**V06** wideband channelizer → **V07** `bd_map` integration (RFDC apply
Tcl from the dump, SmartConnect, clocks/resets, addresses) → step08/09.
