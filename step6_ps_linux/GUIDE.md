# step6 — the A53: Linux, supervision, logging, and how to put it on the board

**Gate:** none of its own. It is what makes G5, G6, G7b and G8c *measurable*
(there is nowhere to write a log without this side).
**Runs on:** any g++ (host), and an aarch64 cross toolchain for the board.

The A53 does four jobs and no maths:

| job | what it does | why it is not on the R5 |
|---|---|---|
| calibration manager | phase/gain vs frequency sweep → coefficients | it needs a shell and a file, not a deadline |
| policy configuration | which rungs, which gates, which scan ranges | operators change it; it must not need a rebuild |
| telemetry + logging | tracks and captures to disk/network | HDF5, filesystems, sockets |
| health / watchdog | is the R5 alive, is the DMA moving | it is the thing that must survive |

## The supervisor

`c/supervisor.cpp` — 300 lines, C++17, standard library only:

```
cells (JSONL on stdin) ─► ladder (mod → dir → bw → cadence) ─► tracks ─► telemetry (JSONL)
                                     │
                              retire after N empty frames
```

It carries **the same four rungs and the same gates** as
`step5_r5_tracking/py/ladder.py`, and the test bench feeds both the same fixture
and compares the track count. That duplication is on purpose: the A53 does not
link bare-metal RPU code, and a shared library across two cores with different
ABIs costs more than 300 lines twice. If you change a gate, change it in both —
`T6.2` is the check that you did.

```bash
make -C step6_ps_linux/c            # host binary  -> build/step6/supervisor
make -C step6_ps_linux/c cross      # aarch64, static -> build/step6/supervisor_aarch64
./build/step6/supervisor < step6_ps_linux/testbench/fixture_cells.jsonl
```

Output is one JSON object per cell plus one per retirement:

```json
{"frame":1,"track":1,"az":10.0250,"el":0.0000,"bw_hz":100000000.000,"mod":"QPSK","state":"update","verified":false}
{"frame":5,"track":3,"az":25.0000,"el":-5.0000,"bw_hz":50000000.000,"mod":"BPSK","state":"retired","verified":false}
```

and one summary line on stderr, which is what a watchdog parses:

```
supervisor: frames=7 cells=15 tracks_live=2 born=3 retired=1 ghosts=1 malformed=0 policy=full
```

## Putting it on the board (the part that needs hardware)

1. **Cross-compile.** With the PetaLinux SDK on PATH:

   ```bash
   source /opt/petalinux/2023.2/environment-setup-cortexa72-cortexa53-xilinx-linux
   make -C step6_ps_linux/c cross
   ```

   The binary is static, so it does not care which rootfs you boot.

2. **Copy it over.** Any of these, whichever your image has:

   ```bash
   scp build/step6/supervisor_aarch64 root@<board>:/usr/bin/doa_supervisor
   # or:  mount the SD card's rootfs partition and cp it into /usr/bin
   ```

3. **Feed it.** Two sources, and this is where the FPGA side meets this side:

   ```bash
   # a) from the DMA node, one burst per line (needs the driver, V04 §7)
   cat /dev/xdma0_c2h_0 | doa_supervisor
   # b) from a recorded file, for a replay test
   doa_supervisor < /var/log/doa/cells_2026-11-07.jsonl
   ```

4. **Log it.** `systemd` unit, because a supervisor that dies must restart:

   ```ini
   [Unit]
   Description=DOA supervisor
   After=network.target
   [Service]
   ExecStart=/usr/bin/doa_supervisor
   Restart=always
   StandardOutput=append:/var/log/doa/telemetry.jsonl
   StandardError=append:/var/log/doa/supervisor.err
   [Install]
   WantedBy=multi-user.target
   ```

   ```bash
   systemctl enable --now doa_supervisor
   tail -f /var/log/doa/supervisor.err      # the summary line, every second
   ```

5. **Watch it.** The health block is the summary line: `malformed` must stay 0,
   `tracks_live` must stay bounded, and `frames` must advance. A supervisor that
   runs but stops advancing frames is the failure mode nobody notices.

## Files

| file | what it is |
|---|---|
| `c/supervisor.cpp` | the ladder + store + telemetry, dependency free |
| `c/Makefile` | host build, and the `cross` target with the SDK message |
| `testbench/fixture_cells.jsonl` | 15 cells / 7 frames: mover, same-direction 16QAM, ghost |
| `testbench/run_testbench.py` | five checks, including the python-vs-C++ agreement |

## The test bench

| check | result on 2026-11-07 |
|---|---|
| T6.1 builds | `supervisor`, 37 kB |
| T6.2 same tracks as the python ladder | **3** and **3** |
| T6.3 the modulation rung does the work | full **3** tracks, direction-only **2** |
| T6.4 the ghost is retired | 1 retired, 1 ghost |
| T6.5 `--quiet` and the exit code | silent, exit 0, `malformed=0` |

`RESULT=PASS (5/5)`.

## What is not proven here

* Nothing ran on an A53. The cross target is written and refuses politely when
  the toolchain is absent; that is not the same as a binary that booted.
* No DMA reader exists yet: `/dev/xdma0_c2h_0` is the V04 contract, and the
  driver configuration is G4/G5 work.
* Calibration (A17) is a MATLAB reference (`matlab_v7/estimate_multifrequency_calibration.m`)
  with no Linux side yet; the supervisor is where it will live.
