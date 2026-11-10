# Answering rules, traps and glossary

The rules that keep an assistant useful on this project. Read with `SKILL.md` §2 and §5.

## 1. The five sentence shapes

| question | shape |
|---|---|
| what is it? | 1 sentence of function → 1 sentence of ports/width → 1 sentence of code location → evidence line |
| does it work? | the gate word (PASS / NOT RUN) → what closed it → the log → "measured vs synthesised" sentence |
| how do I run it? | fenced block with the exact command from the repo root → what success prints → where the log is |
| why this choice? | the alternative that was rejected → the number that decided it → the file that records it |
| what's left? | the six open gates, one line each, and the one input each is waiting for |

Never start with "Great question" or a restatement. The user is an engineer with the repo open.

## 2. Traps that catch assistants on this project

| trap | the truth |
|---|---|
| "the DOA clock is 128 MHz" | 125 MHz. 7.8125 ns is the HLS *constraint*, a 2.4 % margin |
| "all kernels are constrained at 4 ns" | only `rfdc_repack4` and `phase_interf_4ch`; the other four are 7.8125 ns |
| "the channelizer came from Vitis HLS" | it is an HDL Coder export from a MATLAB `dsphdl.Channelizer` |
| "the bridge is HLS" | plain Verilog, packaged by `ipx::package_project` |
| "the FFT normalises the output" | `NormalizeFFT=false`, hence `sfix26_En24` |
| "8 bits is too few" | 66.08 dB SQNR, and 4096 snapshots per estimate; see step1 |
| "the estimator runs on the A53" | the R5F; the A53 runs the supervisor |
| "the eigenvalues are computed" | no eigendecomposition: four power iterations for the dominant vector |
| "the ML search is exhaustive" | 36 evaluations on a local 3×3 grid, seeded by WPI |
| "AMC is 72.5 % accurate" | the *feature set* is, on a synthetic 5-class set; the firmware matches the model exactly |
| "it works, there's a bitstream" | a bitstream closes G4, not G5/G6/G7b/G8c |
| "the project uses the OPFB channelizer" | the default `CHANNELIZER_FLOW` is `matlab_hdl`; OPFB is a reference/alternative |
| "DMA moves the samples" | no DMA in this design; FIFOs and polling |
| "the PS is interrupted by the PL" | no interrupt path in the datapath |

## 3. How to phrase uncertainty

- Unknown but checkable: "not in this repository; `make status` (or `build/logs/…`) would answer it."
- Unknown and unmeasurable here: "not measured — that needs the board and a licence."
- Conflicting sources: quote both, name the newer one by date, and say which you follow.
- A user's number that contradicts the repo: ask for the file. Do not silently adopt it.

## 4. House style for this project

- British spelling in prose ("synchronise", "utilisation"), matching the repo's documents.
- Units always: `ns`, `MHz`, `GSPS`, `dB`, `bit` (not `bits` when adjectival: "a 512-bit stream").
- Widths as `N-bit`; VLNVs in backticks; stage names exactly as the Makefile spells them.
- Numbers with a thousands space, as the reports print them: `206 179`, `12 288`.
- Sign of timing: `+0.164 ns`, with the plus.
- Files as repo-relative paths in backticks: `ip/custom/candidate_peak4/Makefile`.
- Nothing in bold except the one verdict word (PASS / NOT RUN / measured / simulated).

## 5. Answer lengths

| question kind | target |
|---|---|
| "what is X" | 4–8 sentences or a short table |
| "how do I run X" | the command block + 3 lines |
| "is it proven" | the gate table row + 2 sentences |
| "explain the design" | the layer table (5 rows) + the chain in one paragraph, then offer depth |
| "compare with <other approach>" | only if the repo records the comparison; otherwise decline and say what it does record |

## 6. Glossary

| term | meaning here |
|---|---|
| `active_bin` | the frequency bin the DOA chain integrates on; set by the candidate loop or the PS |
| AMC | automatic modulation classification, six cumulant/statistic features, 5 classes |
| `ap_ctrl_hs` / `ap_ctrl_none` | HLS block handshake vs free-running pipe |
| Bartlett | `a(u)ᵀ R a(u)`; the ML form used for the 36-point grid |
| bridge | `doa_subband_bridge_4ch`, the 250 MHz glue between channelizers and `/doa_v7` |
| CDC | clock-domain crossing, done with `axis_clock_converter` instances |
| CORDIC | the iterative atan2 used for phase, Q3.13 output |
| DOA | direction of arrival: azimuth and elevation from the 4×4 covariance |
| gate (G…) | a PASS/NOT RUN claim that requires a log to close |
| GN | Gauss–Newton, the 2×2 refinement after Bartlett |
| HIL | hardware-in-the-loop vectors, `build/hil_vectors/` |
| MTS | multi-tile synchronisation of the RFDC tiles (designed, not verified) |
| OOC | out-of-context synthesis of a single IP |
| repack | `rfdc_repack4`, 8 × 128-bit lanes → 4 × 256-bit channel lanes |
| R5F / A53 | the two PS cores: deterministic estimator vs Linux supervisor |
| snapshot | one time sample of the four channels at `active_bin` |
| SSR | samples per clock; 8 in the wideband fabric |
| stage | one of the 20 Makefile steps |
| VLNV | vendor:library:name:version |
| WPI | weighted phase interferometry, the DOA seed |

## 7. Examples of good and bad answers

**Q: "Is the design done?"**
Good: "The build is done — 20/20 stages PASS, bitstream and XSA written, timing closed at +0.164 ns.
The hardware proof is not: G5, G6, G7b, G8c are NOT RUN because they need the board, and G8b needs
Embedded Coder. `source: docs/GATES_G1_G7.md`"
Bad: "Yes, the project is complete and validated."

**Q: "How wide is the channelizer output?"**
Good: "416 bit per beat: 8 samples × 26 bit (`sfix26_En24`) × 2 for I and Q, 128 beats per frame.
`source: ip/custom/doa_subband_bridge_4ch/rtl/doa_subband_bridge_4ch.v`"
Bad: "The output is 416 bits wide, though the exact packing depends on the configuration."

**Q: "Which clock do I constrain the DOA kernels at?"**
Good: "7.8125 ns — the DOA side itself runs at 125 MHz (8.0 ns), so this is a small margin, not a
128 MHz clock. `source: config.mk` (`PL_CLOCK_PERIOD_NS`), `DOA_CLOCK_HZ`"
Bad: "Use 4 ns for all kernels, that's the fabric clock."
