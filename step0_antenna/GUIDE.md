# step0 — antenna and array (the model, and the input of everything else)

**Gate:** G6 (chamber) is *not* closable without the board; this folder closes the
part that is mathematics. **Runs on:** any machine with MATLAB, or with python3 +
numpy. Nothing here needs Vitis, Vivado, a licence or a board.

**This folder is the input of the whole project.** It writes four scene files, and
step2/step3/step4/step5 are all tested on them:

| file | what is in it |
|---|---|
| `data/scene_single.npz` | one QPSK emitter, 20 dB in band, az +12.50° el −7.25° |
| `data/scene_two.npz` | two emitters 8° apart in azimuth, QPSK and 16QAM |
| `data/scene_decoy.npz` | one emitter and its copy delayed by 40 ns (a repeater) |
| `data/series_mover.npz` | 8 frames of a mover, 1.0°/frame, for step5 |

Each `.npz` holds `x` (4 channels × 4096 complex samples, `fs = 2 GS/s`,
`fc = 4 GHz`) and a sibling `.json` with the truth. The `.mat` written by
`matlab/step0_make_scene.m` has the same meaning, so either language can feed the
rest of the chain.

## Where this step sits

```
step0_antenna        ->  step1_rfadc_mts  ->  step2_pl_ip  ->  step3_r5_doa
(the scenes)             (the capture)        (the kernels)     (the direction)
                                                                     |
                             step6_ps_linux  <-  step5_r5_tracking  <- step4_r5_amc
                             (supervision)       (tracks, decoy)      (modulation)
```

Everything after step1 consumes what step0 produced. That is why step0 has no
"hardware" gate: it is the reference against which the hardware is judged.

## The formulas

Element positions (one plane, `lever = 150 mm` is the offset to the platform
reference and does **not** enter the angle estimate):

```
p0 = (L, -dy/2, -dz/2)     p1 = (L, +dy/2, -dz/2)
p2 = (L, -dy/2, +dz/2)     p3 = (L, +dy/2, +dz/2)      dy = 25 mm, dz = 30 mm
```

Direction from angles, and back:

```
u = ( cos(el)cos(az),  cos(el)sin(az),  sin(el) )
el = asin(u_z)          az = atan2(u_y, u_x)
```

The signal at the four channels and the covariance the PL accumulates:

```
X_n(k) = exp( -j 2*pi*f_k (p_n . u) / c ) * S(k) + N_n(k)
R      = X X^H / K                     (4 x 4, K = 4096 snapshots)
```

One baseline pair `(a,b)` then carries the phase that the whole project reads:

```
angle(R[b,a]) = -2*pi*f*d_ab.u / c        d_ab = p_b - p_a
u_ab          = -angle(R[b,a]) * c / (2*pi*f*|d_ab|)
```

Un-wrapped only while the baseline is shorter than half a wavelength:

```
f_max = c/(2d)     -> 25 mm: 5.996 GHz      30 mm: 4.997 GHz
```

At `fc = 4 GHz` (λ = 74.9 mm) the array is `dy/λ = 0.33`, `dz/λ = 0.40` — inside,
so no ambiguity, and no grating lobe. Above 5 GHz the phase wraps and the
`ambiguity / wrap` block of step3 has real work to do.

The accuracy budget of one baseline (what the 0.5° requirement costs):

```
sigma_phi = 1/sqrt(2 K SNR)        sigma_angle = sigma_phi * lambda/(2*pi*d)
K = 4096, d = 25 mm, fc = 4 GHz  ->  0 dB: 0.302°   20 dB: 0.030°
```

## Files

| file | what it is |
|---|---|
| `py/array_model.py` | geometry, steering vector, the scene generator, `save`/`load`. `python3 step0_antenna/py/array_model.py` prints the array report. |
| `py/make_scenes.py` | writes the four scenes; `--out DIR` to write elsewhere |
| `matlab/step0_antenna_model.m` | the same numbers in MATLAB (positions, `f_max`, beamwidth, `sigma`) |
| `matlab/step0_make_scene.m` | the same scene in MATLAB, saved as `.mat` |
| `testbench/run_testbench.py` | the five checks below, and it writes the scenes |

## How to run it

```bash
# host only, no licence
python3 step0_antenna/testbench/run_testbench.py      # -> RESULT=PASS (7/7)
python3 step0_antenna/py/array_model.py               # the array report
python3 step0_antenna/py/make_scenes.py               # regenerate the scenes

# with MATLAB (this is the command that has NOT been run here)
matlab -batch "cd step0_antenna/matlab; r=step0_antenna_model; disp(r.sigma_deg); step0_make_scene"
```

## The test bench, and what each check proves

| check | proves |
|---|---|
| T0.1 | az/el → u → az/el is exact (worst 7e−15°) |
| T0.2 | a noiseless scene gives a rank-1 `R` whose phase equals `-2πf d·u/c` (3.7e−4 rad) |
| T0.3 | the generator's in-band SNR is the SNR asked for (0.00 dB error at 10 and 20 dB) |
| T0.4 | the six-baseline formula of step3 returns the direction from `R` alone: **0.147°** error at 20 dB |
| T0.5 | 25/30 mm are un-wrapped below 5.0 GHz and below λ/2 at 4 GHz |

Measured on 2026-11-07, `RESULT=PASS (7/7)`.

## What is not proven here

* No antenna, no cable, no chamber: G6 needs the board and a chamber.
* The generator is a **plane-wave, narrowband-per-bin** model. Mutual coupling,
  element patterns, multipath and cable phase drift are not in it; they are the
  calibration job of `step6_ps_linux` (A17) and the risk of G6.

## To make this a measurement instead of a model

1. Put the array in the chamber, one CW tone at `fc`, one mechanical angle.
2. Capture with `step1_rfadc_mts` (4096 snapshots per angle).
3. Run `step0_antenna/testbench/compare_with_capture.py` (to be written when a
   capture exists) — it must print the same `T0.4` number from real data.
4. Only then can the diagram's G6 badge turn green.
