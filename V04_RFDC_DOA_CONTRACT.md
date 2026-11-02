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
| RFDC DDC | fine mixer (Real→I/Q) tuned to the alias centre, decimation **2×** |
| Complex output rate | **2.000 GS/s per channel** (≈1.6 GHz usable DDC passband ≥ 1.5 GHz band + guard) |
| Baseband frequency of a tone | `f_bb = F_C − f_RF` (inverted axis) |
| RF frequency of FFT/PFB bin `k` | `f_RF(k) = F_C − f_bb(k)` |

Keeping the full 1.5 GHz inside both the Nyquist zone and the DDC passband
constrains the *tunable* centre to roughly **2.8 – 3.2 GHz**; outside that
range the usable instant bandwidth shrinks (zone/filter edges are physics,
not firmware). `F_C` is therefore a runtime variable (PS/RFdc driver NCO
update later), with 3.000 GHz as the BD default.

**Phase convention (must be honoured by the estimator):** Zone‑2 sampling +
down‑conversion conjugates the complex envelope. The spatial covariance
produced by the HLS core is therefore the conjugate of the Zone‑1
convention; the PS estimator either conjugates the covariance or uses the
conjugate steering vector, and uses `f_RF(k)` above for the array manifold.
The exact sign is locked by the loopback‑tone HIL test (V12), not by hope.
Per-frequency calibration already exists in the MATLAB side
(`estimate_multifrequency_calibration.m`); the array remains unambiguous
across the band: diagonal baseline 35.4 mm < λ/2 up to ≈4.24 GHz.

**Analog prerequisite:** a preselector/band‑pass in front of the 4 ADCs
must reject Zone‑1/Zone‑3 energy that would alias into the band; the
digital DDC filter cannot undo analog aliasing. ADC Nyquist‑zone and
calibration settings for Zone‑2 operation are applied with the RFDC
configuration (initial BD values + runtime driver where PG269 requires it).

## 3. RFDC target configuration (logical values; enums proven by dump)

Applied identically to the four used datapaths (`00/02` in Tile 0,
`10/12` in Tile 1) — **identical settings are a coherence requirement**;
any per‑channel difference is a DOA defect:

* Sampling rate 4.000 GSPS (unchanged), MTS on Tiles 0+1 (unchanged),
  clock source/distribution unchanged.
* Digital output data: **I/Q**; mixer type **Fine**; mixer mode
  **Real → I/Q**; NCO set so the alias centre (`Fs − F_C`, default
  1.000 GHz) lands at DC. The *sign* written to the NCO property follows
  the PG269/frontend convention and is proven by the tone test; it is
  stored as one named variable, never buried as a magic enum.
* Decimation **2×**; samples per AXI4‑Stream cycle **8** (per I and per Q
  stream); tile fabric frequency + AXIS clock for ADC streams **250 MHz**
  (`2.0 GS/s ÷ 8 = 250 MHz`, the existing `clkRFdiv2` domain). The MTS
  ADC BRAM/DDR capture hierarchies are built for the old 500 MHz real
  contract, so V07 disconnects/removes them **in the work BD only** (the
  V03-proven base stays untouched) and connects the DOA path instead.
* Nyquist zone **2**; calibration mode per PG269 for the Zone‑2 band.
* Unused ADC tiles (2/3) stay disabled (already so in MTS).

Exact Tcl property names/allowed enum values are **not guessed**:
`common/vivado/v04_dump_rfdc.tcl` dumps them from the built work project
on the 2023.2 PC first; the V07 apply Tcl is then written against that
evidence and reviewed as an RFDC CONFIG diff, slice by slice.

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
  `ch0←m00, ch1←m02, ch2←m10, ch3←m12`; confirmed against the actual
  board wiring at calibration time, then frozen in `bd_map`.

## 6. V04 acceptance checklist

- [x] Centre/band/decimation/clock numbers locked above and mirrored in `config.mk`.
- [ ] `v04_dump_rfdc.tcl` output reviewed (property names + enum values + current MTS settings) on the 2023.2 PC.
- [ ] V05 gearbox spec written against §4 (SSR‑8 pairing + capture selector).
- [ ] V06 channelizer feasibility evidence (1‑ch synth) before any step08 integration attempt.

Next stages: **V05** `rfdc_repack4` + bin‑select/capture gate →
**V06** wideband channelizer → **V07** `bd_map` integration (RFDC apply
Tcl from the dump, SmartConnect, clocks/resets, addresses) → step08/09.
