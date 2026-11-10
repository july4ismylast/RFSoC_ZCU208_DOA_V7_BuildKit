# ZCU208 DOA V7 FPGA Build Kit

![ZCU208 DOA V7 architecture](docs/diagrams/zcu208-overall.jpg)

This is the corrected ZCU208 implementation draft for the V7 2×2 DOA
simulation. It is a restartable build system and a hardware/software partition,
not a claim that a bitstream was generated in this environment.

The critical design decisions are:

- use a verified **ZCU208** RFDC/clock/MTS base project; never port a different
  RFSoC board by changing only `PART`;
- keep search and triggered covariance on independent streams so a completed
  covariance frame cannot stop continuous detection;
- process four complex samples per clock on all custom PL blocks;
- compute calibrated four-channel/six-baseline cross-spectra in PL, per
  frequency bin, and extract the six baseline phases in a small CORDIC block
  (V07 phase interferometry — see
  [V07_PHASE_INTERFEROMETRY.md](V07_PHASE_INTERFEROMETRY.md));
- initially run V7 WPI, bounded local ML/Gauss–Newton, and the unit-vector EKF
  on the R5, with the A53 supervising calibration, logging, and networking;
- require C simulation, BD validation, timing closure, exact covariance HIL,
  and angle acceptance as separate gates.

## Start here

```bash
make help
make status
# Vivado/Vitis are locked to 2023.2 (V00): every IP VLNV lives in
# config/ip_versions.tcl and step00 proves it against your installed catalog.
make step00_preflight \
  BASE_XPR=/absolute/path/verified_zcu208_base.xpr
```

Vivado-first flow: the production base is the pinned Xilinx RFSoC-MTS
ZCU208 design. See [V03_MTS_BASE_2023P2.md](V03_MTS_BASE_2023P2.md) for how
that 2022.1.2 base is brought under the 2023.2 lock before step07, and
[V00_V01_V02_CHANGES.md](V00_V01_V02_CHANGES.md) for the version-pinning
changes (branch `vivado-2023.2-v00-v01`).

Run or debug any stage directly:

```bash
make step02_hls_covariance
make step10_synth
make rebuild STEP=step10_synth
make clean-stage STEP=step10_synth
make -n step10_synth
```

The production integration stage intentionally stops until
[`config/zcu208_bd_map.tcl`](config/zcu208_bd_map.tcl) is mapped to the actual
RFDC base-design pin names. For a structural-only BD check, use
`INTEGRATION_MODE=external_ports`; that result is not deployable.

## Documentation

- [Wideband phase interferometry: adopt / correct / reject](V07_PHASE_INTERFEROMETRY.md)
- [Implementation and algorithm guide](ZCU208_IMPLEMENTATION_GUIDE.md)
- [Every build stage and recovery command](BUILD_STAGES.md)
- [File-by-file and code walkthrough](FILE_AND_CODE_GUIDE.md)
- [Primary-source research and adoption decisions](RESEARCH_REFERENCES.md)
- [First-draft audit and direct comparison](AUDIT_AND_COMPARISON.md)
- [What was and was not validated here](VALIDATION_REPORT.md)
- [Original draft source matrix](SOURCE_MATRIX.md)
- [Block guide: every stage, every block, every figure](docs/BLOCK_GUIDE.md) — Part 6 is the IDE walkthrough
- [AI skill for chat bots](skills/README.md) — `skills/rfsoc-doa-v7/`, checked by `make skill-check`

## Why the DOA estimator is phase interferometry, not phase slope

The wideband path measures the angle from the *carrier* phase of the summed
cross-spectrum, not from a phase-versus-frequency slope. `scripts/phase_interf_verify.py`
(committed report under `docs/evidence/2026-11-06-phase-interf/`) measures
0.22° RMSE at 20 dB/bin for a 50 MHz emitter with the coherent estimator, and
101° for the slope estimator proposed by the external review — the slope
estimator's effective lever arm is `B/sqrt(12)` against the carrier's `f_c`, and
`f_c > B` always. The same script rejects 50 mm element spacing (106° error at
3.75 GHz where 25 mm gives 0.27°), and
`scripts/estimate_wideband_dsp_resources.py` shows why a 16K FFT at 2.048 GSPS
is neither instantiable nor necessary.

Over the *whole* 2–4 GHz band the answer is more precise, and it is measured in
`scripts/compare_wideband_estimators.py` (V07 §11): a square 2×2 is wrap-free
while `d·√2·sin θ ≤ λ/2`, which allows 32.3 mm for the declared ±55° scan at
4 GHz, so the array pitch in `config.mk` is **30 mm** — not the review's 50 mm,
which is 1.7× too wide and is measured 34° and 104° off where 30 mm holds 1.6°
and 1.1°. In the same run a *through-origin* frequency-domain fit reaches 0.066°
on a 2 GHz emitter and 0.25° on a 50 MHz one, while the review's
unwrap-plus-intercept variant reaches 0.235° and loses every narrowband frame.
Estimator: `make compare-estimators`. Geometry, not the estimator, sets 0.5°.

**Decoys.** One protected emitter behind a set of decoys is answered twice, for
a continuous emitter and for a radar; every algorithm, block diagram, measured
table and failure case is in
[`docs/DECOY_DISCRIMINATION.md`](docs/DECOY_DISCRIMINATION.md), and the hardware
acceptance criteria are gate **G7** in
[`GATES_RUNBOOK.md`](GATES_RUNBOOK.md).

For **multiple emitters** the answer depends on whether they share the band
(V07 §12). Eight *co-channel* emitters over 2 GHz need 36 elements: the 2×2 finds
1.2 of 8, a 4×4 at 60 mm finds 7, a 6×6 at 75 mm finds all eight at 0.295°
(`make multisource-df`). Eight *frequency-separated* emitters of 1–50 MHz — the
realistic reading of a 2–4 GHz tuning range — are separated by the channelizer
and the shipped 2×2 detects **8.0 of 8**, at 0.59°→0.12° for a 1 MHz target as
dwell grows from 16 to 256 snapshots, and 1.42° at 4 snapshots for the targets
that are allowed 3° (`make narrowband-targets`, §12.4).

When **one** of those signals is the target and the rest are decoys (V07 §13,
`make decoy-df`), the discriminator is a ladder, cheapest rung first. Decoys on
other carriers cost nothing: the channelizer counts them (1/2/4/7 clusters for
0/1/3/6 decoys) and the source azimuth moves by ≤ 0.07°. An *independent* decoy
inside the same band is a hardware problem — the 2×2 recovers 0.4 of 2 while a
3×3 recovers 2 of 2. A *repeater* (DRFM copy) is coherent and therefore rank 1
in every bin, so no per-bin estimator separates it; it is instead flagged by a
DOA that wobbles across the band (43.8° rms against 0.31° for a clean emitter)
and a cepstrum ripple whose period is the delay (101 ns recovered from 100 ns),
and then *resolved* by a two-path ML with the delay searched jointly: both
directions correct in 100% of trials at 20–50 MHz bandwidth on the shipped 2×2,
0% at 1 MHz.

If the protected emitter is a **radar** — it transmits *and* receives — the
problem is easier and the answer changes (V07 §13.7, `make radar-decoy`). A decoy
has to hear a pulse before it can repeat it, so the repeat is always later than
the direct path by at least its turnaround: the triangle inequality plus a
non-negative processing delay. The first tens of nanoseconds of every pulse
therefore carry the radar alone, and its DOA from a 20–100 ns window is
0.09–0.79° where the whole-pulse method is 12–16° wrong; ±2 ns of edge jitter
still gives 0.22°. After the pulse ends, whatever is still on the air is the
decoy, for exactly the delay it inserted: the tail measures the decoy's own
direction (39.6° for a decoy at 40°) with no model at all. A Doppler pull-off
leaves the gate at 0.19–0.36°. The half-sample delay read off the leading edge
is also what the two-path ML needs: with it, 5–50 MHz emitters resolve both
directions exactly, without the blind search that only works at 25–100%. A
co-located, zero-delay decoy — unsolvable for a continuous emitter — is
separated here in *time*; a continuous-wave source has no leading edge and falls
back to the rungs above. The gate holds for LFM, soft-edged LFM, tan-FM and
Barker-13 codes alike (0.12–0.39° against 7.8–12.7° for the whole-pulse method),
and with the ±0.5 dB / ±5° calibration residual of §11.3 it lands at 1.6–2.3° —
so calibration, not the decoy, is what stands between it and the 0.5° class.

A **hopping** emitter (1–100 MHz of instantaneous bandwidth, hopping over
2.7–3.5 GHz) is the case where hopping is an advantage rather than a problem
(V07 §14, `make hopping-target`). The hop range is alias-free on the shipped
30 mm 2×2: measured 0.03–0.09° at 3.5 GHz even at 70°, with the first failure at
6 GHz. One 1 MHz hop is a single bin and gives 2.15° at 2 snapshots, 0.29° at 64
(an 8 µs dwell per hop at 512 ns frames). But hops accumulate: a through-origin
phase fit over the hops of one track turns 800 MHz of hop frequencies into a
synthetic aperture and takes a 1 MHz hopper from 0.740° to **0.078° after 64
hops**. Identity is then a job for a prediction gate plus the invariants a hop
cannot change — bandwidth, dwell, cadence: trusting the strongest hop is wrong
28 times in 60, the gate plus the bandwidth invariant is wrong 0 times, and the
bandwidth invariant is quantised by the bin width (1 and 2 MHz are the same
fingerprint). A decoy that copies the invariants and *crosses* the track is not
separable by identity at all: 15 % of crossings still end on the wrong track.

Several emitters in one picture are **clustered, not masked** (V07 §15,
`make target-clusters`). Clustering happens on the coordinates a hop cannot
change — direction and bandwidth — and is then linked over frames with cadence as
the tie-break: a carrier-only link, the frequency-hopping-network way, leaves
20.7 tracks for three emitters and recovers one, while direction plus bandwidth
recovers three of three at purity 1.00, and cadence separates two emitters that
share both (2.3 → 3.0 of 3). Masking the known emitter out of the spectrum was
measured and rejected: replaying the last hop predicts 0.20 % of the next one, a
band mask takes every other emitter with it (0 % kept), a notch deletes whoever
shares the bin (0 % kept), and a spatial null keeps that emitter's power but
destroys its direction (82–120° of error) because a 2×2 seen at elevation 0 is a
two-channel array. The deliverable is a labelled map: one row per emitter, the
hopper as scattered blocks along it, the static emitter as a fixed column.

A **moving** emitter changes what "cluster" means (V07 §16, `make moving-targets`).
Direction stops being a key and becomes the state you predict: holding the last
direction keeps 98 % of a 0.5°/frame mover and 73 % at 1°/frame — the measurement
noise — but shatters into 6.6–7.0 pieces at 8–16°/frame, while a constant-velocity
prediction with an acquisition gate opened to the maximum angular speed holds
89–100 % continuity to 16°/frame. A 10°/frame manoeuvre breaks the track as it
must (3.1 tracks for two emitters); identity is then re-established from bandwidth
and cadence with 100 % of the detections staying on the right emitter. Two
constant-velocity movers crossing pass through each other with 0 % swaps, which is
a different result from §14.6's 15–30 %, where the decoy manoeuvred while staying
close. What is constant along a track is its slope, not its position.

With both bandwidth and direction changing, the question is not *what* to cluster on but *which model* each feature needs (V07 §17, `make feature-models`). The rule is one ratio: how far a feature moves in one frame against how well it is measured — about 1° and one bin here. A smooth drift gets a rate (a fixed bandwidth keeps 38–50 % of a widening emitter, a rate 100 %); a feature that *jumps* — a carrier hop, a mode change — cannot be a position key, so it is dropped from the cost or replaced by its cadence, which separates 100 % of the time and only after a few frames; a jump in direction is a new track, never a fast target; and level never enters the cost at all.

If the constant is the **modulation**, the label needs an automatic classifier (AMC) — and a label is a *mode*, not a measurement (V07 §18, `make modulation-clusters`). Measured over five classes with six features and nearest class mean: 100 % at 10 dB with 64 symbols, chance at 0 dB (one class absorbs every burst), and 0 % for BPSK/QPSK once a 1e-3/sample carrier remains, because the fourth-order cumulant rotates away. A 3-frame vote does not raise a biased accuracy but makes the label sticky (0.26 → 0.18 flips per frame), which is what a track needs. In the cost it separates two emitters that share direction and bandwidth and differ only in modulation (covered 1.42 → 3.00 of 3, purity 0.75 → 1.00) and does nothing for two that share it — a match that is always true is not a test.

All of it is one **policy**, and the policy is a ladder (V07 §19, `make policy`): `mod → direction → bandwidth → cadence → [cepstrum]`, each rung applied to the cells the previous one left. Measured over six scenes, each rung solves exactly one scene and removing any rung loses exactly that scene: different modulation 100 % on the label alone, same modulation with different directions 100 % on direction alone, a bandwidth-only pair and a cadence-only pair likewise. A pair with the same modulation *and* the same direction must **not** be split — one cell is the correct answer — and when one of the two is a repeater, the cell is flagged by a verification index (cepstrum) that reports two arrivals 100 ns apart, 97 % of the time with a 0 % false-alarm rate, and never invents a partition. `--policy` replaces the ladder, and the report says what the replacement costs.

The modulation label is the one algorithm that runs on the **RPU** (V07 §20, `make amc-port`, [`docs/AMC_ON_R5.md`](docs/AMC_ON_R5.md)): six features, one 1024-point FFT, nearest class mean, no allocation — the MATLAB source (`matlab_v7/classify_modulation.m`) is compiled by Embedded Coder for `ARM Cortex-R`, and the C firmware the RPU links is verified on the host against the same model: 100 % label agreement on 120 bursts, worst feature error 1.4e-5 in single precision, accuracy identical to the model (72.5 %). Embedded Coder and the board are gates G8b/G8c, not claims. The whole machine on one page, as a figure ([PNG](docs/diagrams/system_block.png), [SVG](docs/diagrams/system_block.svg), `make diagram`), is [`docs/SYSTEM_BLOCK_DIAGRAM.md`](docs/SYSTEM_BLOCK_DIAGRAM.md); every gate with its blocker is [`docs/GATES_G1_G7.md`](docs/GATES_G1_G7.md); every algorithm with its evidence is [`docs/ALGORITHMS.md`](docs/ALGORITHMS.md).

## Two MATLABs on one machine

Model Composer 2023.2 needs MATLAB **R2022b**; everything else (preflight, the
HIL vectors, the Embedded Coder build, HDL Coder) uses the `matlab` on `PATH`,
usually R2024a. [`docs/TWO_MATLABS.md`](docs/TWO_MATLABS.md) says which command
uses which install, and `config.local.mk` (untracked) is where the two paths go:

```make
MATLAB_2022B   ?= /path/to/R2022b/bin/matlab
MODEL_COMPOSER ?= /path/Model_Composer/2023.2/bin/model_composer
```

`make tools MATLAB=1` prints both installs and an explicit `[ok]`/`[MISS]` for
every toolbox the code generator needs.

`make mc` **builds** the channelizer IP (it does not open a GUI): MATLAB R2022b
runs in `-batch` with Model Composer's System Generator paths added, compiles the
model's token to IP Catalog, installs `component.xml` in the IP repository, and
fails the stage if no IP came out. It deliberately does **not** go through the
Model Composer launcher, which evals its arguments and appends its own `-r`; a
real run died there ([evidence](docs/evidence/2026-11-07-host-probe/model_composer_launcher_eval_bug.txt)).

No `.slx` is committed (it is a binary built once in the GUI), so the model
goes in `<repo>/ip/model_composer/channelizer/channelizer.slx` and then:

```bash
make mc-path        # the exact path this checkout uses, and whether it exists
make mc             # builds the IP from that file
make mc-gui         # only to create/edit the .slx
make mc-find        # if you already have one somewhere else
make mc-verify      # after a GUI compile
```

## Progress that survives a push

Logs live in `build/logs/` and are not tracked. Every stage also writes a small
page in [`docs/progress/`](docs/progress/PROGRESS.md) — result, times, command,
the lines that matter — and `PROGRESS.md` is one table over all 20 stages:

```bash
make step02_hls_covariance     # writes build/logs/... and docs/progress/step02_hls_covariance.md
make progress                  # rebuilds docs/progress/PROGRESS.md
```

Commit `docs/progress/` after a run; then the branch itself shows how far the
build got, including the stages that failed.

## The eight steps, one folder each

The repository is also organised the way you build it — eight folders in signal
order, each with a `GUIDE.md` (formulas, what to implement, what fails), the
MATLAB, the C or the python, and a test bench that runs:

| folder | you get | bench |
|---|---|---|
| `step0_antenna/` | the 2×2 array, the ambiguity limit, and the scene files everything else is tested on | `PASS 7/7` |
| `step1_rfadc_mts/` | the 64 kB capture record, 12-bit quantiser, **0.73 ps** MTS skew budget, loopback | `PASS 5/5` |
| `step2_pl_ip/` | the eight HLS kernels, the exact `vitis_hls` command for each, Q13 fixed-point budget | `PASS 3/3` |
| `step3_r5_doa/` | **WPI → ML → Gauss–Newton** on the R5F in C, with the numpy reference | `PASS 6/6` |
| `step4_r5_amc/` | the classifier, MATLAB → Embedded Coder → C, both builds | `PASS 5/5` |
| `step5_r5_tracking/` | the ladder, the track store, the decoy check | `PASS 7/7` |
| `step6_ps_linux/` | the A53 supervisor, cross-compile and systemd instructions | `PASS 5/5` |
| `step7_board_bringup/` | the 12-command checklist and every gate still open | `PASS 5/5` |

```bash
make steps     # all eight, ~40 s, no licence, no board
```

[`STEPS.md`](STEPS.md) is the map, and it also lists every command that has been
written but never run, with what each one needs. `make tools` prints where those
tools would have to be on your machine.

## Accuracy statement

V7 demonstrated a 3-D Monte-Carlo RMSE below 0.1° in its stated simulated
acceptance domain (SNR ≥ 15 dB, 4096 coherent snapshots, calibrated 2×2 array).
That is a simulation contract, not a guaranteed field result. A real ZCU208
build must also prove converter coherence, MTS repeatability, channel/cable and
mounting calibration, quantized parity, timing closure, and HIL/anechoic tests.
