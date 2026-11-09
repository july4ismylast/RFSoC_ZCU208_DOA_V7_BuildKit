# What was built, how to open it, and what each block does

For the Vivado host that ran the twenty stages. Everything below names a path that
exists after `make pipeline`, or a GUI click in the tool that produced it.

The full click-by-click version — which window, which pane, which button, which setting, for
Vitis HLS, Vivado, MATLAB/HDL Coder and Vitis — is `docs/BLOCK_GUIDE.md` **Part 6**.

---

## 1. What each stage produced

| stage | tool | artifact it leaves behind |
|---|---|---|
| `step00_preflight` | shell + Vivado | `build/output/ip_catalog_lock.txt` — every pinned VLNV proved against the installed catalog |
| `step01_fetch_references` | git | `upstream/RFSoC-MTS` at the pinned SHA |
| `step02_hls_covariance` | Vitis HLS | `ip/custom/doa_covariance_4ch_v4/doa_covariance_4ch_v4_prj/` + IP in `build/ip_repo` |
| `step03_hls_spectrum` | Vitis HLS | `ip/custom/spectrum_power4/spectrum_power4_hls/` |
| `step04_hls_candidate` | Vitis HLS | `ip/custom/candidate_peak4/candidate_peak4_hls/` |
| `step04_hls_beam` | Vitis HLS | `ip/custom/beam_weight_4ch/beam_weight_4ch_hls/` |
| `step05_hls_repack` | Vitis HLS | `ip/custom/rfdc_repack4/rfdc_repack4_hls/` |
| `step05_channelizer` | MATLAB R2024a | `matlab_channelizer:7.0` IP (`dsphdl.Channelizer` through HDL Coder) |
| `step05_subband_bridge` | Vivado (packaging) | `doa_subband_bridge_4ch:1.0` from hand-written RTL |
| `step05_hls_phase_interf` | Vitis HLS | `ip/custom/phase_interf_4ch/phase_interf_4ch_prj/` |
| `step06_collect_ip` | python | `build/ip_repo/` with `ip_manifest.tsv`; every VLNV re-checked |
| `step07_vivado_project` | Vivado | `build/vivado/doa_v7_zcu208/doa_v7_zcu208.xpr` — a copy of the MTS base |
| `step08_vivado_integrate` | Vivado | hierarchy `/doa_v7` added to the base BD, IP wired and addressed |
| `step09_vivado_validate` | Vivado | BD validation + DRC clean, base inventory |
| `step10_synth` | Vivado | `build/output/post_synth_utilization.rpt`, `post_synth_timing.rpt` |
| `step11_impl` | Vivado | `post_route_utilization.rpt` (+ hierarchical), `post_route_timing.rpt`, routed DCP |
| `step12_bitstream` | Vivado | `build/output/doa_v7_zcu208.bit` |
| `step13_export_xsa` | Vivado | `build/output/doa_v7_zcu208.xsa` |
| `step14_hil_vectors` | MATLAB R2024a | `build/hil_vectors/` — stimulus + expected results for the R5 |
| `step15_package` | shell | `build/release/doa_v7_zcu208_artifacts.tar.gz` + `.sha256` |

Measured on the 2026-11-08/09 run: **20/20 PASS**, post-route **CLB LUTs 48.48 %**,
**BRAM tiles 71.62 %** (tightest), **DSPs 36.12 %**, **WNS +0.164 ns**.

---

## 2. Open the hardware design in Vivado

```bash
cd /path/to/RFSoC_ZCU208_DOA_V7_BuildKit
vivado build/vivado/doa_v7_zcu208/doa_v7_zcu208.xpr &
```

Then, in the GUI:

1. **Flow Navigator → Open Block Design** → the base design `mts` (BASE_BD).
   Inside it, the added hierarchy is **`/doa_v7`** — expand it and you see:
   `covariance`, `spectrum_power`, `candidate_peak`, `beam_monitor`, `covariance_fifo`,
   `candidate_fifo`.
2. At the top level of that BD, the datapath instances are
   `doa_rfdc_repack_0`, `doa_channelizer_0` … `doa_channelizer_3`,
   `doa_subband_bridge_0`, `doa_clk_wiz_125m`, `doa_rst_125m`,
   `doa_cdc_*` (clock converters) and the two PS AXI-Stream FIFOs.
3. **Validate Design** (`F6`, or `validate_bd_design` in the Tcl console). It must
   finish with no messages; this is the same check `step09_vivado_validate` passed.
4. **Address Editor**: six DOA AXI4‑Lite slaves sit under `/control_interconnect`.
   `phase_interf_4ch` is deliberately **not** attached — it is packaged and checked,
   but its net/clock/address requirements are still gate G4 work, not a guess.
5. **Design Runs → impl_1 → Open Implemented Design** (or open the routed DCP under
   the project's `impl_1` directory). Device view shows the placement; the reports are
   already on disk:
   `build/output/post_route_utilization.rpt`, `post_route_utilization_hierarchical.rpt`,
   `post_route_timing.rpt`.
6. **Reports → Report IP Status** tells you whether any IP wants an upgrade — it should
   not, the lock is 2023.2 everywhere.

Without the GUI:

```bash
make fit                                        # table + PASS/WARN/FAIL
grep -E "^\| *(CLB LUTs|Block RAM Tile|DSPs) +\|" build/output/post_route_utilization.rpt
grep -A10 "Design Timing Summary" build/output/post_route_timing.rpt | tail -8
```

---

## 3. Open an HLS kernel in Vitis HLS

Each kernel has its own project directory, created by its own `build_hls.tcl`:

| kernel | project directory |
|---|---|
| `doa_covariance_4ch_v4` | `ip/custom/doa_covariance_4ch_v4/doa_covariance_4ch_v4_prj` |
| `spectrum_power4` | `ip/custom/spectrum_power4/spectrum_power4_hls` |
| `candidate_peak4` | `ip/custom/candidate_peak4/candidate_peak4_hls` |
| `beam_weight_4ch` | `ip/custom/beam_weight_4ch/beam_weight_4ch_hls` |
| `rfdc_repack4` | `ip/custom/rfdc_repack4/rfdc_repack4_hls` |
| `phase_interf_4ch` | `ip/custom/phase_interf_4ch/phase_interf_4ch_prj` |

```bash
vitis_hls -p ip/custom/spectrum_power4/spectrum_power4_hls
```

In the GUI: `solution1` → **C SIMULATION** (run the testbench in `tb/`), **C SYNTHESIS**
(open the synthesis report and the schedule viewer), **C/RTL CO-SIMULATION** if you want
the RTL checked against the C. The out-of-context timing question (gate G3) has its own
script:

```bash
make -C ip/custom/phase_interf_4ch gate3-ooc      # 4.000 ns, out of context
```

`build/ip_repo/ip_manifest.tsv` is the flat list of what was packaged and under which
VLNV.

---

## 4. Open the XSA in Vitis

```bash
vitis -w build/vitis_ws &
```

- **Create Platform Component** → *Hardware* → `build/output/doa_v7_zcu208.xsa`, part
  `xczu48dr-fsvg1517-2-e`. You get the PS7 configuration, the PL clocking (250 MHz
  `clkRFdiv2` domain and the derived 125 MHz `doa_v7` clock) and the AXI4‑Lite address
  map the Address Editor showed.
- **Create Application Component** on the `psu_cortexr5_0` for the AMC/DOA firmware;
  the sources are `firmware/amc_r5/` (`amc.c`, `amc.h`, `amc_model.h`) and its host test
  is `firmware/amc_r5/test_amc.c` (gate G8a, passing under host gcc).
- Boot files for the PS side are described in `step6_ps_linux/`.

`make step14_hil_vectors` wrote the vectors the R5 side compares against —
`build/hil_vectors/` — so a Vitis debug session has both the stimulus and the expected
outputs without regenerating them in MATLAB.

---

## 5. What each block does

| block (BD instance) | duty |
|---|---|
| `doa_rfdc_repack_0` (`rfdc_repack4`) | gearbox: pairs the eight RFDC AXI4-Stream outputs (`m00/m01`, `m02/m03`, `m10/m11`, `m12/m13`; even = I, odd = Q) into four 256-bit SSR-8 complex streams at 250 MHz, packing `{Q[31:16], I[15:0]}` |
| `doa_channelizer_0..3` (`matlab_channelizer`) | one transposed `dsphdl.Channelizer` per channel: 8 complex s16 samples/beat in, 1024 bins as 8 complex s26 bins/beat out, `TLAST` every 128 accepted beats = one snapshot |
| `doa_subband_bridge_0` | deterministic single-clock bridge: four 416-bit channel streams → the three 512-bit four-lane × four-channel AXI4-Stream inputs of `/doa_v7`; quantises `sfix26_En24 → sfix16_En15` with half-up rounding and symmetric saturation, asserting ready continuously so repack and channelizers stay in lockstep |
| `covariance` (`doa_covariance_4ch_v4`) | the DOA statistic: R = XXᴴ over four channels, four samples per clock, one 512-bit beat per clock |
| `spectrum_power` (`spectrum_power4`) | per-lane incoherent power, four unsigned 64-bit bin powers per 256-bit beat — the detector statistic, not the covariance |
| `candidate_peak` (`candidate_peak4`) | per-frame candidate gate: max bin and global average over one `TLAST`-delimited frame, emits one AXI192 record; threshold `Q8.8 = 512` means peak > 2× average. Deliberately not sold as full CA-CFAR |
| `beam_monitor` (`beam_weight_4ch`) | diagnostic only: applies four Q1.15 weights to four channels for four lanes per clock, so a calibration or steering error is visible in hardware. It does not estimate DOA |
| `doa_clk_wiz_125m`, `doa_rst_125m` | the 125 MHz `/doa_v7` clock and its reset, derived from `clkRFdiv2` |
| `doa_cdc_*` | AXI4-Stream clock-domain crossings between the 250 MHz RF domain and the 125 MHz DOA domain |
| `phase_interf_4ch` (packaged, not attached) | per-bin phase interferometer: six complex cross-spectra and six CORDIC phases from four calibrated channels, so the PS never runs `atan2` per bin |
| `firmware/amc_r5` | the R5 side: angle-of-arrival estimation from the covariance, AMC, and tracking — gates G8a (passing) through G8c (needs the board) |

## 6. What you can check without a board

```bash
make lint                 # static: shell, Make dry-runs, Tcl/SV/XDC, required files
make steps                # the host algorithm chain, 8/8
make ip-equivalence       # the channelizer model vs its Verilog, bit-exact
make fit                  # resources and post-route WNS from the reports on disk
make status               # 20/20 stages, with the log of any that failed
make amc-port            # G8a: the C port checked against the model's vectors
```

What no command here can do is prove anything on silicon. That list — the eleven steps
and what each closes — is `step7_board_bringup/GUIDE.md`, with
`bash step7_board_bringup/checklist.sh` printing the commands in order.
