# Build, stages and gates

Source of truth: `Makefile`, `config.mk`, `docs/OPEN_AND_CHECK.md`, `docs/GATES_G1_G7.md`,
`docs/WHERE_WE_ARE.md`. Measured state below is the 2026-11-08/09 run; anything newer must come from
the user's `make status`.

## 1. Commands a user actually needs

Run from the repository root.

| command | what it does | cost |
|---|---|---|
| `make help` | every target, one line each | instant |
| `make lint` | Tcl/XDC/SystemVerilog syntax, shell syntax, Make dry-runs, VLNV pins | ~5 s |
| `make steps` | the eight host benches (step0…step7) | minutes |
| `make status` | which stages have stamps, which logs are stale | instant |
| `make fit` | reads the post-route reports and prints a verdict; says NOT-MEASURED rather than guessing | instant |
| `make tools` | what is installed and where | instant |
| `make pipeline` | all twenty production stages in order | hours, needs licences |
| `make <stage>` | one stage, e.g. `make step05_hls_phase_interf` | minutes–hours |
| `make hls-all` | the seven HLS/RTL IP folders (`hls` + `install` each) | ~1 h |
| `make step06_collect_ip` | re-verify every VLNV, write `build/ip_repo/ip_manifest.tsv` | seconds |
| `make step11_impl` | implementation; sets the `Performance_ExtraTimingOpt` strategy itself | ~40 min |
| `make diagram` | regenerate the five system figures and the 23 block figures | ~1 min |
| `make clean-stage STEP=<stage>` | delete one stage's stamp and log | instant |
| `make rebuild STEP=<stage>` | clean and re-run one stage | as that stage |
| `make verify-phase-interf` | host estimator + kernel checks for the V07 block | ~3 min |
| `make compare-estimators` | wideband estimator comparison, full trial counts | ~6 min |
| `make radar-decoy` | decoy discrimination, host criteria (gate G7a) | ~3.5 min |
| `make ip-equivalence` | HDL channelizer vs MATLAB model, 16 384 samples | ~1 min |
| `make publish-evidence` / `make publish-debug-logs` | copy logs into `docs/evidence/`, `docs/debug-logs/` | seconds |

Everything that can be proven without a licence is already green: `make lint`, `make steps`,
`make verify-phase-interf`, `make radar-decoy`. If one of those fails on the user's machine, the
problem is their environment, not the licence.

## 2. The twenty stages

| # | stage | tool | artifact |
|---|---|---|---|
| 1 | `step00_preflight` | shell + Vivado | `build/output/ip_catalog_lock.txt` — every pinned VLNV proved against the installed catalog |
| 2 | `step01_fetch_references` | git | `upstream/RFSoC-MTS` at the pinned SHA |
| 3 | `step02_hls_covariance` | Vitis HLS | `ip/custom/doa_covariance_4ch_v4/doa_covariance_4ch_v4_prj/`, IP in `build/ip_repo` |
| 4 | `step03_hls_spectrum` | Vitis HLS | `ip/custom/spectrum_power4/spectrum_power4_hls/` |
| 5 | `step04_hls_candidate` | Vitis HLS | `ip/custom/candidate_peak4/candidate_peak4_hls/` |
| 6 | `step04_hls_beam` | Vitis HLS | `ip/custom/beam_weight_4ch/beam_weight_4ch_hls/` |
| 7 | `step05_hls_repack` | Vitis HLS | `ip/custom/rfdc_repack4/rfdc_repack4_hls/` |
| 8 | `step05_channelizer` | MATLAB R2024a | `openai:doa:matlab_channelizer:7.0` via HDL Coder |
| 9 | `step05_subband_bridge` | Vivado (packager) | `openai:doa:doa_subband_bridge_4ch:1.0` from hand-written RTL |
| 10 | `step05_hls_phase_interf` | Vitis HLS | `ip/custom/phase_interf_4ch/phase_interf_4ch_prj/` |
| 11 | `step06_collect_ip` | python | `build/ip_repo/` + `ip_manifest.tsv`, every VLNV re-checked |
| 12 | `step07_vivado_project` | Vivado | `build/vivado/doa_v7_zcu208/doa_v7_zcu208.xpr` (a copy of the MTS base) |
| 13 | `step08_vivado_integrate` | Vivado | `/doa_v7` hierarchy added to the base block design, IP wired and addressed |
| 14 | `step09_vivado_validate` | Vivado | block-design validation + DRC clean |
| 15 | `step10_synth` | Vivado | `post_synth_utilization.rpt`, `post_synth_timing.rpt` |
| 16 | `step11_impl` | Vivado | `post_route_utilization.rpt` (+ hierarchical), `post_route_timing.rpt`, routed DCP |
| 17 | `step12_bitstream` | Vivado | `build/output/doa_v7_zcu208.bit` |
| 18 | `step13_export_xsa` | Vivado | `build/output/doa_v7_zcu208.xsa` |
| 19 | `step14_hil_vectors` | MATLAB R2024a | `build/hil_vectors/` — stimulus + expected results for the R5 |
| 20 | `step15_package` | shell | `build/release/doa_v7_zcu208_artifacts.tar.gz` + sha256 |

A stage is "done" when its stamp exists; a log without a stamp means the last attempt failed. That is
all `FAILED/OLD` means — it is not a stale-result warning.

## 3. The gates, with their real status

| gate | question | status |
|---|---|---|
| G0 | is the physics right, on the host? | **PASS** |
| G1a | is the fixed-point core bit-exact? | **PASS** |
| G1b | does the kernel pass its own testbench (shimmed)? | **PASS** |
| G1c | do `config.mk`, `build_hls.tcl` and `collect_ip.sh` agree on the VLNV? | **PASS** (contract only) |
| G2 | does Vitis HLS compile, synthesise and export it? | **PASS** (2026-11-08: step02–step06 all PASS) |
| G3 | does the packaged IP meet 4.0 ns out of context? | **NOT RUN** (in context, step10/step11 PASS) |
| G4 | does it integrate into the block design and produce a bitstream? | **PASS** (step07–step12, `doa_v7_zcu208.bit` written) |
| G5 | on silicon, does the phase sign and offset hold? | **NOT RUN** — needs the board |
| G6 | with a calibrated array, does the accuracy hold in a chamber? | **NOT RUN** — needs array + source |
| G7a | do the decoy criteria pass on host models? | **PASS** (models only) |
| G7b | does a repeater get rejected on hardware? | **NOT RUN** — needs board + repeater |
| G8a | does the R5 firmware reproduce the model? | **PASS** (host gcc) |
| G8b | does Embedded Coder build and link it for the RPU? | **NOT RUN** — needs Embedded Coder |
| G8c | does an AMC frame meet its deadline on the R5F? | **NOT RUN** — needs the board |

Six open: **G3, G5, G6, G7b, G8b, G8c**. If a user says "the project is finished", this table is the
correction: the *bitstream* is finished, the *proof on hardware* is not.

## 4. Measured numbers from the full run

| claim | value | proof |
|---|---|---|
| stages | 20/20 PASS (2026-11-08/09) | `make status` on the Vivado host |
| CLB LUTs | 206 179 / 425 280 = **48.48 %** | `docs/evidence/2026-11-09-matlab_hdl/post_route_utilization.rpt` |
| CLB registers | 313 132 = 36.81 % | same |
| Block RAM tiles | 773.5 / 1 080 = **71.62 %** (tightest) | same |
| DSPs | 1 543 / 4 272 = 36.12 % | same |
| URAM / IOB | 20/80, 82/347 | same |
| timing | post-route **WNS +0.164 ns** | `docs/evidence/2026-11-09-matlab_hdl/post_route_timing.rpt` |
| release | `doa_v7_zcu208.bit`, `.xsa`, `doa_v7_zcu208_artifacts.tar.gz` (24.9 MB + sha256) | `build/release/` |

Utilisation is only valid for that exact bitstream. Any RTL change invalidates it — say so.

## 5. Where the evidence lives

```
build/logs/stepNN_*.log        one per stage, the first thing to read after a failure
build/stamps/                  *.done — presence is the definition of "this stage passed"
build/output/                  reports copied out of the Vivado project (util, timing, DRC, bit, xsa)
build/ip_repo/                 packaged IP, one directory per IP, plus ip_manifest.tsv
docs/evidence/<date>-<topic>/  published evidence: reports, logs, REVIEW.md with what it proves
docs/debug-logs/<stamp>-<flow>/  bulky logs published with make publish-debug-logs
```

`build/` is git-ignored in full. Evidence is *copied* into `docs/evidence/` precisely so a claim
survives deleting the build tree.

## 6. Configuration that must be right before anything expensive

| knob | default | why it bites |
|---|---|---|
| `PART` | `xczu48dr-fsvg1517-2-e` | every IP and report is relative to it |
| `BOARD_PART` | `xilinx.com:zcu208:part0:2.0` | the MTS base |
| `BASE_XPR` (`BASE_KIND=mts`) | `build/mts_base_src_2023p2/boards/ZCU208/build_mts/mts/mts.xpr` | a substitute base invalidates every comparison |
| `VIVADO`, `VITIS_HLS` | from `config.mk` | pinned to 2023.2; `step00` refuses another version |
| `MATLAB` / `MATLAB_2022B` | R2024a / R2022b path | two releases, two products (`docs/TWO_MATLABS.md`) |
| `PL_CLOCK_PERIOD_NS` | `7.8125` | the DOA-side HLS constraint (clock is 125 MHz) |
| `WIDEBAND_CLOCK_PERIOD_NS` | `4.0` | the 250 MHz side; `repack4` and `phase_interf` use it |
| `ARRAY_AXIS_SPACING_M` | `0.030` | 50 mm is rejected — it wraps in band |
| `CHANNELIZER_FLOW` | `matlab_hdl` | `model_composer`, `opfb`, `external` also exist |
| `ALLOW_CHANNELIZER_PACKAGE` | unset | packaging exits 2 until you set it to 1 |

Per-machine overrides go in `config.local.mk` (not tracked). Never ask a user for its contents and
never print licence paths.
