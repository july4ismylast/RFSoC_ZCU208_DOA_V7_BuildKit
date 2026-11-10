# Evaluation set

Twenty-four questions to test whether a bot actually uses the skill. Each entry gives what a good
answer *must* contain, and the trap it must not fall into. Grade by facts, not wording.

Two families: **L** (lookup — the answer is in the references) and **T** (trap — a plausible wrong
answer is easy). A bot that passes all 24 is safe to put in front of a user; one that fails a T is not.

| # | question | must contain | must not say |
|---|---|---|---|
| L1 | What board and part is this designed for? | ZCU208, `xczu48dr-fsvg1517-2-e` | "ZCU111", "ZCU216", a generic UltraScale+ |
| L2 | How many ADC channels, and what band? | 4 channels, 2–4 GHz, 3.0 GHz centre, 1.5 GHz IBW | 8 channels, or "DC–4 GHz" |
| L3 | What is the channelizer's output width and format? | 416 bit, 8 samples × 26 bit × I/Q, `sfix26_En24`, 128 beats/frame | "512-bit", "16-bit", "cfloat" |
| L4 | How many frequency bands and taps? | 1024 bands, 12 taps/band, 12 288 coefficients | "256 bands", "16 taps" |
| L5 | What does the bridge's register 0x08 control? | `SCALE_SHIFT`, default 9, the s26→s16 quantizer | "the NCO", "the decimation" |
| L6 | How does the PS read the covariance? | through `axi_fifo_mm_s` FIFOs, polled; no DMA | "AXI DMA", "interrupt-driven" |
| L7 | Which core runs the DOA estimator? | the R5F; the A53 runs the supervisor | "the A53 runs the estimator" |
| L8 | What are the eight custom IP VLNVs? | all eight with `openai:doa:` prefix and the pinned versions | a made-up version, or `xilinx.com` for a custom IP |
| L9 | How many stages does the build have, and what is `make status` for? | 20 stages; stamps vs logs | "16 stages", "it runs the pipeline" |
| L10 | Which command proves the eight host benches? | `make steps` | `pytest`, `ctest`, `nosetests` |
| L11 | Where do the post-route reports land? | `build/output/post_route_*.rpt`, copied into `docs/evidence/` | "inside the Vivado project only" |
| L12 | What did the full build achieve? | 20/20 PASS, 48.48 % LUT, 71.62 % BRAM, 36.12 % DSP, WNS +0.164 ns | any number without BRAM being tightest |
| L13 | Which resource is tightest? | Block RAM at 71.62 % | "DSP", "LUT" |
| L14 | What are the four open items on hardware? | G5, G6, G7b, G8c (plus G3 and G8b needing tools/licence) | "nothing, it is validated" |
| T1 | What frequency is the DOA clock? | 125 MHz; 7.8125 ns is only the HLS constraint | "128 MHz", "the DOA clock is 7.8125 ns" |
| T2 | All kernels are constrained at 4 ns, right? | no: only `rfdc_repack4` and `phase_interf_4ch` | "yes" |
| T3 | Did Vitis HLS produce the channelizer IP? | no, MATLAB + HDL Coder; HLS produces the six C kernels | "yes, the channelizer is an HLS kernel" |
| T4 | Is the AMC 72.5 % accurate in the field? | no: synthetic 5-class set, and the model scores the same | "72.5 % field accuracy" |
| T5 | The design is validated, since the bitstream exists? | no: a bitstream closes G4 only; G5/G6/G7b/G8c are NOT RUN | "yes, it is validated" |
| T6 | Does the FFT normalise the channelizer output? | no, `NormalizeFFT=false`, hence `sfix26_En24` | "yes, it normalises" |
| T7 | How many eigenvalues does the estimator compute? | none: four power iterations for the dominant vector | "it does an eigendecomposition" |
| T8 | How exhaustive is the ML search? | 36 evaluations on a local 3×3 grid from the WPI seed | "a full 0.005° search of ±55°×±45°" |
| T9 | Is MTS verified? | designed, not verified; no board run | "MTS is locked and verified" |
| T10 | Can you give the utilisation after adding a fifth channelizer? | no: utilisation is only valid for the built bitstream | any invented percentage |

## Scoring

- Any T answered wrongly → fail, regardless of score.
- L questions: 2 points for the fact plus a source, 1 point for the fact alone, 0 otherwise.
- Full marks require a `source:` line naming a file that exists in the repository. A bot with no file
  access may say "from the project summary" once, but not as a habit.

## Regression use

Re-run this set after editing any file under `skills/rfsoc-doa-v7/`. Expected failures after an edit
to `references/numbers.md` are the numbers themselves; `make skill-check` catches the mechanical ones
(missing file, missing token, wrong VLNV, dead make target) before a human reads an answer.
