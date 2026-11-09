# Gates G1–G8: what they are, why they are not done, and what closing each takes

The gates are the boundary between "measured" and "claimed". Every one of them is
a question that a host script cannot answer, which is why they are listed
separately from the studies. [`GATES_RUNBOOK.md`](../GATES_RUNBOOK.md) is the
operator sheet (commands, logs to publish); this page is the engineering view:
what the gate *is*, what blocks it, what it would take, and where it sits in
[`SYSTEM_BLOCK_DIAGRAM.md`](SYSTEM_BLOCK_DIAGRAM.md).

Run `make tools` (`bash scripts/check_tools.sh`, add `MATLAB=1` to also list the
MATLAB toolboxes) to print where every tool lives on the machine you are on, and
which gate each one unlocks. The status below is what the authoring container
could prove: it has no Vitis, no Vivado, no MATLAB and no board, which is exactly
why the middle of the chain is open.

Status as of this commit:

| Gate | Question | Status |
|---|---|---|
| G0 | is the physics right, on the host? | **PASS** |
| G1a | is the fixed-point core bit-exact? | **PASS** |
| G1b | does the kernel pass its own testbench (shimmed)? | **PASS** |
| G1c | do `config.mk`, `build_hls.tcl` and `collect_ip.sh` agree on the VLNV? | **PASS** (contract only) |
| G2 | does Vitis HLS compile, synthesise and export it? | **PASS** (2026-11-08: `step02`–`step06` all PASS, every VLNV collected) |
| G3 | does the packaged IP meet 4.0 ns out of context? | **NOT RUN** (in context it does: `step10`/`step11` PASS) |
| G4 | does it integrate into the block design and produce a bitstream? | **PASS** (2026-11-08: `step07`–`step12` PASS, `doa_v7_zcu208.bit` written) |
| G5 | on silicon, does the phase sign and offset hold? | **NOT RUN** — needs the board |
| G6 | with a calibrated array, does the accuracy hold in a chamber? | **NOT RUN** — needs array + source |
| G7a | do the decoy criteria pass on host models? | **PASS** |
| G7b | does a repeater get rejected on hardware? | **NOT RUN** — needs board + DRFM/source |
| G8a | does the R5 firmware reproduce the model? | **PASS** (host gcc) |
| G8b | does Embedded Coder build and link it for the RPU? | **NOT RUN** — needs Embedded Coder for the RPU toolchain |
| G8c | does an AMC frame meet its deadline on the R5F? | **NOT RUN** — needs the board |

---

## G0 — the physics, on the host

**Question.** Before any licence is spent: are the estimator, the array geometry,
the spacing rule and the resource screen self-consistent?

**What exists.** `scripts/phase_interf_verify.py` (Monte-Carlo against the
Cramér–Rao bound), `scripts/estimate_wideband_dsp_resources.py` (front-end
screen), `scripts/compare_wideband_estimators.py` (§11), and the later studies
§10–§19 which all run without a licence.

**Why it is already closed.** It is closed by construction: it only needs NumPy.
The recent sections extend it — the association ladder, the AMC label, the decoy
verification index — and `make lint` plus the nine study scripts are the G0
surface today.

**What it does not say.** G0 is a model of the world, not the world. It cannot
detect a broken clock plan, a wrong RFDC mode or a cable swap.

---

## G1a — the fixed-point core, bit-exact

**Question.** Does `phase_interf_core.hpp`, in the arithmetic the FPGA will use,
produce exactly the numbers the model produces?

**What exists.** `make -C ip/custom/phase_interf_4ch host-check` builds the core
with g++ and compares against golden vectors, including the CORDIC phase output
(`phase_from_cordic_q13.m` is the MATLAB twin).

**Why it is closed.** No vendor tool is needed: the core is plain C++ with a
fixed-point type.

**Residual risk.** The host compiler is not Vitis HLS. A bit-exact host result
proves the algorithm and the quantisation, not the schedule. That is G2's job.

---

## G1b — the kernel and its testbench, shimmed

**Question.** Does the HLS kernel's AXI-stream behaviour (handshakes, tlast,
backpressure) work, when the HLS pragmas are replaced by a shim?

**What exists.** `make -C ip/custom/phase_interf_4ch host-kernel-check` compiles
`src/phase_interf_4ch.cpp` with `tb/host_shim/` standing in for the HLS headers.

**Why it is closed.** Same reason: no vendor tool.

**Residual risk.** A shim is not the HLS scheduler. Deadlock-free under the shim
does not prove II=1 or the interface timing.

---

## G1c — the packaging contract

**Question.** Do the three places that name the IP agree: `config.mk`
(`openai:doa:phase_interf_4ch:1.0`), `ip/custom/phase_interf_4ch/build_hls.tcl`,
and `common/scripts/check_component_vlnv.sh`?

**What exists.** The checker, exercised against a synthetic `component.xml`, so a
mismatch fails in seconds instead of after a 40-minute synthesis.

**Why it is closed.** It is a string comparison.

**Residual risk.** It proves the *contract*, not that Vitis produced such a
component. G2 proves that.

---

## G2 — Vitis HLS: C simulation, synthesis, export, packaging

**Question.** Does the kernel synthesise, and does the packaged IP match what the
block design expects?

**Where it sits.** Boxes 3–7 of the block diagram: spectrum power, candidate
gate, covariance, phase interferometry.

**Why it is not run.** Vitis HLS 2023.2 is not installed and cannot be installed
without a licence and ~100 GB. The sandbox that produced the host evidence has
neither. The script exists and is known-correct in the parts that do not need the
tool (Tcl parse, `config_interface`, VLNV).

**What closing it takes.**
1. A machine with Vitis HLS 2023.2 at `VITIS_HLS` (or on `PATH`).
2. `make step02_hls_covariance step03_hls_spectrum step04_hls_candidate step05_hls_phase_interf`
   — each runs C simulation, `csynth_design`, `export_design`, then
   `collect_ip.sh`.
3. Publish `build/output/phase_interf_4ch/hls_reports/*` (utilisation, II, latency)
   with the log, per `GATES_RUNBOOK.md` §G2.
4. Failure modes to expect, in order: II > 1 on the phase core (statement-level
   dependency), DSP over-budget in the CORDIC, and an interface mismatch in
   `component.xml`.

**Cost.** 30–60 min per kernel on a normal workstation.

---

## G3 — out-of-context synthesis and timing at 4.0 ns

**Question.** Does the packaged IP close timing at the wideband clock when
synthesised alone?

**Where it sits.** The same boxes as G2, at the boundary to G4.

**Why it is not run.** Needs G2's packaged IP *and* Vivado 2023.2.

**What closing it takes.**
1. G2 green.
2. `make -C ip/custom/phase_interf_4ch gate3-ooc` — the script fails on WNS < 0 or
   if `ap_clk` is not the 4.0 ns period pinned in `config.mk`.
3. If it fails, the fixes are architectural, not cosmetic: pipeline the CORDIC,
   split the cross-spectrum accumulate, or reduce to 2 bins/cycle.

---

## G4 — block-design integration, validation, implementation

**Question.** Does the whole PL assemble: the new IP added to the verified ZCU208
MTS base, block design validating, synthesis and place-and-route closing?

**Where it sits.** Everything between the RFDC and the AXI-Lite register map — in
other words, the left half of the block diagram at once.

**Why it is not run.** Needs Vivado 2023.2 *plus* a licensed `BASE_XPR`
(`BASE_KIND=mts`). This repository copies a verified base project rather than
recreating one, and that base is not redistributable.

**What closing it takes.**
1. `BASE_XPR` pointing at the ZCU208 MTS base for 2023.2; `make step07_vivado_project`.
2. `config/zcu208_bd_map.tcl` already contains the seventh-block wiring as a
   documented, commented section (§7.5 of V07). Uncomment it, run `step08`, `step09`.
3. `step10_synth`, `step11_impl`, `step12_bitstream`, `step13_export_xsa`.
4. Compare against **G4a** (the base without the new block): utilisation, WNS, and
   that the eight existing DOA slaves still enumerate.

**Note.** G4a (today's build, no new block) is a legitimate first milestone: it
proves the flow and the base, and it is the control for G4b.

---

## G5 — RF loopback on hardware: does the sign survive silicon?

**Question.** Inject a known delay (cable/phase shifter) and check that the
measured phase difference has the right sign, the right slope against frequency,
and an offset inside the calibrated bound.

**Where it sits.** Boxes 1–7 on the board — the first point where a wrong sign
cannot be blamed on the model.

**Why it is not run.** No board. Also needs the bitstream from G4.

**What closing it takes.**
1. G4's bitstream and XSA.
2. A DAC→ADC loopback (the MTS base supports it) or two signal generators locked
   to the same reference.
3. `hil/matlab/` capture scripts + `scripts/radar_decoys.py --replay` for the
   post-processing, and the criterion in `GATES_RUNBOOK.md` §G5.
4. Publish the capture and the sign/offset table; a failure here is almost always
   a clock or a cable, not the estimator.

---

## G6 — calibrated array, chamber or field accuracy

**Question.** With the array calibrated for phase and gain (frequency-dependent),
does the accuracy measured on the host survive?

**Where it sits.** The whole receive chain, plus the calibration manager on the
A53.

**Why it is not run.** Needs a chamber (or a known-good far-field source), a
positioner, and a calibrated array; none are in the repository.

**What closing it takes.**
1. G5 green (the sign is right before calibration means anything).
2. `matlab_v7/estimate_multifrequency_calibration.m` applied to a measured sweep;
   coefficients land in the A53's calibration table.
3. A sweep in azimuth/elevation, compared against the modelled CRB and against
   §6's simulated RMSE.
4. Report both the achieved RMSE and the residual calibration error: a 1.5°
   criterion (G7b) cannot be evaluated if calibration alone is 1.5°.

---

## G7 — decoy discrimination

Two halves, deliberately separated because their evidence is different.

### G7a — host criteria (PASS)

**Question.** Do the discriminators separate a repeater from the protected
source *in the models*?

**What exists.** `make radar-decoy` (`scripts/radar_decoys.py`, study L table) and
§19.1's cepstrum table: a 100 ns repeater is found 100 % of the time with a 0 %
false-alarm rate, and the delay estimate lands within the 16 ns resolution. The
criteria are stated as pass/fail in the report, and `make fmt`-style gates are
relative, never absolute constants.

**What it does not say.** Anything about silicon. G7a is a statement about models
and post-processing.

### G7b — on hardware (NOT RUN)

**Question.** With a real radar, a real repeater and a real delay line, does the
rejection hold?

**Why it is not run.** Needs the bitstream (G4), the calibrated array (G6), a
repeater with a settable delay, and a capture path. Three of those four do not
exist here.

**What closing it takes.**
1. G4 + G6 green.
2. `scripts/radar_decoys.py --replay capture.h5` on a real capture (the replay
   path is already exercised by `make g7-selftest`).
3. Publish: the 1.5° criterion on the control (no decoy), the same on the decoy
   run, and the cepstrum detection table on real noise.

---

## G8 — AMC on the R5 (new with §18–§20)

### G8a — the firmware reproduces the model (PASS, host)

**Question.** Does the C that will run on the RPU return the same label and the
same six features as the model measured in §18?

**What exists.** `make amc-port` → `scripts/amc_port_check.py`: it exports the
model to `firmware/amc_r5/amc_model.h` and `matlab_v7/amc_model_params.m`,
generates 120 bursts across 0–20 dB, compiles `firmware/amc_r5/amc.c` twice
(double and `-DAMC_SINGLE_ACC`), and compares.

Measured (`docs/evidence/2026-11-06-phase-interf/amc_port.txt`):

| check | result |
|---|---|
| label agreement, double build | **100 %** of 120 bursts |
| label agreement, all-single build | **100 %** |
| worst feature error, double | 7e-7 |
| worst feature error, single | 1.4e-5 |
| accuracy through the firmware | 72.5 %, identical to the model |
| labels changed by dropping to single | none |

**What it does not say.** That Embedded Coder emits this code, that it links on
the RPU, or that it is fast enough.

### G8b — Embedded Coder builds it for the RPU (NOT RUN)

**Question.** Does `matlab_v7/build_amc_r5.m` produce a library that the RPU
toolchain links, with the constants and the arithmetic of G8a?

**Why it is not run.** No MATLAB, no Embedded Coder, no ARM Cortex-R support
package in this environment. The script is written and documented; `matlab_v7/verify_amc_vectors.m`
is the check to run *before* codegen, on the same vectors G8a uses.

**What closing it takes.**
1. MATLAB R2023a+ with Embedded Coder and Simulink Coder.
2. `python3 scripts/amc_export.py && python3 scripts/amc_port_check.py` (G8a must
   be PASS — if the C port disagrees with the model, codegen only reproduces a bug).
3. `matlab_v7/verify_amc_vectors.m` → must print PASS.
4. `matlab_v7/build_amc_r5.m` → `build/amc_r5_codegen/`.
5. Link with `armr5-none-eabi-gcc -mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16`,
   then re-run the same vector file **on the target** and compare with G8a's table.
   Codegen is only done when the target agrees with the host.

### G8c — the frame deadline on the R5F (NOT RUN)

**Question.** Does one 1024-sample burst fit the frame budget, with the FPU the
R5F actually has?

**Why it is not run.** Needs the board and a counter.

**What closing it takes.** A cycle count around `amc_run()` at the operating
frequency, plus the deadline: a detection frame arrives every 16 snapshots of the
capture (8 µs of data at 2 GS/s), and the R5F must classify every detection in
the frame before the next one. The expected cost is dominated by the 1024-point
FFT and the 1024 `atan2` calls; both are single-precision and neither has been
timed here. Until G8c passes, no latency claim may be quoted.

---

## Why the gates are ordered this way

Each gate is cheaper to fail than the next:

```
G0 host physics          minutes, no licence
G1 host core + contract  minutes, no licence
G8a host firmware        minutes, no licence
G2 HLS                   ~1 h per kernel, licence
G3 OOC timing            ~20 min, licence, needs G2
G4 BD + bitstream        hours, licence, needs a licensed base
G5 loopback              needs the board, needs G4
G6 chamber               needs the board, a chamber, a calibrated array
G7b decoy on hardware    needs all of the above plus a repeater
G8b codegen + link       needs MATLAB, then G4's toolchain
G8c R5 deadline          needs the board, needs G8b
```

Skipping a gate does not save the time; it moves the failure to a place where it
costs more. The two ends of the chain (G0/G1/G8a and G7a) are green, which is why
this repository can state its simulated results precisely and its hardware
results not at all.
