# The eight steps — one folder each, in the order the signal travels

The repository used to be organised by *type* (`ip/`, `firmware/`, `scripts/`,
`matlab_v7/`, `docs/`). It is now also organised by **step**, because that is how
somebody builds it: eight folders, each with a `GUIDE.md`, the MATLAB, the C or
the python, and a test bench that runs.

```bash
make steps          # all eight test benches, in order, ~40 s
make step3          # one of them
bash step7_board_bringup/checklist.sh    # what to run on your machine, and why
```

## The map

```
 step0_antenna        the 2x2 array, the scenes, the input of everything
      │                 py/array_model.py  matlab/step0_make_scene.m
      ▼
 step1_rfadc_mts      the capture record, 12-bit ADC, MTS skew, loopback (G5)
      │                 py/capture_format.py  matlab/step1_capture_header.m
      ▼
 step2_pl_ip          the eight HLS kernels (G2, G3) and the fixed-point budget
      │                 kernels.tsv  matlab/step2_fixed_point_budget.m
      ▼
 step3_r5_doa         WPI -> ML -> Gauss-Newton on the R5F (G7a), C + numpy
      │                 c/doa_core.c  py/estimator.py
      ▼
 step4_r5_amc         the modulation classifier, MATLAB -> Embedded Coder -> C (G8a/G8b)
      │                 matlab/step4_build_r5.m  firmware/amc_r5/amc.c
      ▼
 step5_r5_tracking    the ladder, the track store, the decoy check (G7a)
      │                 py/ladder.py  matlab/step5_ladder_costs.m
      ▼
 step6_ps_linux       the A53: supervision, telemetry, logging, watchdog
      │                 c/supervisor.cpp
      ▼
 step7_board_bringup  the gates that need your tools and the board (G2..G8c)
                       checklist.sh
```

## What is in each folder

| folder | GUIDE | code | test bench | result |
|---|---|---|---|---|
| `step0_antenna` | geometry, ambiguity, accuracy budget | `py/array_model.py`, `py/make_scenes.py`, 2 `.m` | 5 checks | **PASS 7/7** |
| `step1_rfadc_mts` | record layout, SQNR, MTS 0.73 ps budget | `py/capture_format.py`, 1 `.m` | 5 checks | **PASS 5/5** |
| `step2_pl_ip` | the chain, HLS commands, Q13 budget | `kernels.tsv`, 1 `.m` | 3 host checks + 7 HLS pending | **PASS 3/3** |
| `step3_r5_doa` | WPI, ML, Gauss-Newton, EKF, with formulas | `c/doa_core.c`, `py/estimator.py`, 1 `.m` | 6 checks | **PASS 6/6** |
| `step4_r5_amc` | features, nearest class mean, two builds | `matlab/*.m` + `firmware/amc_r5` | 5 checks | **PASS 5/5** |
| `step5_r5_tracking` | the four rungs, the cost, the decoy | `py/ladder.py`, 1 `.m` | 7 checks | **PASS 7/7** |
| `step6_ps_linux` | supervisor, systemd, DMA, cross-compile | `c/supervisor.cpp` | 5 checks | **PASS 5/5** |
| `step7_board_bringup` | the 12-command checklist, blockers | `checklist.sh` | 5 readiness checks | **PASS 5/5** |

Every test bench prints one `RESULT=PASS (n/m)` line and nothing in it is a
hardware claim: the hardware gates are still open and say so.

## The commands that have not been run

This is the list you asked for: every command in the repository that is written
but **never executed here**, why, and what it needs. `make tools` prints where
each tool would have to be on your machine.

| gate | command | needs | log it must leave |
|---|---|---|---|
| G2 | `make hls-all` | Vitis HLS 2023.2 (`XILINX_HLS`) | `build/output/v07_gate2_*.rpt` |
| G2 | `make -C ip/custom/phase_interf_4ch collect-reports` | the above | same |
| G3 | `make -C ip/custom/phase_interf_4ch gate3-ooc` | Vivado 2023.2 (`XILINX_VIVADO`) | `docs/evidence/<date>/gate3_ooc.txt` |
| G4 | `make step07_vivado_base BASE_XPR=<path>` | Vivado + the licensed MTS base | `docs/evidence/<date>/vivado_base.txt` |
| G4 | `make step10_synth step11_impl step12_bitstream step13_export_xsa` | the above | `…/vivado_build.txt`, XSA |
| G5 | `dd if=/dev/xdma0_c2h_0 of=/tmp/loop.bin bs=65568 count=16` | the board, booted, with the DMA node | `docs/evidence/<date>/loopback.bin` |
| G6 | `step0_antenna/testbench/compare_with_capture.py` (to be written) | the board + a chamber | `…/chamber.txt` |
| G7b | `step3_r5_doa/testbench/run_testbench.py --from-capture DIR` (flag to add) | the board captures | `…/g7b.txt` |
| G8b | `matlab -batch "cd matlab_v7; verify_amc_vectors"` | MATLAB + Embedded Coder | `…/amc_vectors.txt` |
| G8b | `matlab -batch "cd matlab_v7; build_amc_r5"` | the above + ARM Cortex-R support | `…/amc_r5_build.txt` |
| G8c | 100 bursts through the AMC on the R5, timed | the board | `…/amc_r5_timing.txt` |
| — | `matlab -batch "cd step4_r5_amc/matlab; step4_build_r5"` | MATLAB + Embedded Coder | same as G8b |
| — | `matlab -batch "cd step5_r5_tracking/matlab; …"` | MATLAB | — |
| — | `make tools MATLAB=1` | MATLAB (starts a licence checkout) | — |

Three of those commands need a file that does not exist yet and the table says
so: the chamber script, the `--from-capture` flag, and the DMA reader. They are
listed because pretending they exist would be worse than naming them.

### Every stage leaves a tracked page

`build/logs/*.log` is not in git (large, machine-specific), so a pushed branch
used to show nothing about what had run. Now every stage writes two things:

| file | tracked | what it holds |
|---|---|---|
| `build/logs/<stage>.log` | no | the full output, every line |
| `docs/progress/<stage>.md` | **yes** | result, start/finish/duration, the command, the 40 lines that matter, and the path of the full log |
| `docs/progress/PROGRESS.md` | **yes** | one table over all 20 stages: PASS / FAIL / NOT-RUN, finished time, link to the page |

Both are written by `scripts/run_stage.sh` whatever the result, so a failed
stage is visible too. Rebuild the table by hand with:

```bash
make progress      # -> docs/progress/PROGRESS.md
make status        # the same information on the terminal
```

Commit `docs/progress/` after a run on the board host; that is what makes
"where did the build get to" answerable from GitHub.

### Two MATLABs

If Model Composer is installed, it pins its own MATLAB (2023.2 → R2022b) while
the command line runs a newer release. Only the channelizer's Model Composer
route needs the old one, and it **builds**. The model is
`<repo>/ip/model_composer/channelizer/channelizer.slx` (no `.slx` is committed);
`make mc-scratch` generates it from `make_channelizer_model.m` with no GUI,
`make mc-path` prints that exact path, `make mc-find` finds an existing one, and
`make mc` then needs no argument. `make mc-example` downloads AMD's 2023.2
example into `build/` for reference only. `make mc` runs R2022b in `-batch` with the Model Composer
and System Generator paths added, compiles the token to IP Catalog, installs the
IP and verifies the `component.xml` exists — the same stage as
`step05_channelizer CHANNELIZER_FLOW=model_composer`, so it lands in the progress
table. It does **not** use the Model Composer launcher (it evals its arguments
and appends its own `-r`). `make mc-gui` opens that GUI, which you need only to
create or edit the `.slx`; `make mc-verify` collects the IP after a GUI compile.
[`docs/TWO_MATLABS.md`](docs/TWO_MATLABS.md) has the table and the
`config.local.mk` snippet, and `make tools MATLAB=1` prints an `[ok]`/`[MISS]`
verdict for every toolbox the code generator needs.

### What to send back, and what happens then

Run `make tools` (add `MATLAB=1` if you want the toolbox list) and send the
output. Everything the checklist needs is either in that output or is one
absolute path:

```
XILINX_HLS      /tools/Xilinx/Vitis_HLS/2023.2      -> G2, G3
XILINX_VIVADO   /tools/Xilinx/Vivado/2023.2          -> G3, G4
BASE_XPR        /…/mts/mts.xpr                       -> G4
MATLAB_ROOT     /usr/local/MATLAB/R2024a             -> G8b (needs Embedded Coder in `ver`)
```

With those, the logs land in `docs/evidence/` and the amber badges in
`docs/diagrams/system_block.png` become green — one at a time, each one only
after its log exists.

## Reading order, if you have ten minutes

1. `step3_r5_doa/GUIDE.md` — the estimator, and what ML + Gauss–Newton is.
2. `step4_r5_amc/GUIDE.md` — the classifier and how it becomes an R5 library.
3. `step5_r5_tracking/GUIDE.md` — why the ladder's order is the algorithm.
4. `step7_board_bringup/GUIDE.md` — what is left, and in which order.
5. `docs/diagrams/system_block.png` — the whole thing in one picture.
