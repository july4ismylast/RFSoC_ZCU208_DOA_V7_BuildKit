# The algorithms, one entry each

Every algorithm in the project in one table: what it does, what it consumes and
produces, where the evidence lives, how it fails, where it runs, and whether it is
implemented. Nothing here is a claim beyond what the cited evidence file says.

Legend for **status**: `host-PASS` = a script in this repository measures it and
the report says PASS; `IP-written` = hardware source exists, host-tested, never
synthesised; `MATLAB` = reference model only; `policy` = host-measured decision
logic, no hardware.

| # | Algorithm | In → out | Evidence | Fails when | Runs on | Status |
|---|---|---|---|---|---|---|
| A1 | RFDC down-conversion and SSR repack | 2 GS/s × 4 → complex baseband streams | V04 contract; `ip/custom/rfdc_repack4` host test | wrong mode or clock plan | PL hard IP | IP-written |
| A2 | Channelisation and spectrum power | stream → 410 carriers, per-bin power | V06 feasibility; `make lint` (Tcl) | sample-rate plan off by 2× | PL (HLS) | IP-written |
| A3 | Candidate detection (peak + noise gate) | power → candidate bins | `ip/custom/candidate_peak4` host test | two emitters in one bin; noise floor drift | PL (HLS) | IP-written |
| A4 | Triggered capture | candidates → 4096 × 4 complex | `ip/custom/doa_covariance_4ch_v4` | trigger too late for a hopper | PL | IP-written |
| A5 | Calibrated covariance | snapshots → 4×4 int64 | `make -C ip/custom/doa_covariance_4ch_v4 host-check` | uncalibrated array | PL (HLS) | host-PASS |
| A6 | Per-bin cross-spectrum + CORDIC phase | snapshots → phase per baseline | V07 §5–7; `phase_interf_host_tb`, `phase_interf_kernel_hostrun` | 4.0 ns not closed (G3) | PL (HLS) | host-PASS (G1a/b), no synthesis |
| A7 | Weighted phase interferometry (WPI) | phase + covariance → az, el | V07 §6, §10; `wpi_vs_music_check.txt` | two emitters (manifold rank 2 on a 2×2) | R5 | host-PASS |
| A8 | Local ML + Gauss–Newton | covariance → refined az, el | V07 §6; `matlab_v7/estimate_doa_from_covariance_v7.m` | local minima; needs a good seed | R5 | MATLAB |
| A9 | Unit-vector EKF | az/el sequence → smoothed track | `matlab_v7/PlatformDynamics3D.m` | manoeuvre (process noise) | R5 | MATLAB |
| A10 | Clustering in (f, az, t) | detections per frame → tracks | V07 §15; `target_clustering.txt` | two emitters with equal direction and bandwidth | R5 | host-PASS |
| A11 | Motion model (rate prediction, acquisition gate) | cluster sequence → tracks for movers | V07 §16; `moving_targets.txt` | a jump, not motion | R5 | host-PASS |
| A12 | Feature-model selector (rate / mode / pattern / drop) | feature statistics → which model | V07 §17; `feature_models.txt` | a feature whose change ≈ its error | R5 | host-PASS |
| A13 | AMC: six features + nearest class mean | burst → label + margin | V07 §18; `modulation_clusters.txt` | ≤0 dB (chance), same modulation, residual carrier | **R5 (firmware)** | host-PASS + G8a |
| A14 | Association ladder (`mod → dir → bw → cadence`) | cells → tracks | V07 §19; `cluster_policy.txt` | a cell with a decoy in it | R5 | host-PASS |
| A15 | Decoy verification (cepstrum ripple) | cell power → two-path delay | V07 §13, §19.1; `radar_decoys.txt`, `cluster_policy.txt` | no ripple: incoherent or zero-delay decoy | R5 | host-PASS (G7a) |
| A16 | Two-path ML (delay + angle) | covariance + delay → both directions | V07 §13.7; `radar_decoys.txt` | co-located zero delay | R5 | host-PASS |
| A17 | Calibration (phase/gain vs frequency) | sweep → coefficients | `matlab_v7/estimate_multifrequency_calibration.m` | temperature drift between sweeps | A53 | MATLAB |
| A18 | Narrowband multi-target (1–50 MHz) | carriers → up to 8 emitters | V07 §12.4; `narrowband_targets.txt` | co-channel emitters | R5 | host-PASS |

## The four that decide what a detection *is*

A10–A15 are not steps in a pipeline; they are the same decision at four levels of
certainty, and they were built in that order:

```
 A10  is this detection the same emitter as last frame?      (direction, bandwidth)
 A11  ... and if it moves?                                    (rate, acquire gate)
 A12  ... and if a feature jumps?                              (mode or pattern)
 A13  ... and if two emitters differ only in modulation?        (label)
 A14  ... and if they differ in nothing?                        (do not split)
 A15  ... and if one of them is a decoy?                        (verify the cell)
```

Each one is measured with the metric that can fail: continuity (A10, A11),
kept-percentage and tracks (A12), accuracy and flip rate (A13), covered cells and
purity (A14), detection against a 0 % false-alarm rate (A15).

## What no algorithm in this table does

* **No authentication.** A14 and A15 identify geometry and arrival, not identity.
  A decoy that copies the waveform copies the label (§18.6).
* **No ECCM.** The decoy problem here is DWQ/DOA: the decoy must not disturb the
  protected source's own function (§13.7). No jamming model exists.
* **No hardware accuracy claim.** A1–A6 are synthesised by nobody yet (G2–G4), so
  every number attached to them is a host or simulation number.

## Where to read more

| Topic | Document |
|---|---|
| the machine, box by box, and where each gate sits | [`SYSTEM_BLOCK_DIAGRAM.md`](SYSTEM_BLOCK_DIAGRAM.md) |
| the gates: criteria, blockers, what closing each takes | [`GATES_G1_G7.md`](GATES_G1_G7.md) |
| decoy discrimination in one place | [`DECOY_DISCRIMINATION.md`](DECOY_DISCRIMINATION.md) |
| AMC → Embedded Coder → R5F | [`AMC_ON_R5.md`](AMC_ON_R5.md) |
| the estimator, the array, the accuracy budget | [`../V07_PHASE_INTERFEROMETRY.md`](../V07_PHASE_INTERFEROMETRY.md) §3–§7 |
| every evidence file and what produced it | [`evidence/2026-11-06-phase-interf/REVIEW.md`](evidence/2026-11-06-phase-interf/REVIEW.md) |
