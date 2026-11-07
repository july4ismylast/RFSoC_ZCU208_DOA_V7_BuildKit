# step3 — the direction, on the R5F: WPI → ML → Gauss–Newton

**Gate:** G7a (**closed** — host, with numbers). G7b (on the board) is open.
**Runs on:** the C here *is* the R5F code (plain C99, libm only, no allocation);
the numpy file is its reference. No MATLAB, no Vitis, no board needed to run the
test bench.

This is the folder that answers "what is ML + Gauss–Newton, and why two of them".

## Where it sits

```
step1 capture ──► [ WPI seed ] ──► [ ML grid, 36 points ] ──► [ Gauss-Newton, 2 steps ] ──► az, el
                        │                     │                        │
                  6 baselines           Bartlett cost P(u)        Newton on J(u)
                        └──────────────────── one covariance R, three costs ───────────────┘
```

Input: the 4×4 covariance `R` (from `doa_covariance_4ch_v4` or from a scene).
Output: `az, el` in degrees, and the intermediate stages (the test bench keeps
all three so you can see what each one bought).

## 1. WPI — the seed

Six baselines, one phase each, weighted least squares:

```
phi_ab = angle(R[b,a])                       d_ab = p_b - p_a
gamma  = |R[b,a]|^2 / (R[a,a] R[b,b])        coherence, 0..0.999
w      = gamma/(1-gamma),  clipped [0.05, 100]
u_yz   = -(B' W B)^-1 B' W phi / k           k = 2*pi*f/c
```

Exact for one emitter, six `atan2` and a 2×2 solve — the only stage cheap enough
to be the first guess. Its accuracy is already the CRLB at high SNR, so it is a
good seed and a poor finisher (it has no way to use the *shape* of the peak).

## 2. ML — what "maximum likelihood" actually maximises here

For one emitter the covariance is `R = σ_s² a(u)a(u)' + σ_n² I`. The
log-likelihood of that model, maximised over the unknown power and noise, is
monotone in the generalised likelihood ratio, and the ratio collapses to the
Bartlett form:

```
P(u) = a(u)' R a(u) ,        a(u)_n = exp(-j k p_n . u)
û_ML = argmax P(u)
```

That is the whole content of "ML" in this project: **the direction whose steering
vector explains the most energy in R**, with the unknown amplitude and noise
profiled out. There is no closed form for this array, and a full search at
0.005° over ±55° × ±45° is 4·10⁸ evaluations, which no R5F will do at 10 Hz.

So the ML search is *local*: four stages of a 3×3 grid, steps 0.5 → 0.1 → 0.02 →
0.005°, i.e. **36 evaluations**, starting from the WPI seed. If the seed is in
the main lobe, 36 points land inside 0.005° of the peak.

## 3. Gauss–Newton — the finisher

Newton needs the gradient and the Hessian of `P`. Written against the signal
subspace `v` (the dominant eigenvector of `R`, found by **four power iterations**,
no eigen-decomposition):

```
J(theta) = || (I - v v') a(theta) ||^2          same minimiser as P
d(theta) = -j k (p . du/dtheta) .* a
g        = 2 Re( d' (I - v v') a )              2x1
H        = 2 Re( d' (I - v v') d ) + 1e-7 I     2x2
delta    = H^-1 g ,  clipped to GNMaxStep_deg = 0.05 deg
theta   -= delta                                  twice (GNIterations = 2)
```

Why two iterations: the cost is almost quadratic near the peak. The first step
removes the residual of the 0.005° grid; the second confirms the gradient did not
come back. Why the 0.05° cap: a bad seed (two emitters, a null) could otherwise
send the step off the main lobe, and a tracker prefers a wrong-but-near answer to
a divergent one.

`H^-1 g` on a 2×2 is a division — that is why this runs on an R5F with no DSP
library and no `double` FPU (build with the single-precision path if you need it;
`step4_r5_amc` shows how that is done for the classifier).

## 4. The tracker that consumes it

`ekf_unit_vector` is the 6-state unit-vector EKF (state `(u, du)`, one update per
frame, renormalisation after every prediction). It is what turns per-frame
`(az, el)` into the `detections` that step5 associates.

## Files

| file | what it is |
|---|---|
| `c/doa_core.h` | the interface: `doa_wpi`, `doa_estimate`, `doa_bartlett` |
| `c/doa_core.c` | **the R5F implementation** — 4×4 complex, 2×2 solves, ~230 lines |
| `c/Makefile` | builds `build/step3/libdoa_core.so`; `make check` compiles with `-Werror` |
| `py/estimator.py` | the same three stages in numpy, plus the EKF; `python3 …/estimator.py` prints an SNR table |
| `matlab/step3_doa_from_capture.m` | the MATLAB reference on a `.mat` capture, and the exact field set the estimator needs |
| `testbench/run_testbench.py` | six checks, below |

## How to run it

```bash
python3 step3_r5_doa/testbench/run_testbench.py     # -> RESULT=PASS (6/6), needs gcc
make -C step3_r5_doa/c check                        # -Werror compile, the R5 way
python3 step3_r5_doa/py/estimator.py                # a quick SNR table
matlab -batch "cd step3_r5_doa/matlab; step3_doa_from_capture"   # NOT run here
```

For the board, the same `doa_core.c` compiles with
`armr5-none-eabi-gcc -mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16 -O2`;
nothing in it allocates, so it drops into the RPMsg loop with a static buffer.

## The test bench, and what each check proves

| check | result on 2026-11-07 |
|---|---|
| T3.1 WPI recovers one emitter | error **0.320°** at 20 dB in band (+12.548 / −6.933 vs +12.50 / −7.25) |
| T3.2 ML+GN is not worse than the seed | **0.320°**, 36 Bartlett points, 2 Newton steps |
| T3.3 **C == numpy** | 24 random cases, worst difference **1.3e−14°** |
| T3.4 error vs SNR | 0 dB: 0.283° mean · 10 dB: 0.090° · 20 dB: **0.048°** |
| T3.5 EKF on step0's mover | jitter **0.337 → 0.218**, error 0.233 → 0.228° |
| T3.6 two emitters fail, with a number | one direction 3.71° from the nearest truth (four elements cannot hold two directions) |

`RESULT=PASS (6/6)`.

Two things to notice in that table. First, T3.3 is the important one: the C that
would run on the R5F is the *same algorithm* as the reference to 14 digits, so
step3's accuracy numbers are the firmware's numbers. Second, T3.4's 0 dB row
(0.283° mean) is where the 0.5° budget starts to bite — that is the SNR floor the
radar link has to deliver.

## What is not proven here

* No R5 silicon: no cycle count, no 10 Hz frame rate, no cache behaviour (G7b).
* The covariance is modelled as complex Gaussian; the real one carries
  calibration error, mutual coupling and quantization (step1/step6 own that).
* T3.6 is a *limit*, not a bug: two coincident emitters need the AMC ladder
  (step4/step5), not a better direction estimator.
