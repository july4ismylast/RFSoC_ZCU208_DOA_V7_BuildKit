# step7 — bring-up: the gates that need your tools and the board

**Gates:** G2, G3, G4, G5, G6, G7b, G8b, G8c — every one of them **open**, and
every one of them here, in the order that works.
**Runs on:** your machine with Vitis HLS 2023.2, Vivado 2023.2, MATLAB
(+ Embedded Coder) and the ZCU208.

This folder contains no algorithm. It contains the checklist, the readiness test
bench, and the explanation of what each gate is waiting for.

## The list

```bash
bash step7_board_bringup/checklist.sh              # print all 11 commands
bash step7_board_bringup/checklist.sh --run 2      # run one of them
```

| # | gate | what it closes | command |
|---|---|---|---|
| 1 | G0, G1a–c, G7a, G8a | **already closed by this repository** | `make steps` |
| 2 | tools | what is installed, and where | `make tools` |
| 3 | G2 | eight HLS kernels: csim + csynth at 4.000 ns | `make hls-all` |
| 4 | G2 | copy the csynth reports out | `make -C ip/custom/phase_interf_4ch collect-reports` |
| 5 | G3 | out-of-context synthesis (the 4.000 ns question) | `make -C ip/custom/phase_interf_4ch gate3-ooc` |
| 6 | G4 | the Vivado base — **needs `BASE_XPR`** | `make step07_vivado_base BASE_XPR=<path>/mts.xpr` |
| 7 | G4 | synth, impl, bitstream, XSA | `make step10_synth step11_impl step12_bitstream step13_export_xsa` |
| 8 | G8b | MATLAB → Embedded Coder → C for the AMC | `matlab -batch "cd matlab_v7; verify_amc_vectors"` then `"cd matlab_v7; build_amc_r5"` |
| 9 | G5 | boot, then the DAC→ADC loopback capture | `dd if=/dev/xdma0_c2h_0 of=/tmp/loop.bin bs=65568 count=16` |
| 10 | G6 | the chamber sweep, one angle at a time | script to write: `step0_antenna/testbench/compare_with_capture.py` |
| 11 | G7b | the estimator on board captures | flag to add: `--from-capture DIR` |
| 12 | G8c | cycles per burst on the R5 | on the board: 100 bursts through the AMC, timed |

Read the order as a dependency chain: 3 must pass before 4, 4 before 5 (G3 reads
the csynth reports), 5 before 6 (the IP must exist before the block design), 6
before 7 (there is no bitstream without the base project).

## The four things the checklist cannot supply

| what | why it matters | where it comes from |
|---|---|---|
| `BASE_XPR` | steps 08–11 patch a licensed MTS base project; without it the build stops at step 07 | your Vivado project for the ZCU208 MTS reference |
| Vitis HLS 2023.2 on `PATH` | G2/G3 | `XILINX_HLS=/tools/Xilinx/Vitis_HLS/2023.2` |
| Vivado 2023.2 on `PATH` | G3/G4 | `XILINX_VIVADO=/tools/Xilinx/Vivado/2023.2` |
| Embedded Coder | G8b | MATLAB `ver` must list `Simulink Coder` and `Embedded Coder` |

`make tools` prints all four, and nothing in this folder pretends otherwise. In
the authoring container none of them exist, which is exactly why the middle of
the chain is open — see `docs/GATES_G1_G7.md` for the full gate table.

## The readiness test bench

```bash
python3 step7_board_bringup/testbench/run_testbench.py     # -> RESULT=PASS (5/5)
```

| check | what it proves |
|---|---|
| T7.1 | all 8 step folders have a `GUIDE.md` and a `testbench/run_testbench.py` |
| T7.2 | `make lint` still passes (38 Tcl/XDC files, shell syntax, Make dry-runs) |
| T7.3 | the checklist lists 11+ commands and exactly **one** is marked closed |
| T7.4 | the diagram of record exists and is newer than the script that draws it |
| T7.5 | `make tools` reports on all five tool families |

`RESULT=PASS (5/5)` means *the repository is ready to be taken to the board*.
It does not mean anything about the board.

## What "closing a gate" means here

A gate closes when a **log exists** in `docs/evidence/<date>/` and its number is
quoted in the gate table. Typing the command is not closing the gate; a green
badge in `docs/diagrams/system_block.png` is drawn only from a log that is in the
repository. That rule is what keeps this project's claims checkable, and it is
the reason the diagram has eight amber badges today.
