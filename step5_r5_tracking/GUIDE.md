# step5 — tracks, the ladder, and "is this one emitter or two?"

**Gate:** G7a (**closed**, the studies are green), G7b (board) open.
**Runs on:** python3 (pure numpy). No MATLAB, no Vitis, no board.

step3 answers *where*; step4 answers *what modulation*. step5 answers the harder
question: **which of those belong to the same emitter**, and **is this cell one
arrival or two**.

## Where it sits

```
step3 (az, el)  ┐
step4 (label)   ├─► cell ─► [ ladder: mod → dir → bw → cadence ] ─► track store ─► step6
step1 burst     ┘                │                                        │
                                 └── two_arrivals (decoy flag) ───────────┘
```

A **cell** is one detection in one frame: `{az, el, bw_hz, mod, power_db,
snr_db, frame}`. A **track** is a list of cells plus a label vote, a verification
flag and an arrival count.

## The ladder, and why the order is the algorithm

Four rungs, applied **in this order**, each one a gate plus a distance:

| # | rung | gate | distance | what it separates |
|---|---|---|---|---|
| 1 | modulation | 0.5 | 0 if the label matches, **9** if not | a different modulation is a different emitter |
| 2 | direction | 1.5 | `hypot(Δaz, Δel)/0.5°` | anything 0.75° away is another emitter |
| 3 | bandwidth | 1.0 | `|log(bw_c/bw_t)|/0.35` | same direction, different occupied band |
| 4 | cadence | 1.2 | `max(0, gap−1)/1.5` | a hopper that came back late |

The cost that the ladder minimises (V07 §19.15):

```
C = Σ_r w_r (d_r / σ_r)^2   over the rungs that could be measured
```

Association is greedy in `(C, −measured rungs)` order: the cheapest pair that
passes every gate wins, then the next. Greedy is what fits a 10 Hz frame — the
committed study `scripts/cluster_policy.py` measures what greedy costs against a
global assignment (purity and covered cells), and the answer is in
`build/output/v07_policy_quick.txt`.

**The order is not cosmetic.** T5.1 of the bench is the demonstration: the same
16QAM cell at the same direction as a QPSK track becomes a **second track** with
the full ladder (2 tracks) and is **absorbed** into the QPSK track if the
modulation rung is removed (1 track). That single number is V07 §19's whole
argument.

## The decoy: `two_arrivals`

A repeater is one waveform arriving twice:

```
x(t) = s(t) + a·s(t − τ)      →      |r(τ)| = a/(1+a²)   in the burst's autocorrelation
```

For step0's `scene_decoy` (−6 dB echo, τ = 40 ns) that is 0.40; for a single
emitter it is noise. The bench measures **40.0 ns with correlation 0.36** on the
repeater and **no flag** on the single emitter.

Resolution is one sample (0.5 ns at 2 GS/s) because the PS has the raw burst.
`scripts/radar_decoys.py` uses the *cepstral* form on the PL's 410-bin power
spectrum instead (16 ns resolution); both are reported, and the ladder consumes
the **flag**, never the number — a delay estimate that is 3 ns off still means
"two arrivals", and that is all the policy needs.

## Files

| file | what it is |
|---|---|
| `py/ladder.py` | rungs, `cost`, `passes`, `associate`, `Store`, `two_arrivals`; `python3 …/ladder.py` runs a 4-frame demo |
| `matlab/step5_ladder_costs.m` | the same cost table in MATLAB, one row per track |
| `testbench/run_testbench.py` | seven checks, below |

## How to run it

```bash
python3 step5_r5_tracking/testbench/run_testbench.py    # -> RESULT=PASS (7/7), ~19 s
python3 step5_r5_tracking/py/ladder.py                  # a 4-frame demo
python3 scripts/cluster_policy.py --quick               # the committed G7a study
```

## The test bench

| check | result on 2026-11-07 |
|---|---|
| T5.1 rung order matters | full ladder **2** tracks, direction-only **1** track |
| T5.2 decoy check | **40.0 ns**, correlation 0.36, flagged · single emitter clear |
| T5.3 cost monotone | near 0.04 < far 4.00, wide 9.85; modulation mismatch **81** |
| T5.4 store lifecycle | survives one empty frame; ghost retires at frame 6 |
| T5.5 committed studies | `moving_targets`, `feature_models`, `cluster_policy` all **RESULT=PASS** |

`RESULT=PASS (7/7)`.

## What is not proven here

* The cells are synthetic; on the board they come from step3 (0.3° error) and
  step4 (72.5 % accuracy), and both of those errors enter the cost as distances.
  The ladder is *designed* to be robust to them (that is what the σ's are for),
  but that is a claim this bench does not measure — G7b does.
* Two emitters with **equal direction, bandwidth, cadence and modulation** are
  not separated by this ladder, by construction (V07 §19.1). The decoy flag is
  the only tool there is, and it only works if the echo is delayed.
* Cadence gate tolerates exactly one missing frame; a hopper with a longer
  off-time becomes a new track. That is a policy choice, and it is one line to
  change (`SIGMA["cadence"]`).
