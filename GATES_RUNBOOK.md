# Gates G2–G6: what to run, what to look at, how to publish the logs

Everything in this repository that can be proved without a licence has already
been run (`make lint`, `make verify-phase-interf`). This page is the operator
sheet for the rest: gates **G2 … G6** of
[`V07_PHASE_INTERFEROMETRY.md`](V07_PHASE_INTERFEROMETRY.md) §8, which need
Vitis HLS 2023.2, Vivado 2023.2, MATLAB, or a board.

Run the gates in order. Each gate's failures are cheaper to fix than the next
gate's, so skipping ahead costs licence hours rather than saving them.

---

## 0. Before spending a licence

```bash
make lint                     # Tcl/XDC/SV syntax, shell, dry-runs, IP VLNV pins (~5 s)
make verify-phase-interf      # estimator + resource studies, g++ core and kernel tests (~3 min)
make compare-estimators       # V07 section 10 and 11 at full trial counts (~6 min)
make status                   # which stages already have stamps
```

`make compare-estimators` is the one that decides the *hardware* questions —
element pitch (30 mm), which estimator the PS runs, and whether the external
review's frequency-domain chain is adopted. Run it before anyone cuts metal.

If those are green, the remaining failures are tool issues (versions, licences,
`BASE_XPR`, MATLAB path) rather than code issues.

Configuration that must be right *before* G2:

| Item | Where | Why it bites |
|---|---|---|
| `VIVADO`, `VITIS_HLS` | `config.mk` | Both are pinned to 2023.2 by `config/ip_versions.tcl`; `step00` refuses another version |
| `BASE_XPR` | `config.mk` (`BASE_KIND=mts` default) | The whole flow copies a *verified* ZCU208 MTS base project; a substitute base invalidates every downstream comparison |
| `WIDEBAND_CLOCK_PERIOD_NS` | `config.mk` (4.0) | `phase_interf_4ch` is constrained at 4.0 ns by `build_hls.tcl`; G3 fails loudly if the packaged IP disagrees |
| `V7_MATLAB_ROOT` | `config.mk` | Only needed for G5 (`step14_hil_vectors`) |
| `ARRAY_AXIS_SPACING_M` | `config.mk` (0.030) | Set by the wrap-free rule in V07 section 11; 50 mm is rejected, 25 mm is the ±90° fallback |

```bash
make step00_preflight         # tools, part, versions, catalog
make step01_fetch_references  # upstream references (once)
```

---

## 0.1 The whole chain, step 0 to the release, in one page

Host-only (no licence): run these first; they are the only ones that can be
green in this environment.

```bash
make lint                                  # static checks, ~5 s
make verify-phase-interf                   # host estimator/kernel checks, ~3 min
make compare-estimators                    # V07 section 10 + 11 studies, ~6 min
make matlab-lint                           # optional, needs MISS_HIT
```

Licence tools (Vitis HLS 2023.2, Vivado 2023.2, MATLAB R2024a). Every HLS model
in the kit is a target of its own, and `make hls-all` builds all seven of them in
one command (`doa_covariance_4ch_v4`, `spectrum_power4`, `candidate_peak4`,
`beam_weight_4ch`, `rfdc_repack4`, `doa_subband_bridge_4ch`, `phase_interf_4ch`):

```bash
make step00_preflight                      # tools, part, version lock, IP catalog
make step01_fetch_references               # pins the upstream references (once)

make hls-all                               # every custom HLS IP: csim, csynth, export
# or one at a time, exactly what the numbered stages do:
make step02_hls_covariance                 # V7 4-channel covariance
make step03_hls_spectrum                   # 4-lane spectrum power
make step04_hls_candidate                  # streaming peak/noise candidate
make step04_hls_beam                       # optional vector beam monitor
make step05_hls_repack                     # V05 RFDC SSR-8 I/Q gearbox
make step05_channelizer                    # 1024-band channelizer (CHANNELIZER_FLOW=...)
make step05_subband_bridge                 # 4-channel subband stream bridge
make step05_hls_phase_interf               # V07 per-bin cross-spectrum + phase  <- new block

make -C ip/custom/phase_interf_4ch collect-reports   # G2 reports into build/output/
make step06_collect_ip                     # VLNV check, one IP repository

make step07_vivado_project                 # copy the verified MTS base
make step08_vivado_integrate               # add DOA V7 through config/zcu208_bd_map.tcl
make step09_vivado_validate                # BD validation, clock/interface reports
make step10_synth                          # synthesis
make -C ip/custom/phase_interf_4ch gate3-ooc   # G3: OOC timing at 4.0 ns
make step11_impl                           # opt/place/route
make step12_bitstream                      # .bit/.hwh
make step13_export_xsa                     # hardware handoff
make step14_hil_vectors                    # V7 fixed-point HIL vectors (MATLAB)
make step15_package                        # release bundle + manifests

make status                                # which stamps exist
make push-gate-logs                        # commit + push the allowlisted logs
```

`make pipeline` runs steps 00–15 in order once the prerequisites exist; the list
above is the same thing with every artefact-producing sub-step named.

---

## G2 — Vitis HLS: C simulation, synthesis, export, packaging

```bash
make step05_hls_phase_interf                       # csim → csynth → export_design
make -C ip/custom/phase_interf_4ch collect-reports # copies the Vitis reports into build/output/
make step06_collect_ip                             # VLNV check + one IP repository
make status
```

What it proves when green: the kernel compiles and simulates in the real tool,
`csynth` schedules it, the IP exports, and `step06` accepts exactly the VLNV that
`config.mk` asks for (`openai:doa:phase_interf_4ch:1.0`).

Look at:

```bash
grep -E "ERROR|WARNING|PASS|FAIL" build/logs/step05_hls_phase_interf.log | head -40
sed -n '1,60p' build/output/v07_gate2_csynth.rpt              # target clock, estimated clock
grep -E "II|Latency" build/output/v07_gate2_csynth.rpt | head -20
sed -n '1,40p' build/output/v07_gate2_csynth_design_utilization.rpt
```

Pass criteria — all four, not three:

1. `csim_design` reports PASS (the `tb/phase_interf_4ch_tb.cpp` frames).
2. `csynth` target clock is **4.000 ns** (not 7.8125 — that was the bug fixed in
   commit `6c63f60`).
3. `II=1` on `beat_loop` and a bounded latency on `phase_loop`. If `csynth`
   reports the phase loop pipelined at `II=1`, the tool has replicated six CORDIC
   chains: read the utilisation report before accepting it.
4. `build/output/v07_gate2_csynth_design_utilization.rpt` is within the §7.4
   budget range (≈192–384 DSP48 at `II=1`). If DSPs exceed ~400, set
   `#pragma HLS PIPELINE II=4` on `beat_loop` — the channelised input needs a
   beat every ~2 ms, not every cycle — and re-run. Record whichever you chose.

Publish:

```bash
make push-gate-logs
```

---

## G3 — Vivado out-of-context synthesis and timing at 4.0 ns

Needs G2's packaged IP in `build/ip_repo/phase_interf_4ch` (i.e. `step06` green).

```bash
make -C ip/custom/phase_interf_4ch gate3-ooc
cat build/output/v07_gate3_ooc_synthesis.rpt
```

The summary report carries the machine-readable lines:

```text
V07_GATE3_OOC_LUT=…            V07_GATE3_OOC_FF=…
V07_GATE3_OOC_DSP=…            V07_GATE3_OOC_BRAM=…
V07_GATE3_OOC_WNS_NS=…         V07_GATE3_OOC_TNS_NS=…
V07_GATE3_OOC_CLOCK_PERIOD_NS=4.000
V07_GATE3_RESULT=PASS WNS=… ns
```

Pass: `V07_GATE3_RESULT=PASS`, i.e. WNS ≥ 0 at 4.000 ns **and** `ap_clk` read
back at 4.000 ns. The script already fails on either condition, so a green exit
code is the gate.

If `open_run <ip>` is rejected by your 2023.2 build, the script's error message
gives the checkpoint path (`<ip>_synth_1` run directory); open it with
`open_checkpoint` and run the same report commands. Fix the script, don't delete
the gate.

Publish: `make push-gate-logs`

---

## G4 — Block-design integration, validation, implementation

```bash
make step07_vivado_project
make step08_vivado_integrate
make step09_vivado_validate
make step10_synth
make step11_impl
```

**Read this first:** `phase_interf_4ch` is packaged and collected, but it is *not*
instantiated in the block design yet. `config/zcu208_bd_map.tcl` attaches the six
existing DOA slaves. Wiring the seventh block is gate G4 work and
`V07` §7.5 lists exactly what it needs (250 MHz wideband `ap_clk`, active-low
reset source, the subband bridge's 512-bit selected-bin stream, a FIFO path for
`m_axis`/`m_phase`, its own AXI-Lite segment, and the per-bin calibration
sequence). Adding it blind to an unmeasured base design is how a base-project
regression gets blamed on the new IP.

So there are two honest G4 variants:

* **G4a (today's build, no new block):** steps 07–11 as written. Proves the
  existing chain still closes timing with the current IP repository.
* **G4b (with the phase block):** G4a, then edit `config/zcu208_bd_map.tcl`
  following §7.5, then re-run 08–11 and compare utilisation/timing against G4a.

Look at:

```bash
cat build/output/validation_messages.txt      # must be clean
cat build/output/timing_gate.txt              # PASS/FAIL + WNS
sed -n '1,40p' build/output/post_synth_utilization.rpt
sed -n '1,40p' build/output/post_route_utilization.rpt
grep -E "WNS|WHS|TNS" build/output/post_route_timing.rpt | head
```

Publish: `make push-gate-logs` (the allowlist already includes
`validation_messages.txt`, `timing_gate.txt`, `post_*_utilization.rpt`,
`post_route_timing.rpt`, `route_status.rpt`).

---

## G5 — RF loopback on hardware: does the sign survive silicon?

This is the gate that converts "the simulator says +0.37 rad" into a hardware
fact. It needs the bitstream from G4, a DAC→ADC loopback (the MTS base keeps the
DAC loopback structure for exactly this), and MATLAB.

```bash
make step14_hil_vectors        # generates the fixed-point HIL vectors (needs V7_MATLAB_ROOT)
# then, on the board: load the XSA/bitstream, run the PS capture, save the CSV
matlab -batch "addpath('hil/matlab'); report = run_zcu48dr_hil('compare','<capture>.csv'); disp(report)"
```

`run_zcu48dr_hil` has three modes (`prepare`, `loopback`, `compare`); `compare`
returns a struct with `ExactIntegerMatch` and the angle error. Pass criteria:

1. `ExactIntegerMatch == true` — the PL accumulators equal the MATLAB integer
   reference bit for bit.
2. Injected delay → measured phase slope has the **sign predicted in V07 §5.2**
   (a positive `uy` gives a *negative* baseline-0 phase). This is the one place a
   sign error would show up as a physical rather than a numerical fact.
3. Angle error against a known geometric delay ≤ the §6 simulated figure plus the
   §10.3 calibration term, or the difference is written down and explained.

Publish: `make push-gate-logs` (adds `build/logs/step14_hil_vectors.log`), plus
the CSV and the report struct pasted into the evidence snapshot — the script
allowlist does not know about them, so copy them by hand into
`docs/evidence/<date>-hil/` and commit.

---

## G6 — Calibrated array, chamber/field accuracy

No script exists for this gate and none should: it is a measurement campaign.
What it must produce, from `V07` §6 and §10.3:

1. **Frequency-dependent per-channel calibration.** Measure each channel's
   complex response versus RF frequency (VNA, or a stepped-tone source) across
   2.25–3.75 GHz, and store it as one complex coefficient per channel *per
   channelizer bin*. Then the PS must rewrite `cal0..cal3` for the selected bin
   before each frame — a single coefficient per channel costs 0.50° at 200 ps of
   residual delay (measured, §10.3).
2. **Geometry.** Element positions measured (or mechanically fixtured) to
   ≤ 0.1 mm. At the adopted 30 mm pitch, 0.5 mm of position error alone costs
   0.79° (measured, V07 §11.3) against a 0.066° noise term — larger than the
   whole requirement, so the 0.5° claim is a calibration claim.
3. **Angle sweep against truth.** A source at known az/el on a rotator or in a
   chamber, ≥ 20 angles across ±50°, multiple snapshots, record bias and RMS per
   angle and the residual against the §6 simulated 0.22°.
4. **Nothing above may be reported as a 0.5° claim** until items 1–3 are in the
   evidence directory with the raw captures.

---

## Publishing logs for review (the short version)

Two mechanisms exist; both write only what is allowlisted, never build trees.

| Command | What it does |
|---|---|
| `make debug-stage STEP=step05_hls_phase_interf` | runs the stage, then snapshots logs and **commits locally** (no push, prompts first) |
| `make push-gate-logs` | commits **and pushes** the current `build/logs` + `build/output` allowlist, non-interactive |
| `EVIDENCE_YES=1 EVIDENCE_PUSH=1 bash scripts/publish_debug_logs.sh` | the same, spelled out |
| `make debug-stages STEPS="step05_hls_phase_interf step06_collect_ip step07_vivado_project"` | runs a sequence, stops at the first failure, snapshots everything (local commit) |
| `make publish-evidence` | the `docs/evidence/<date>-<flow>/` variant (`ip_manifest.tsv`, OPFB gate reports), with completion markers checked first |

What `push-gate-logs` copies (this is the whole allowlist):

* `build/logs/step0*.log` … `step15_package.log` for the stages listed in
  `scripts/publish_debug_logs.sh` — now including
  **`step05_hls_phase_interf.log`** (added with this runbook);
* `build/output/v07_gate2_csynth*.rpt`, `v07_gate2_csim.log`,
  `v07_gate3_*.rpt` (added with this runbook);
* the pre-existing `step08_base_bd_inventory.txt`, `v07_bd_integration.rpt`,
  `doa_address_map.txt`, `ip_status.txt`, `validation_messages.txt`,
  `post_*_{utilization,timing}.rpt`, `post_route_drc.rpt`, `route_status.rpt`,
  `timing_gate.txt`;
* a `progress.txt` with the per-stage PASS / FAILED / NOT-RUN table and the
  source commit.

Guards you should know about, because they will refuse to run:

* The branch must be `arena/*` (the script exits 2 otherwise).
* Any file outside `build/` is refused.
* Files larger than 15 MB are refused or truncated (head 2 MB + tail 4 MB).
* Stage logs can contain hostnames, usernames and absolute paths — the script
  prints `git diff --cached --stat` and waits for confirmation unless
  `EVIDENCE_YES=1`. Skim `docs/debug-logs/<UTC>-<flow>/progress.txt` before you
  push.

Typical single-gate sequence, end to end:

```bash
make step05_hls_phase_interf
make -C ip/custom/phase_interf_4ch collect-reports
make step06_collect_ip
make -C ip/custom/phase_interf_4ch gate3-ooc
make push-gate-logs
```

and the reviewer then reads
`docs/debug-logs/<UTC>-<flow>/progress.txt`, `step05_hls_phase_interf.log`,
`v07_gate2_csynth.rpt` and `v07_gate3_ooc_synthesis.rpt`.
