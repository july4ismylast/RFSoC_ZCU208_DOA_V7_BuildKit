# Stage V03 — RFSoC-MTS ZCU208 base under the Vivado 2023.2 lock

**Locked decisions (2026-11-01):** Vivado/Vitis **2023.2** · base = **Xilinx
RFSoC-MTS** `boards/ZCU208` (standard MTS; the same MTS design also exists for
RFSoC4x2 — we use the ZCU208 one) at pinned commit
`f8e93e7f89d0e80f0e4edf5a2ea4b45f0fcd6d3d` · RF target **2–4 GHz** ·
**4 ADC channels**. Part `xczu48dr-fsvg1517-2-e`, board
`xilinx.com:zcu208:part0:2.0`. All IP VLNVs: `config/ip_versions.tcl` (V00).

## Why V03 is an *upgrade* stage, not just "run make"

Upstream `mts.tcl` says in its header: *Vivado v2022.1.2*. Its CHECK-IPs list
and PS instantiation use `xilinx.com:ip:zynq_ultra_ps_e:3.4`. In Vivado
2023.2 the PS IP is **3.5** (introduced in 2023.1; AMD Answer Record
000035673), so the pristine script stops in its CHECK IPs section. Every
other catalog IP in MTS (`usp_rf_data_converter:2.6`, `axis_data_fifo:2.0`,
`axi_dma:7.1`, `smartconnect:1.0`, `clk_wiz:6.0`, `ddr4:2.2`, …) is unchanged
in 2023.2 — that is what `make step00_preflight` proves on your PC.

## What "4 ADC" means in the standard MTS design (our starting map)

The ZCU208 MTS base captures exactly the four physical ADC channels we need:

| DOA channel (proposed) | RFDC stream in MTS BD | Captured today by |
|---|---|---|
| 0 | `usp_rf_data_converter_1/m00_axis` (Tile 0, ADC0) | `hier_adc0_cap` (BRAM) |
| 1 | `usp_rf_data_converter_1/m02_axis` (Tile 0, ADC2) | `hier_adc1_cap` (BRAM) |
| 2 | `usp_rf_data_converter_1/m10_axis` (Tile 1, ADC0) | `hier_adc2_cap` (BRAM) |
| 3 | `usp_rf_data_converter_1/m12_axis` (Tile 1, ADC2) | `deepCapture` (DDR4 DMA) |

Analog top ports: `vin0_01`, `vin0_23_0`, `vin1_01` (+ DAC loopback ports we
will disable in V04, not now). MTS settings to keep **untouched in V03**:
ADC 4 GSPS direct clocking from CLK104 (`xrfclk/LMX2594_4000.0.txt`,
`LMK04828_500.0.txt`), Tile0+Tile1 `Multi_Tile_Sync=true`, the whole
`clocktreeMTS` (SYSREF `util_ds_buf` + `xpm_cdc_gen` + `clk_wiz`) and per-domain
`proc_sys_reset`s. Channel→physical SMA/XM650 mapping for *your* antennas is
confirmed at V04/board time; until then use the order above.

*RF note for 2–4 GHz (handled in V04, recorded now):* with Fs = 4 GSPS the
band 2–4 GHz is exactly Nyquist Zone 2. A target signal must sit inside the
zone with margin ≥ BW/2 from 2.0/4.0 GHz (the MATLAB default centre of
4.0 GHz would alias to DC at Fs = 4 GSPS). V04 will fix the decimation/NCO
plan and reconcile it with the MATLAB `Fs = 2.048e9` search model and the
512 MS/s @ 128 MHz covariance contract.

## Run order on your Vivado 2023.2 PC

```bash
# 0) version lock + catalog proof (V00/V01; needs Vivado+Vitis HLS 2023.2 on PATH)
make step00_preflight
#    -> build/output/ip_catalog_lock.txt must show PASS for every catalog IP.
#    If one line FAILs, send me that file; we fix one line in ip_versions.tcl.

# 1) build the custom IP so step07 can run later (Vitis HLS 2023.2, exact TBs)
#    STATUS 2026-11-02: DONE on the user PC -- step00..step06 all PASS
#    (step05/06 proven with CHANNELIZER_FLOW=opfb; the production matlab_hdl
#    channelizer run is still owed before final V06 integration, but step07
#    only needs the step06 manifest, which exists).
make step02_hls_covariance step03_hls_spectrum step04_hls_candidate step04_hls_beam
make step05_channelizer CHANNELIZER_FLOW=matlab_hdl   # + MATLAB R2024a
make step06_collect_ip
#    -> manifest must show covariance:7.1 spectrum:2.0 candidate:1.0 beam:2.1
#       (beam 2.1 = ap_ctrl_none fix; covariance 7.1 = AXIS register_mode fix)

# 2) fetch the pinned MTS base and make the controlled 2023.2 adaptation copy
make step01_fetch_references FETCH_SET=RFSoC-MTS
./scripts/prepare_mts_2023p2_patch.sh
#    -> diff printed by the script must show ONLY: PS 3.4->3.5 (x2) +
#       impl_1 strategy -> Performance_ExtraTimingOpt (x3)

# 3) create the unmodified MTS project in 2023.2 (first failure = information)
cd build/mts_base_src_2023p2/boards/ZCU208/build_mts
vivado -mode batch -source mts.tcl
```

**Expected first-run outcomes:** ✅ project `mts/` is created and the BD opens,
or ❌ Vivado stops on a renamed/removed PS 3.5 `CONFIG.PSU__*` property or a
2022 run-flow name. In the ❌ case **do not improvise edits**: save the
complete Vivado log and send it; each incompatibility gets one recorded patch
line in `scripts/prepare_mts_2023p2_patch.sh` (same pattern as the PS VLNV),
then re-run from a clean `build/mts_base_src_2023p2`.

### First-run evidence (2026-11-02, user Vivado 2023.2 PC)

Better than expected: **no PS-property failure at all.** With only the PS
3.4→3.5 substitution, `mts.tcl` created the project, the BD validated, and
`make bitstream` ran synth + impl + `write_bitstream` to completion
(DRC 0 errors; `mts_wrapper.bit` written). The one failing gate is upstream
`make check_timing`: the routed timing summary ends at
**WNS = −0.017 ns, TNS = −0.050 ns, WHS = +0.010 ns** (hold is fine), all in
clock `clk_out1_mts_MTSclkwiz_0` (the 500 MHz `clkRF` domain). The worst
endpoints sit in `deepCapture` (`axis_data_fifo_adc` BRAM output,
`axis_dwidth_converter_0` upsizer) fed by RFDC `m12_axis`; the router's
built-in physical synthesis already improved WNS from −0.180 to −0.017.
A bitstream that fails its own timing check is **not** signoff, so at that
point gate 3 was not passed and step07 stayed blocked (timing closure
below).

Timing-closure path (implementation-only — still no BD/clock/RFDC edits):
first run the non-destructive probe on the existing routed checkpoint
(`phys_opt_design -directive AggressiveExplore`), **from the repo root**
(it locates the checkpoint under `build/mts_base_src_2023p2/...` itself):

```bash
vivado -mode batch -source common/vivado/v03_postroute_physopt_probe.tcl 2>&1 | tee $HOME/mts_v03_physopt_probe.log
grep "PROBE RESULT" $HOME/mts_v03_physopt_probe.log
```

**Probe result (2026-11-02): improved but not closed** — worst setup slack
−0.017 → **−0.009 ns** (TNS −0.033, only 6 failing endpoints of 199244,
WHS +0.010). So adaptation #2 is now encoded in
`scripts/prepare_mts_2023p2_patch.sh`: `impl_1` strategy
`Vivado Implementation Defaults` → **`Performance_ExtraTimingOpt`**
(timing-driven place/route; implementation effort only — synthesis, BD,
clocks, RFDC and constraints unchanged; the routed timing summary remains
the signoff report upstream `check_timing.tcl` reads). Re-run V03 from a
clean adapted tree:

```bash
./scripts/prepare_mts_2023p2_patch.sh
# diff must show ONLY: PS 3.4->3.5 (x2) + impl strategy (x3)
cd build/mts_base_src_2023p2/boards/ZCU208/build_mts
make 2>&1 | tee $HOME/mts_v03_extratimingopt_make.log
# = block_design -> bitstream -> check_timing -> handoff
```

**Second-run evidence (2026-11-02): gate 3 PASS.** The clean re-run above
completed block_design → bitstream → check_timing → handoff
(“Built overlays successfully!!”, XSA validated): routed summary
**WNS = +0.021 ns, TNS = 0.000 (0/199255 failing), WHS = +0.009 ns,
THS = 0.000** — “All user specified timing constraints are met” — with
`mts.bit` (33 MB), `mts.hwh` (1.2 MB) and `mts.xsa` (3.6 MB) produced.
The `Performance_ExplorePostRoutePhysOpt` fallback is therefore not
needed; it stays recorded in the prepare script only as the next lever if
a future re-run regresses.

Remaining before step07 are gates 2 + 4, now one command from the repo
root (read-only audit; never saves the base):

```bash
vivado -mode batch -source common/vivado/v03_report_mts_base.tcl 2>&1 | tee $HOME/mts_v03_base_audit.log
grep -iE "locked|outdated" build/output/v03_mts_report_ip_status.rpt   # gate 2: must be clean
make step07_vivado_project && make status
```

## V03 acceptance gates (all must pass before V04 touches RFDC settings)

1. Adapted `mts.tcl` completes in Vivado **2023.2**; `validate_bd_design` = 0 errors.
   *(✅ 2026-11-02.)*
2. In that project: *Report IP Status* shows **no locked/outdated IP**
   (Tcl: `report_ip_status`); `get_property PART` = `xczu48dr-fsvg1517-2-e`,
   `BOARD_PART` = `xilinx.com:zcu208:part0:2.0`.
   *(Run `common/vivado/v03_report_mts_base.tcl` — pending at time of writing.)*
3. **Unmodified base** (still no DOA blocks) synthesises
   (`make` in build_mts, i.e. block_design → `build_bitstream.tcl` wrapper →
   bitstream → `check_timing.tcl` → `handoff.tcl`) with timing met. This
   proves tool + board clocking before we change a single RFDC setting.
   *(✅ 2026-11-02 with the recorded `Performance_ExtraTimingOpt` impl
   strategy: WNS +0.021 ns / WHS +0.009 ns, XSA validated — see evidence
   above. Defaults had failed by −17 ps; post-route phys-opt probe −9 ps.)*
4. The result is the base for step07: `config.mk` now defaults (for
   `BASE_KIND=mts`) to
   `BASE_XPR=$(BUILD)/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr`
   and `BASE_BD=mts`, so no manual environment setting is needed. Still
   export `write_bd_tcl` + `report_ip_status` outputs into `build/output/`
   so the 2022.1.2 → 2023.2 delta stays reviewable.

Only after gate 4: `make step07_vivado_project` (which refuses any
non-2023.2 Vivado, verifies part + board part, and appends — never
overwrites — IP repo paths; if the V03 output is missing it now stops with
the exact V03 commands instead of a bare "BASE_XPR is empty"), then V04
(4-slice RFDC + 2–4 GHz sample-rate plan), V05 (gearbox `rfdc_repack4`),
V06 (channelizer), V07 (bd_map integration).

**Never in V03:** changing MTS clock/SYSREF wiring, ADC sample rates, tile
enables, or DAC loopback structure; building the pristine MTS in Vivado
2024.1/2025.2 "because it was open"; committing the generated `mts/` Vivado
project into git (commit only the patch script + reports + this document).
