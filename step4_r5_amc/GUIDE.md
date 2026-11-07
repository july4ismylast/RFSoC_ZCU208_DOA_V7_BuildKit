# step4 — AMC on the R5F (MATLAB → Embedded Coder → C)

**Gates:** G8a (**closed**: C == model, 100 % label agreement), G8b (Embedded
Coder build, **open**), G8c (cycles on the R5, **open**).
**Runs today:** the C, two ways, on any machine with gcc. **Needs MATLAB:**
the codegen step, which is the whole point of the folder.

This is the folder you asked for: the MATLAB modulation classifier, the
Embedded-Coder path to C, and the C itself, side by side with a bench that
proves the two agree.

## The chain

```
matlab_v7/amc_features.m          six features from one burst
        │
        ▼
matlab_v7/classify_modulation.m   nearest class mean + margin  ── Embedded Coder ──►  C
        │                            (build_amc_r5.m, gate G8b)                        │
        ▼                                                                              ▼
scripts/amc_export.py  ──► amc_model_params.m + amc_model.h        firmware/amc_r5/amc.c
                                    (the same tables)                       │
                                                                            ▼
                                                        scripts/amc_port_check.py (G8a)
```

Note what is **not** in that picture: no floating-point toolbox, no `coder.ceval`,
no external library. The generated library is 16 kB of static buffers and one
1024-point FFT, and it allocates nothing.

## The algorithm in one paragraph each

**Features.** For a carrier-recovered burst `x` (1024 samples, 4 samples/symbol),
six numbers: `|C40|` (fourth-order cumulant — the BPSK/QPSK discriminator),
`C42 = mean|x|⁴ / power²`, `sigma_ap` (amplitude variation), `gamma_max` (peak of
the amplitude-ripple spectrum), `freq_std` (phase-increment spread → FSK) and
`spike` (spectral line → residual carrier). Every one is scaled by the class
means, so no feature dominates by units.

**Classifier.** Nearest class mean in the six-dimensional standardised space.

```
d_k = || (f - mu_k) / sigma ||²          label = argmin_k d_k
margin = d_runner-up - d_best            (how decided the answer is)
```

Five classes: BPSK, QPSK, 8PSK, 16QAM, 4FSK. A small margin means two classes are
close, and V07 §18.4 says the caller must then **vote with the track's previous
label**, not invent a new one — that is the difference between a classifier and a
track attribute.

**Why nearest class mean and not a neural net.** Because G8c has to be provable
on an R5F: NCM has 5×6 multiply-adds per burst, a provable bound, and no
allocator. The accuracy it costs is in the table below and is the honest price.

## Two builds, and why both

```bash
make -C step4_r5_amc/c            # build/test_amc_double and build/test_amc_single
make -C step4_r5_amc/c single     # -DAMC_SINGLE_ACC: the R5 configuration
```

The Cortex-R5F in the ZCU208 has **no double-precision FPU**. `AMC_SINGLE_ACC`
replaces the accumulator with `float`; P4 of the bench is the check that this
changes **no label**, which is what makes the single build deployable.

## Files

| file | what it is |
|---|---|
| `c/Makefile` | builds `firmware/amc_r5/*` both ways (no copy of the source) |
| `matlab/step4_classify_burst.m` | one burst → label, margin, features |
| `matlab/step4_build_r5.m` | **G8b**: checks the toolboxes, then calls `build_amc_r5` |
| `testbench/run_testbench.py` | five checks; runs `scripts/amc_port_check.py` rather than re-implementing it |
| `../firmware/amc_r5/` | the firmware: `amc.c`, `amc.h`, `amc_model.h` (generated), `test_amc.c` |
| `../matlab_v7/` | `amc_features.m`, `classify_modulation.m`, `build_amc_r5.m`, `verify_amc_vectors.m` |

## How to run it

```bash
# host, today
python3 step4_r5_amc/testbench/run_testbench.py        # -> RESULT=PASS (5/5)
make amc-port                                          # the same G8a script, by hand
python3 scripts/amc_export.py                          # regenerate the tables

# MATLAB: the model, then the codegen (NOT run here -- no MATLAB on this machine)
matlab -batch "cd step4_r5_amc/matlab; step4_classify_burst(randn(1024,1)+1i*randn(1024,1))"
matlab -batch "cd step4_r5_amc/matlab; step4_build_r5"
matlab -batch "cd matlab_v7; verify_amc_vectors"
```

`step4_build_r5` prints which of MATLAB Coder / Simulink Coder / Embedded Coder
is present before it tries, so a missing licence is one line, not a stack trace.

## The test bench

| check | result on 2026-11-07 |
|---|---|
| T4.1 both builds compile | `test_amc_double`, `test_amc_single` |
| T4.2 label agreement with the model | **100.0 %** double and single (120 bursts) |
| T4.3 double vs single disagreements | **none** |
| T4.4 accuracy against truth | **72.5 %** for firmware, firmware-single and model alike |
| T4.5 the tables in `amc_model.h` | 60 constants, sha256 `62bc0ee7287bfe1f` |

`RESULT=PASS (5/5)`. Feature-level agreement (P2 of the same script): 6.8e−7
double, 1.4e−5 single — i.e. single precision costs nothing that survives
rounding.

## What is not proven here

* **G8b**: nothing in this repository was produced by Embedded Coder. The C was
  written to match the MATLAB function by function, and G8a proves the match;
  the codegen run itself is still a command waiting for your MATLAB.
* **G8c**: no cycle count, no 10 Hz frame budget, no cache measurement.
* 72.5 % accuracy is against a synthetic 5-class set at 0–20 dB; it is not a
  claim about any real waveform (V07 §18.5).
