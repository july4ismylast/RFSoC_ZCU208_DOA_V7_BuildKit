# step2 — the programmable logic (the eight kernels)

**Gates:** G1a/G1c (host, **closed**), G2 (Vitis HLS csim + csynth, **open**),
G3 (out-of-context synthesis, **open**), G4 (bitstream, **open**).
**Runs today:** the host checks. **Needs the tool:** every `hls` line below.

The sources are not copied into this folder — they live in `ip/custom/<kernel>/`
with their own test benches, and `kernels.tsv` is the table that binds them here.
One copy of the truth, one place to run it.

## The chain

```
RF-ADC ─► rfdc_repack4 ─► doa_subband_bridge_4ch ─► spectrum_power4 ─► candidate_peak4
                                                          │                 │
                                                          ▼                 ▼
                                                   doa_covariance_4ch_v4   trigger+capture
                                                          │                 │
                                                          ▼                 ▼
                                                   phase_interf_4ch ──► AXI-Lite + DMA ──► PS
```

| kernel | what it does | host check today | HLS command |
|---|---|---|---|
| `rfdc_repack4` | 2 GS/s × 4 real → SSR complex, 558.8 Gb/s | — | `make -C ip/custom/rfdc_repack4 hls` |
| `doa_subband_bridge_4ch` | 4-channel AXI-Stream bridge, bit exact | **PASS** (golden model) | `make -C ip/custom/doa_subband_bridge_4ch ip` |
| `spectrum_power4` | 410 carriers, power per bin | — | `make -C ip/custom/spectrum_power4 hls` |
| `candidate_peak4` | peak + noise gate → candidate bins | — | `make -C ip/custom/candidate_peak4 hls` |
| `doa_covariance_4ch_v4` | 4096 snapshots → 4×4 covariance, int64 | — | `make -C ip/custom/doa_covariance_4ch_v4 hls` |
| `phase_interf_4ch` | per-bin cross-spectrum + CORDIC phase | **PASS** (core + kernel) | `make -C ip/custom/phase_interf_4ch hls` |
| `beam_weight_4ch` | optional beam weights | — | `make -C ip/custom/beam_weight_4ch hls` |

Each `hls` target is exactly `$(VITIS_HLS) -f build_hls.tcl` inside that folder:
C simulation, C synthesis at a **4.000 ns** clock, then IP export to
`build/ip_repo/`. `config.mk` sets `VITIS_HLS ?= vitis_hls`; if your Vitis is at
`/tools/Xilinx/Vitis_HLS/2023.2/bin/vitis_hls`, do

```bash
make -C ip/custom/phase_interf_4ch hls VITIS_HLS=/tools/Xilinx/Vitis_HLS/2023.2/bin/vitis_hls
```

The reports that G2 needs land in `build/output/v07_gate2_*.rpt` automatically
(`collect-reports` copies them out of the Vitis solution folder).

## The fixed-point budget (why 13 bits of phase is enough)

`matlab/step2_fixed_point_budget.m`:

```
phase LSB   dphi   = 2*pi*2^-b
angle LSB   dtheta = dphi * lambda/(2*pi*d)      d = 25 mm, f = 4 GHz
```

| phase bits | phase LSB | angle per LSB | verdict |
|---|---|---|---|
| Q8 | 2.45e−2 rad | 0.671° | **above** the 0.5° budget |
| Q10 | 6.14e−3 rad | 0.168° | inside |
| **Q13** | **7.67e−4 rad** | **0.021°** | inside, 24× margin ← what the IP uses |
| Q16 | 9.59e−5 rad | 0.0026° | inside, overkill |

Accumulator: 4096 snapshots × Q15 full scale = 2^43, so 43 bits worst case and
`int64` is the right word on a 32-bit R5 — which is why the phase record is 16
words (32 bits of accumulator + 32 bits of phase per baseline).

## Model Composer, if you prefer a block diagram to a script

`ip/model_composer/channelizer/` holds the Model Composer model for the
channeliser, and `ip/matlab/channelizer_hdl/` the MATLAB-side generator. The
Model Composer path produces the same IP through HDL Coder instead of
`vitis_hls -f build_hls.tcl`; the two are alternatives, not a required pair.
Command that has **not** been run here:

```matlab
matlab -batch "cd ip/matlab/channelizer_hdl; run('generate_channelizer_hdl')"
```

## How to run it

```bash
# today, no licence
python3 step2_pl_ip/testbench/run_testbench.py          # -> RESULT=PASS (3/3), HLS skipped

# with Vitis HLS 2023.2 (this is the run that closes G2)
python3 step2_pl_ip/testbench/run_testbench.py --with-hls

# one kernel, by hand
make -C ip/custom/phase_interf_4ch hls && make -C ip/custom/phase_interf_4ch collect-reports

# G3, the out-of-context synthesis that checks the 4.000 ns clock
make -C ip/custom/phase_interf_4ch gate3-ooc
```

## The test bench

| check | result on 2026-11-07 |
|---|---|
| `doa_subband_bridge_4ch` golden model | PASS |
| `phase_interf_4ch` host core (CORDIC, sign, 51-bit accumulator) | PASS |
| `phase_interf_4ch` kernel against the production test bench | PASS |
| 7 HLS commands | **skipped** — `vitis_hls` is not on this machine's PATH |

`RESULT=PASS (3/3)`, and the test bench prints every pending HLS command instead
of pretending it ran. When you run it with `--with-hls`, each line becomes a real
PASS/FAIL and G2 can be closed.

## What is not proven here

* No synthesis has happened: no II, no latency, no LUT count, no 4.000 ns timing.
  The host shim gives you the *numbers* of the algorithm, not its *schedule*.
* The `rfdc_repack4` and `spectrum_power4` host numbers come from their test
  benches (compile them with `g++` the way `phase_interf_4ch` is compiled); they
  have no `host-check` target yet. That is a ten-line Makefile change, listed as
  a to-do in `docs/GATES_G1_G7.md`.
