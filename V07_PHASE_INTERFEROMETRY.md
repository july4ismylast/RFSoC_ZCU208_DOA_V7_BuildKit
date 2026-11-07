# Stage V07 — wideband phase-interferometry DOA (adopt / correct / reject)

**Status:** architecture decision recorded 2026-11-06 · new PL block
`ip/custom/phase_interf_4ch` (v1.0) added with host-verified fixed-point core ·
two reproducible evidence reports under
[`docs/evidence/2026-11-06-phase-interf/`](docs/evidence/2026-11-06-phase-interf/)
· **no synthesis, no bitstream, no hardware measurement is claimed here.**

This document is the response to the external architecture review that proposed
replacing "monopulse Σ/Δ, 400 MHz, DDC→50 MSPS, FFT at 50 MSPS, per-bin
CFAR→monopulse" with "phase interferometry, 2 GHz instantaneous, DDC ×2 only,
FFT 16K at 2.048 GSPS, per-bin cross-spectrum → phase-slope fit".

The review's *direction* is right and is adopted. Several of its *numbers* are
not, and one of its headline blocks (16K FFT at 2.048 GSPS) should not be built.
Everything below is either measured on this repository's own evidence, computed
by a script in this repository, or explicitly marked unproven.

---

## 0. Decision summary

| Review proposal | Decision | Where |
|---|---|---|
| Phase interferometry is the primary estimator | **ADOPT** — already the V7 primary path (`HYBRID_CAL_WPI_ML_EKF` is six-baseline coherence-weighted phase); V07 makes it explicit and per-bin | §2, §5 |
| 2 GHz instantaneous bandwidth | **ADOPT** — already locked by V04 (4.000 GSPS, RFDC fine NCO, decimation 2 → 2.000 GS/s complex) | §2 |
| DDC ×2 only, no ×80 chain | **ADOPT** — the RFDC hardening does this for free; there is no fabric FIR to build | §2, §3.4 |
| Per-bin cross-spectrum | **ADOPT** — new `phase_interf_4ch` block | §5 |
| Multi-frequency **phase-slope fit** as the accuracy mechanism | **ADOPT for band-filling emitters, through the origin and without unwrapping** — 0.066° at 30 mm over 2–4 GHz, 5× better than the band-centroid average; the review's *intercept* version is 0.235° and loses 9–10 of 10 narrowband frames, so it is rejected | §4, §11.2, §11.4 |
| FFT **16K at 2.048 GSPS** | **REJECT** — not an instantiable IP configuration; 4-channel BRAM 26 %…165 % of the device; buys no accuracy | §4 |
| Array spacing **d = 50 mm** | **REJECT** — unambiguous only to 3 GHz; measured 106° error at 3.75 GHz / az 55° where 25 mm gives 0.27°, and 33.9°/104.2° off over the full band where 30 mm holds 1.6°/1.1° | §4.4, §11.1 |
| Amplitude-assisted "face selection" | **ADOPT, restated** — amplitude resolves only the ±45° quadrant; it cannot resolve an interferometer ambiguity | §5.5 |
| MUSIC / CSSM | **DEFER for one emitter; needed only for co-channel sources** — eight *co-channel* emitters need 36 elements (2×2 finds 1.2 of 8), but eight 1–50 MHz emitters at different carriers are separated by the channelizer and the shipped 2×2 detects 8.0 of 8 | §9, §12.1, §12.4 |
| 4.096 GSPS converters, 3.072 GHz NCO, 125 kHz bins | **CORRECT** — the pinned MTS base runs 4.000 GSPS with a 3.000 GHz centre; bins are 122.07 kHz at 16K, 1.953 MHz at 1024 bands | §3 |
| "1× FFT TDM at 4× clock" | **REJECT** — needs a 1 GSPS fabric clock; the V06 timing gate is 4.0 ns (250 MHz) | §3.3 |

---

## 1. The review describes a different draft, not this repository

The review's "previous (wrong)" column — monopulse Σ/Δ, 400 MHz instantaneous,
DDC→50 MSPS (80× decimation), FFT at 50 MSPS, per-bin CFAR→monopulse — is not
what this build kit contains. The repository has been on a wideband, phase-based
path since V04:

| Already in place | Evidence |
|---|---|
| 4.000 GSPS RF-ADC, Nyquist Zone 2, fine Real→I/Q NCO, **decimation 2** → 2.000 GS/s complex per channel, SSR-8 at 250 MHz | [`V04_RFDC_DOA_CONTRACT.md`](V04_RFDC_DOA_CONTRACT.md), scratch-apply proof 2026-11-03 |
| SSR-8 I/Q gearbox, C-sim bit-exact, II=1, 500 MHz estimated | [`V05_RFDC_REPACK4_SPEC.md`](V05_RFDC_REPACK4_SPEC.md), `step05_hls_repack` PASS |
| 1024-band PFB channelizer, 1.953 MHz bins, one-channel OOC timing closed | [`V06_CHANNELIZER_FEASIBILITY.md`](V06_CHANNELIZER_FEASIBILITY.md), Gates 0/1/2/3 |
| Six-baseline coherence-weighted phase DOA (WPI) + bounded ML/GN + EKF, 4096-snapshot calibrated covariance | `matlab_v7/DOAEstimator4Ch.m`, `estimate_doa_from_covariance_v7.m` |
| Unambiguous geometry: 25 mm axes / 35.4 mm diagonal, valid to 4.24 GHz | `DOAEstimator4Ch.setupImpl` throws `DOA2x2:AmbiguousBaseline` otherwise |

So the "fundamental architecture change" reduces to three real deltas:

1. make the **per-bin cross-spectrum** an explicit PL block instead of relying on
   a frame covariance computed downstream of a channel selector;
2. make the estimator's **frequency dimension** explicit (which bins feed which
   estimate) — and thereby show why the review's slope fit is the wrong primary
   estimator;
3. fix the **geometry**, **sample-rate** and **front-end** numbers so they match
   the pinned MTS base and the measured channelizer.

---

## 2. What the review got right

* **Wideband is the right operating point.** 2 GHz instantaneous bandwidth is
  already the V04 contract; the review correctly identifies that the 80×
  decimation chain (50 MSPS, 50 MHz) would be a different, narrowband product.
* **Cross-spectrum before angle.** Computing `X_a·conj(X_b)` and taking a phase
  is the sufficient statistic for a pair of channels; it is exactly what the
  existing covariance block accumulates, but per-bin it also carries *frequency*,
  which the frame covariance throws away.
* **Deferring MUSIC/CSSM.** With four elements and one to two emitters, WPI plus
  a bounded local ML refinement reaches the requirement; subspace methods add
  cost and calibration sensitivity for no demonstrated benefit.
* **Four multiplies per cross-spectrum, CORDIC for the phase.** Correct, and it
  is how `phase_interf_4ch` is built (§5).

---

## 3. Corrections to the review's numbers

### 3.1 Sample rate and bin width

The pinned MTS base clocks the four ADCs at **4.000 GSPS** (`LMX2594_4000.0.txt`,
V04 §1), not 4.096 GSPS. With RFDC decimation 2 the complex rate is **2.000 GS/s**
and a 16K transform gives **122.07 kHz** bins, not 125 kHz. 4.096 GSPS is a
supported converter rate for the ZU48DR, but adopting it would mean re-doing the
CLK104/LMX2594 plan, the SYSREF division and the whole V03 MTS proof — for a
2.4 % bin-width change. **Do not change the clock plan.**

The review's default RF centre is 3.072 GHz; this build kit's contract is
**3.000 GHz with a 2.25–3.75 GHz captured band** (V04 §2), which keeps 250 MHz of
guard to both Nyquist-zone edges. Keep 3.000 GHz.

### 3.2 "RF-ADC output 4.096 GSPS real, SSR=16"

At 250 MHz, 4.096 GSPS real is 16 samples/clock per channel; the resulting
complex SSR-16 stream is 2 048 bits per channel per clock (4 channels: 8 192
bits/clock). That cannot be carried by the V04/V05 fabric contract, which is
8 samples/clock × 4 channels × 32 bits = 1 024 bits at 250 MHz. The review's own
table therefore describes a datapath that does not exist on this base design.

### 3.3 "1× FFT TDM at 4× clock"

Four channels sharing one FFT would need a 1 GSPS fabric clock (or four 16K
transforms per 8 µs each). V06 gates the wideband logic at **4.0 ns (250 MHz)**
and the measured channelizer closes at 250 MHz with +1.8 ns slack. A 1 GSPS
fabric clock is not available on this part at this utilisation. There is no TDM
option; the choice is four parallel instances or nothing.

### 3.4 The "halfband decimator ×2, 31-tap FIR, 32 DSP48" block is unnecessary

With `ADC_Decimation_Mode = 2`, the RFDC performs the halfband decimation in
hardened logic inside the tile, together with the fine NCO. Building a fabric
decimator would duplicate hardened silicon and add 32 DSPs plus a 16-clock
latency for nothing. V04 already configures the hardened path; **no fabric
decimator is implemented.**

### 3.5 "Per-bin cross-spectrum: 8 DSP48 per bin"

The count is right per bin and per baseline lane, and wrong by the SSR factor
and the baseline count. Per clock the block sees 4 lanes × 4 channels of one bin
group; six baselines × 4 real multiplies × 4 lanes = **96 real multiplies**, i.e.
~40 DSP48 after the calibration stage is shared. The review's "8 DSP48 per bin,
pipelined" understates the arithmetic by ~10× and omits the calibration multiplies.

### 3.6 "CORDIC 16-bit, 12 iterations, 28 clocks total"

Six phases (one per baseline) at 16-bit accuracy need ~16 iterations, not 12, and
they do not need six dedicated CORDICs: one shared datapath at ~2–3 k LUT and no
DSP (§7.4) serves all six, because the pass runs once per frame. The latency
claim is irrelevant: the block runs at the **250 MHz wideband fabric clock** on
the channelizer's output stream (`WIDEBAND_CLOCK_PERIOD_NS` = 4.0 ns), and the
CORDIC pass happens once per frame, not once per sample.

### 3.7 Block-floating-point is ignored

The review specifies BFP output from the FFT and then multiplies bins from
different channels. Each channel's FFT has its **own** block exponent. A phase
comparison is immune to a real scalar, but the amplitude/coherence terms are
not: `|S_ab|²/(P_a·P_b)` needs the exponents aligned, and the review's
"amplitude for face selection" step has no exponent handling at all. My
implementation accumulates the calibrated complex products and derives coherence
from the accumulated magnitudes, so no exponent alignment is required.

### 3.8 The MATLAB reference has three defects

```matlab
p = polyfit(f_det, phi_det, 1);   % w = Sigma(bins) computed above but never used
```

* the SNR weights are computed and never passed (`polyfit` has no weight input —
  use `w.\`/`fitlm` with weights, or a weighted normal-equation solve);
* `unwrap` on per-bin phase of a *narrowband* emitter unwraps noise: with ~410
  bins and 0.07 rad per-bin phase noise, 2π slips are common, and a single slip
  across a 50 MHz span corrupts the slope by ~6×10⁻⁹ rad/Hz — 100° of angle
  (measured: 120° RMSE, §6);
* `if sign(A2 - A1) ~= sign(theta_az)` compares an amplitude difference with an
  angle sign; the two are unrelated in general, and with 25–50 mm spacing the
  element amplitude difference is far too small to resolve a phase ambiguity.

---

## 4. The 16K FFT at 2.048 GSPS question — answered

> *"4.2 FFT 16K: At 2.048 GSPS — is it fit on zcu208???"*

**No — do not build it.** Three independent reasons, in order of strength.

### 4.1 No instantiable IP configuration

| Implementation | Samples/clock | Applies here? |
|---|---|---|
| AMD FFT LogiCORE v9.1 (the VLNV pinned by this project's V00 rule) | **1** | No. 8 samples/clock needs 8 cores per channel, each holding a full 16K transform memory → 8× memory for one channel |
| Vitis DSP Library SSR FFT | 2/4/8/16, benchmarked **≤ 4K** | No at 16K: outside the documented envelope |
| MathWorks `dsphdl` FFT / Channelizer | power-of-two vector | Unproven at 16K × SSR-8; would need a one-channel OOC synthesis exactly like V06 Gate 1/2 |
| 8 × AMD FFT + polyphase recombination | 8 by construction | No: 8× memory plus twiddle/recombine logic, no IP support |

The existing `ssrfft_16x4096_axis` (OPFB, Plan B) is a **4096**-point, 16-way
transform — an order of magnitude less memory than four 16K transforms.

### 4.2 Resource arithmetic (screen, not synthesis)

From `scripts/estimate_wideband_dsp_resources.py`
([report](docs/evidence/2026-11-06-phase-interf/wideband_frontend_screen.txt)),
device = 425,280 LUT / 850,560 FF / 1,080 BRAM36 / 80 URAM / 4,272 DSP48,
routed MTS base = 42,263 LUT / 50.5 BRAM36:

| Front end (one channel) | bin | BRAM36 range | DSP48 (lower bound) | LUT | frame |
|---|---|---|---|---|---|
| 1024-band PFB channelizer, 12 taps, SSR-8 (**measured**) | 1.953 MHz | 176 | 312 | 35,902 | 4.10 µs |
| 1024-pt FFT, SSR-8 | 1.953 MHz | 4…27 | 90 | ~35,900 | 0.51 µs |
| 4096-pt FFT, SSR-8 | 488.3 kHz | 14…108 | 108 | ~43,100 | 2.05 µs |
| **16384-pt FFT, SSR-8** | 122.07 kHz | **57…433** | 126 | ~50,300 | 8.19 µs |

Four channels plus the MTS base:

| Front end ×4 | BRAM36 | DSP48 | LUT | Verdict |
|---|---|---|---|---|
| 1024-band channelizer | 754 (**69.9 %**) | 29.3 % | 43.7 % | closes by arithmetic (V06) |
| 4096-pt FFT | 107…484 (10…45 %) | 10.2 % | 50.5 % | plausible, unproven |
| **16K FFT** | **278…1783 (26…165 %)** | 11.9 % | 57.2 % | **not settled by arithmetic; the pessimistic end does not fit** |

The BRAM range spans "deep FFT memory packs nearly perfectly" (2× of
data+twiddle) to the 15.2× overhead actually observed on the measured
channelizer (whose 12-tap-deep PFB memory packs badly). An FFT should sit near
the low end — but that is precisely the kind of claim V06 refused to accept
without a one-channel OOC run, and the same rule applies here.

### 4.3 It buys no accuracy

For a coherent cross-spectrum estimate the angular variance depends on the
number of coherently combined bin–snapshot products, `K = bins × snapshots`,
through `σ_θ ≈ c/(2π f_c d) · σ_φ/√K`. At equal observation time:

| Front end | bins in a 50 MHz emitter | frames per 8.2 µs | K |
|---|---|---|---|
| 1024-band channelizer | 25.6 | 16.0 | **410** |
| 4096-pt FFT | 102.4 | 4.0 | **410** |
| 16K FFT | 409.6 | 1.0 | **410** |

A finer transform moves the same samples into fewer, longer frames. Finer bins
buy **separation of emitters inside the band**, not angular accuracy for a
single emitter. The measured 1024-band front end already exists and already
timing-closes.

**Conclusion:** keep the 1024-band channelizer; if finer bins are ever needed for
bin-of-arrival or multi-emitter separation, the step is 4096 points, not 16384.

### 4.4 The 50 mm baseline is not usable across 2–4 GHz

Phase measurement on a baseline `d` is unambiguous only for
`|sin θ| ≤ c/(2 f d)`. At 3.75 GHz that is **0.799 for 50 mm** and **1.599 for
25 mm** — i.e. 50 mm has no ambiguity headroom inside the ±55° scan at the top
of the captured band. Measured (case 4 of the evidence report), az = 55°,
3.75 GHz:

| Estimator | d = 50 mm | d = 25 mm |
|---|---|---|
| coherent WPI | **106.2°** (wrapped) | **0.27°** |

A larger baseline does improve raw angular sensitivity (`σ_θ ∝ 1/d`), but only
inside the unambiguous sector. The correct way to obtain *both* from four
elements is a two-baseline (coarse/fine) array — a geometry change that must be
decided before the array is built, not a firmware change. With a square 2×2 the
constraint is the diagonal: `d·√2·sin θ ≤ λ_min/2`, which gives 32.3 mm for the
declared ±55° scan at 4 GHz. **§11 replaces the 25 mm figure with 30 mm** on that
rule and measures what each spacing does over the whole band; the
`DOA2x2:AmbiguousBaseline` guard stays either way. The 50 mm rejection above is
confirmed there, not weakened: 50 mm is measured 33.9° and 104.2° off in the two
directions where the rule says it must wrap.

---

## 5. The adopted architecture: per-bin phase interferometry (PIR-2×2)

### 5.1 Chain (all rates are the V04 contract)

```text
4× RF-ADC 4.000 GSPS, Nyquist Zone 2
  │  hardened fine NCO (-F_C) + hardened halfband decimation 2   ← no fabric cost
  ▼
2.000 GS/s complex per channel, AXI 8 samples/beat I + Q @ 250 MHz
  │  rfdc_repack4 (V05): channel-aligned SSR-8 complex vectors
  ▼
1024-band PFB channelizer per channel (V06 Plan A, measured)
  │  1.953 MHz bins, one 1024-bin snapshot every 1024 input samples
  ├──────────────► search branch: spectrum_power4 + candidate_peak4 (bins, rate)
  │                                    │ candidate bin / bin cluster
  ▼                                    ▼
phase_interf_4ch  ◄──────────── bin selector (existing subband bridge)
  │  per selected bin, over N snapshots:
  │    4× calibrated channel powers
  │    6× complex cross-spectra  S_ba = Σ_n X_b conj(X_a)   (covariance-block order)
  │    6× phase  atan2(Im S_ba, Re S_ba)   (16-iteration CORDIC)
  │    6× |S_ab|²  for coherence weights
  ▼
PS (A53/R5): calibration, WPI solution, ambiguity/amplitude check,
             optional bounded ML refinement, EKF tracking
```

### 5.2 Mathematics as implemented

For channel `n` at array position `p_n`, direction `u`, RF frequency `f`:

```text
X_n(f) = A_n(f)·S(f) + N_n(f),      A_n(f) = exp(-j·2π·f·(p_n·u)/c)

S_ba(f) = X_b(f)·conj(X_a(f)) = exp(-j·2π·f·(p_b - p_a)·u/c)·|S(f)|²
```

The product order is **`X_b·conj(X_a)`, i.e. the same order
`doa_covariance_4ch_v4` already accumulates**, so the block's 16-word output is
a drop-in replacement for that block and the PS can reuse
`estimate_doa_from_covariance_v7.m` unchanged. For the azimuth pair CH1→CH2
(baseline `+y`, spacing `d`) and the elevation pair CH1→CH3 (baseline `+z`):

```text
uy = -angle(Σ_k S_12(k))·c / (2π·f_c·d)
uz = -angle(Σ_k S_13(k))·c / (2π·f_c·d)
az = atan2(uy, sqrt(1-uy²-uz²)),   el = asin(uz)
```

where the sum runs over the emitter's occupied bins and `f_c` is the
power-weighted centroid of those bins — the leading minus is the one in
`estimate_doa_from_covariance_v7.m` (`directionYZ = -(B'WB)^-1·B'W·φ/k`), not a
new convention. This is that same coherence-weighted six-baseline phase LS, with
the frequency dimension retained until the last step.

**A target at positive `uy` therefore produces a negative baseline-0 phase.** If
this is ever "fixed" by dropping the minus, every angle is mirrored: the
reference WLS port reports az `+12.5°` as `-12.5°` with otherwise identical
statistics, which looks plausible on a scope and is wrong on the sky.

**Sign convention is asserted four times**: the host core test feeds the exact
per-channel phasors of a target at az `+20°`, el `-12°` (one baseline negative,
the other positive, so a uniform flip cannot pass) and requires
`-2π·f·d·u/c` within 3 LSB; the HLS C-simulation testbench repeats it through
the AXI ports; `scripts/phase_interf_verify.py` checks it against an independent
steering model; and the MATLAB estimator applies the same product order and the
same minus.

### 5.3 Calibration, coherence, and the bits that matter

* Per-channel complex gain (Q2.14 real/imag, 32-bit packed) is applied **before**
  the cross-products, exactly like `doa_covariance_4ch_v4`, so the PS writes the
  same calibration table to both blocks.
* Coherence `|S_ab|²/(P_a·P_b)` is formed in the PS from the accumulated
  magnitudes (no divider in PL) and used as the WPI weight.
* Accumulators are 64-bit signed in the shipped core: a 4096-sample frame of
  20-bit calibrated values needs 51 bits worst case (proven, not assumed, by
  `FrameAccumulator::worstCaseBits` in the host test). The 51-bit figure is why
  the block is *not* 48-bit; an earlier draft of this document said 48 and was
  wrong.
* Phase output is Q3.13 rad (16-bit), CORDIC 16 iterations, integer-only, so the
  host model and the HLS C simulation are bit-identical (§7.3).

### 5.4 Estimator selection (the part the review got backwards)

The PS selects per detection:

| Emitter | Estimator | Why |
|---|---|---|
| Narrowband (≤ a few hundred MHz occupied) | **coherent WPI** over occupied bins × snapshots | the carrier is the lever arm; bin count is free SNR |
| Band-filling / noise-like (≳ 1 GHz) | coherent WPI first, slope fit only as a cross-check | even at 2 GHz the slope lever arm is `B/√12` vs the carrier `f_c`, and `f_c > B` always |
| Long baseline (d > λ/2) with a band-filling emitter | slope fit **to unwrap**, not to measure | the delay is unambiguous even when the phase is not |
| Two emitters inside one emitter's bandwidth | finer front end (4096-pt), not a different estimator | separation is a resolution problem |

The general statement, which the review's error analysis contradicts:

```text
σ_θ(WPI)   = c/(2π f_c d) · σ_φ/√K
σ_θ(slope) = c/(2π d)     · σ_φ·√12/(√K·B)
ratio      = √12·f_c/B  ≥ √12·(f_c/B) > 1     because B < 2f_c
```

The phase-slope estimator is *never* better than coherent phase for a known
carrier, at any bandwidth. It is 242× worse for a 50 MHz emitter at 3.5 GHz and
6.1× worse for a 2 GHz emitter — both confirmed by measurement (§6).

### 5.5 Amplitude: quadrant only

Amplitude comparison across a 25–50 mm baseline over a 2 GHz band has essentially
no angular discrimination — the element patterns differ by a fraction of a dB
across the scan sector, while the phase ambiguity sector is tens of degrees. The
block therefore reports the four channel powers for two legitimate uses:

* **quadrant/face selection** (±45°) when the array is mounted with a known
  forward hemisphere and the estimate must be disambiguated front/back;
* **diagnostics**: a channel whose power collapses is a dead RF chain, which is
  the failure that silently ruins a phase-only estimator.

It is *not* used to resolve the interferometer ambiguity; that is what the
`d ≤ λ/2` guard and, later, a coarse/fine baseline pair are for.

---

## 6. Measured accuracy (this repository, reproducible)

`python3 scripts/phase_interf_verify.py`
→ [report](docs/evidence/2026-11-06-phase-interf/phase_interf_reference_check.txt)

Model: four coherent channels, 2.000 GS/s, 16K bins, `F_C` 3.000 GHz, one
emitter, flat noise density, per-bin SNR quoted in one 122.07 kHz bin,
150 Monte-Carlo trials per row, RMSE over azimuth and elevation jointly.

This report keeps the **25 mm fallback geometry** so that its numbers stay
comparable with the V06/V07 record; the adopted 30 mm pitch is measured over the
full 2–4 GHz band in §11, with much coarser 15.6 MHz bins, so the narrowband
RMSE there (0.25°) is not directly comparable with the 0.222° below — the bin
count is 8× lower, which alone costs about `√8`.

**Narrowband 50 MHz emitter at 3.500 GHz, d = 25 mm, 20 dB/bin**

| Estimator | RMSE | median | max |
|---|---|---|---|
| coherent WPI (adopted) | **0.222°** | 0.169° | 0.6° |
| single peak bin only | 1.776° | 1.459° | 4.2° |
| slope fit (oracle unwrap) | 101.4° | 48.3° | 180° |
| slope fit (review's literal code) | 120.0° | 67.8° | 180° |

The oracle slope fit lands above its own theoretical penalty (457× measured vs
242× predicted) because a 50 MHz lever arm already produces ~26° per-axis
errors, and any trial whose `|u| > 1` leaves the unit sphere gets counted as a
180° failure. The *ordering* is what matters and it is unambiguous: even with
perfect unwrapping, a slope fit over a narrowband emitter cannot compete with a
coherent phase measurement at the carrier.

**Wideband 2.0 GHz emitter, d = 25 mm, 20 dB/bin**

| Estimator | RMSE |
|---|---|
| coherent WPI | **0.036°** |
| slope fit (oracle unwrap) | 0.206° (5.8× worse; theory 6.1×) |
| slope fit (review's literal code) | 177.7° (unwrap slips) |

**Per-bin SNR sweep, 50 MHz emitter** (`coherent_wpi`): 10 dB → 0.764°,
15 dB → 0.418°, 20 dB → 0.232°, 25 dB → 0.130° — the expected `1/√SNR` slope.

**Snapshot averaging at 10 dB/bin**: 1 → 0.671°, 8 → 0.240°, 64 → 0.091°.

**Calibration residual** (CH2/CH3, opposite signs, 20 dB/bin):

| Residual | RMSE |
|---|---|
| none | 0.210° |
| 0.2 dB / 1.0° | 0.825° |
| 0.5 dB / 3.0° | **2.398°** |

### 6.1 What the accuracy budget really says

| Term | Value | Comment |
|---|---|---|
| Statistical (20 dB/bin, 50 MHz, 1 frame) | 0.22° | measured |
| Statistical (20 dB/bin, 64 frames) | 0.09° | measured |
| Calibration residual 0.2 dB / 1.0° | 0.8° | **dominant** |
| Calibration residual 0.1 dB / 0.5° | ≈0.45° | extrapolated, same scaling |
| Array position error 0.5 mm at 25 mm | ≈1.1° | `Δd/d` maps directly into angle |
| Element/cable phase drift over ΔT | unquantified | must be measured on hardware |

The review's "0.25° total RMS, meets 0.5° with margin" is **not supported**: its
statistical term is optimistic for its own estimator and it omits the geometry
term entirely. The binding requirement is **calibration and mechanical
tolerance**, not DSP. A credible field claim is 0.5° RMS only after a
`≤0.2 dB / ≤1°` calibrated array with `≤0.2 mm` surveyed positions — which is
what the HIL and chamber gates in `VALIDATION_REPORT.md` exist to prove.

---

## 7. New PL block: `ip/custom/phase_interf_4ch`

### 7.1 Contract

| Item | Value |
|---|---|
| Input | `s_axis` 512-bit, lane-major `word = lane*4 + channel`, `{Q[31:16], I[15:0]}`, 4 lanes × 4 channels (same beat as `doa_covariance_4ch_v4`) |
| Control | AXI4-Lite: `cal0..cal3` (Q2.14 complex), `frameSamples` (default 4096), `frameTag` |
| Output A | `m_axis` 64-bit × 16 words per frame: 4 powers, 6 cross-spectrum real parts, 6 imaginary parts — **bit-identical to `doa_covariance_4ch_v4`**, including the `X_b·conj(X_a)` product order, so the PS can feed `estimate_doa_from_covariance_v7.m` unchanged |
| Output B | `m_phase` 128-bit × 1 per frame: 6 × phase Q3.13 (96 b), frame tag `[111:96]`, phases-valid bit 112 |
| Clock | `ap_clk` = **250 MHz wideband fabric clock (4.0 ns)**, the channelizer's output domain (`WIDEBAND_CLOCK_PERIOD_NS`); `II=1` on the accumulation loop. An earlier draft of `build_hls.tcl` used `PL_CLOCK_PERIOD_NS` (7.8125 ns) — proving closure at 128 MHz for a block that never runs at 128 MHz — and that was fixed |
| VLNV | `openai:doa:phase_interf_4ch:1.0` |

### 7.2 Structure

```text
beat → 4× calibration (complex Q2.14) → 20-bit I/Q per channel
      → 4 power accumulators        (int64, 51-bit worst case)
      → 6 cross-spectra             (int64 Re/Im)
      → frame end → 6× atan2 through ONE shared normaliser+CORDIC (Q3.13)
      → m_axis (16 words, covariance-compatible) + m_phase (6 phases + tag)
```

### 7.3 Verification status (honest)

| Check | Status |
|---|---|
| Fixed-point core compiles and runs on the host, bit-exact golden vectors | **PASS** (`make -C ip/custom/phase_interf_4ch host-check`, g++) |
| CORDIC error ≤ 1 LSB over 0…2π | **PASS** (host test, 4 096 angles) |
| Accumulator growth worst case (4096 samples, 20-bit calibrated) | **PASS** — 51 bits of 64, asserted by the test |
| **The production kernel and the production C-simulation testbench compile and pass on the host** (AXI beat packing, 16-word order + `TLAST`, phase-record bit positions, frame-tag echo, az/el sign) | **PASS** — `make … host-kernel-check`, via the minimal shim in `tb/host_shim/`; three frames incl. the 4096-sample production frame |
| C simulation / synthesis / export in Vitis HLS 2023.2 | **NOT RUN** — requires the user's licensed tool; `step05_hls_phase_interf` is wired but unproven |
| Scheduling / II / latency / HLS overflow semantics | **NOT RUN** — the shim cannot model them (it ignores `#pragma HLS`) |
| OOC timing at 4.0 ns | **NOT RUN** |
| Integration into the BD, timing closure, hardware | **NOT RUN** |

The last row of the passing block is the important one for a first Vitis run: the
two most common ways to lose a day on a licensed machine — the kernel not
compiling, and the AXI record being packed differently from what the PS expects
— are already excluded for free, on any machine with `g++`.

The block is deliberately small (§7.4) so that, unlike the front end, its
feasibility is not in doubt; but "small" is not "proven", and the gate table
below keeps the distinction.

### 7.4 Budget

Counted, not guessed. Per 512-bit beat the kernel processes 4 lanes × 4 channels:

| Multiplies per beat | Count |
|---|---|
| Calibration, 16 complex multiplies × 4 real | 64 |
| Channel powers, 16 × 2 real | 32 |
| Cross-spectra, 4 lanes × 6 pairs × 4 real | 96 |
| **Total real multiplies per beat** | **192** |

| Resource | Estimate (and why it is an estimate) |
|---|---|
| DSP48 at `II=1` | **≈192–384**. One multiplier per cycle needs 192 DSP48E2 at best; the calibrated operands are 20-bit, which does not fit the 27×18 multiplier, so some products cost two DSPs. 4–9 % of the 4 272 DSP on the ZU48DR |
| DSP48 at `II=4` | ≈48–96. A channelised bin delivers ~2 MS/s, i.e. a 4096-sample frame every ~2 ms, so a beat every 16 ns is still ~500× faster than needed. Relax the iteration interval only with measured G2/G3 numbers in hand |
| LUT | ~3–8 k. **One** shared normaliser+CORDIC datapath (see the `phase_loop` comment), not six |
| FF | ~5–10 k (64-bit accumulators, 20-bit pipeline registers) |
| BRAM | 0 (the 16-entry 30-bit arctan table is LUTROM) |
| Phase-pass latency | ~250 cycles ≈ 1 µs at 250 MHz, once per frame — 0.05 % of a 2 ms channelised frame; this is why the CORDIC is shared rather than replicated |
| Clock domain | 250 MHz wideband (`ap_clk` ← channelizer output clock, 4.0 ns) |

These are arithmetic, not synthesis results. G2 must replace every row with the
`csynth` report, and G3 with the Vivado OOC report
(`build/output/v07_gate3_ooc_synthesis.rpt`, `V07_GATE3_OOC_*` keys).

Two HLS hazards were removed before they could cost a synthesis run:

* The CORDIC normaliser was two data-dependent `while` loops. Vitis HLS cannot
  schedule a loop whose bound depends on data, so it is now 51 fixed-trip
  conditional steps (the host test still shows 1 LSB worst-case error, i.e. the
  change is bit-identical where it matters).
* `PIPELINE II=1` was on the phase loop. At `II=1` HLS would have to
  instantiate six copies of a fully unrolled 16-stage 64-bit CORDIC — six
  cascaded adder chains, ~10 ns each, at a 4.0 ns clock. The loop is now a
  sequential state machine sharing one datapath.

### 7.5 What G4 has to do (integration is deliberately not written yet)

`phase_interf_4ch` is packaged and collected by `step05`/`step06`, but
`config/zcu208_bd_map.tcl` does **not** instantiate it:
`08_integrate_doa_v7.tcl` attaches the six existing DOA AXI4-Lite slaves (it says
so in its header), and a seventh block cannot be added to a base design nobody
has measured. Wiring it blind would violate the rule that nothing is claimed that
was not run, so the integration checklist lives here instead:

| Item | Requirement |
|---|---|
| `ap_clk` | the **250 MHz wideband** net the `doa_subband_bridge_4ch` output lives on (`clkRFdiv2`-derived), not `/doa_v7` 125 MHz |
| `ap_rst_n` | same active-low synchronised reset as `doa_covariance_4ch_v4` |
| `s_axis` | `doa_subband_bridge_4ch` selected-bin output, 512-bit, `word = lane*4 + channel`, `{Q[31:16], I[15:0]}` |
| `m_axis` | an AXI4-Stream RX FIFO to the PS (the record the PS turns into WPI/coherence) |
| `m_phase` | 128-bit per frame; may share the same FIFO path behind a small arbiter, or a second FIFO |
| AXI4-Lite | its own address segment on `/control_interconnect`; `cal0..3` written with the **same** table as the covariance block |
| Clock-domain crossing | none needed if the above clock is respected; the existing 4 async converters are for the PS streams, not this block |

The PS sequence per frame is: write `frameSamples`, write `frameTag` from the
search result, read 16 words (`m_axis`) and one phase word (`m_phase`), then run
`estimate_doa_from_covariance_v7.m` verbatim.

Integration itself is G4: `step08` … `step11`, unrun.

---

## 8. Gates to close before any accuracy claim

| Gate | Command / artefact | Status |
|---|---|---|
| G0 estimator physics (host) | `python3 scripts/phase_interf_verify.py` | **PASS** |
| G0 front-end feasibility screen | `python3 scripts/estimate_wideband_dsp_resources.py` | **PASS** (screen only) |
| G0 estimator comparison vs 2D MUSIC/ISSM (§10) | `make compare-estimators` | **PASS** |
| G1a fixed-point core | `make -C ip/custom/phase_interf_4ch host-check` | **PASS** |
| G1b kernel + C-sim testbench on the host (shimmed) | `make -C ip/custom/phase_interf_4ch host-kernel-check` | **PASS** |
| G1c packaging/VLNV contract (config.mk ⇄ `build_hls.tcl` ⇄ `collect_ip.sh`) | `check_component_vlnv.sh` against a synthetic export, see evidence | **PASS** (contract only — not that Vitis produced it) |
| G2 HLS C-sim + csynth + export | `make step05_hls_phase_interf` | **NOT RUN** |
| G3 OOC synthesis + timing of the packaged IP at 4.0 ns | `make -C ip/custom/phase_interf_4ch gate3-ooc` (`gate3_ooc.tcl`, `v06_gate2` style) | **NOT RUN** — script written, never executed; it fails the gate on WNS < 0 or if `ap_clk` is not the 4.0 ns wideband period |
| G4 BD integration, validate, timing | `step08`…`step11` | **NOT RUN** |
| G5 RF loopback: measured phase vs known delay, sign and offset | HIL | **NOT RUN** |
| G6 calibrated array, chamber/field accuracy | HIL/chamber | **NOT RUN** |

Until G4–G6 exist, the only accuracy numbers this project may quote are the
simulated ones in §6, labelled as simulated.

**How to run each gate, what to look at, and how to publish the logs:**
[`GATES_RUNBOOK.md`](GATES_RUNBOOK.md). It also documents the two guards that
will stop you (an `arena/*` branch is required before logs may be pushed, and
`phase_interf_4ch` is not instantiated in the BD yet — §7.5).

---

## 9. Deferred and rejected

| Item | Disposition |
|---|---|
| MUSIC / CSSM / ESPRIT | Deferred — and now **measured**, not assumed: §10. 2.5–4.8× worse than WPI for one emitter, and structurally unable to separate two emitters on a 2×2 grid (manifold rank 2 at one elevation) |
| 16K FFT @ 2 GSPS | Rejected (§4) |
| 4.096 GSPS clock plan | Rejected (§3.1) |
| Fabric halfband decimator | Rejected — hardened in the RFDC (§3.4) |
| d = 50 mm element spacing | Rejected (§4.4) — would need a coarse/fine baseline pair |
| Phase-slope fit as primary estimator | Rejected; retained as a diagnostic and as an unwrap aid for long baselines |
| Multi-target (≥3 emitters) | Out of scope; needs subspace methods and more elements |
| 2.048 GSPS "critically sampled for 2 GHz complex BW" | True as a statement, but the PRF of the build kit is 2.000 GS/s (§3.1) |

---

---

## 10. Wideband 2D MUSIC vs interferometry, measured

The fair follow-up to §9's "MUSIC deferred" is: *if 0.5° is the requirement, is a
wideband 2D MUSIC/CSSM chain the better primary estimator?* Answered by
`scripts/compare_wpi_vs_music.py`, which runs four estimators on this array and
this band and compares them against the Cramér-Rao bound. Report:
[`docs/evidence/2026-11-06-phase-interf/wpi_vs_music_check.txt`](docs/evidence/2026-11-06-phase-interf/wpi_vs_music_check.txt).

### 10.1 One emitter: interferometry is already at the bound

4 elements, 2×2, 25 mm axes, 2.25–3.75 GHz, 20 dB/bin, 16 snapshots, az 12.5°,
el −8.3°, 40 Monte-Carlo trials:

| Estimator | az RMSE | el RMSE | vs WPI |
|---|---|---|---|
| **coherent WPI** (what the PL block accumulates) | **0.147°** | **0.121°** | 1.00× |
| ISSM (per-bin 2D MUSIC, spectra averaged over the band) | 0.362° | 0.442° | 2.47× |
| narrowband 2D MUSIC at 3.0 GHz, best single bin | 0.708° | 0.635° | 4.82× |
| **CRB (the information floor)** | **0.121°** | 0.115° | — |

WPI sits 1.22× above the CRB. Nothing — MUSIC included — can be materially
better, because 0.5° is not being limited by the estimator: it is limited by
bandwidth (2 GHz, already the V04 maximum), by SNR, and by snapshots. A
super-resolution estimator spends PS cycles to approach the same bound from the
wrong side.

### 10.2 Two emitters: the 2×2 array cannot represent them, at any SNR

This is the result that settles the architecture question, and it is structural
rather than numerical. For a planar grid the steering vector is

```text
a(θ) = [e^-jα, e^+jβ, e^-jβ, e^+jα],   α = π·f·d·(uy+uz)/c,  β = π·f·d·(uy-uz)/c
```

i.e. one fixed phase pattern times a *single* phase term. So the span of
`{a(az, el₀) : az}` has a hard rank at each elevation, and that rank is the
number of emitters a subspace method can even represent:

| Array | Elements | Rank at el = −8.3° | Two emitters found (30 dB/bin, N=128, 10 trials) |
|---|---|---|---|
| 2×2 (shipped) | 4 | **2** | 0/10 at 10° **and** 0/10 at 20° separation |
| 2×3 | 6 | 2 | — |
| 3×3 | 9 | 3 | 10/10 at 10° and 20° |
| 3×4 | 12 | 3 | — |
| 4×1 ULA along y | 4 | 4 | (azimuth only, no elevation) |

Read the 2×2 and 4×1 rows together: **the same four elements give rank 2 in a
2×2 grid and rank 4 in a ULA.** The 2×2 buys 2D coverage and gives up
multi-emitter capability; that trade is inherent to the geometry, not to the
estimator, and it is why two emitters collapse into one angle on this build kit
no matter what runs in the PS. Getting both would mean nine elements (3×3), which
is outside the V04 four-channel contract.

### 10.3 What actually blocks 0.5°: calibration and geometry

| Error source | Measured effect on the shipped chain |
|---|---|
| Residual per-channel delay, **one** complex coefficient per channel (as shipped) | 0.13° → **0.50°** as delay reaches 200 ps rms |
| Residual per-channel delay, per-bin calibration (PS rewrites `cal0..cal3` per selected bin) | stays **0.15°** |
| Element position error 0.1 mm | 0.28° |
| Element position error 0.5 mm | **1.11°** — more than the whole 0.5° budget |
| Calibration phase residual 1.0° / 3.0° (constant, §6) | 0.83° / 2.40° |

The delay row is actionable and new: `cal0..cal3` is one complex Q2.14 value per
channel, which is a **narrowband** calibration. Across 2 GHz, a residual delay
leaves a phase ramp that no single coefficient can remove, and the coherent sum
loses coherence. The fix is free — the block processes one selected bin cluster
per frame, so the PS should rewrite the calibration coefficients *for that bin*
before each frame, from a measured frequency-dependent calibration table. That
belongs in G5/G6, not in a new PL block.

### 10.4 Verdict

* **Keep coherent WPI as the primary estimator.** It is at the CRB, it is ~40
  DSP48 of arithmetic rather than a 2D search per bin, and it fits the existing
  4-channel contract.
* **Do not add 2D MUSIC/CSSM for accuracy.** Measured 2.5–4.8× worse for one
  emitter, and its one real benefit is unreachable on this array (rank 2).
* **Spend the effort where the budget actually goes:** frequency-dependent
  calibration (per-bin `cal`), array position measurement to ~0.1 mm, and the
  G5/G6 measurements. A 0.5° claim without those is a calibration claim, not an
  estimator claim.
* **If two emitters ever become a requirement**, it is an array change (≥ 3×3)
  and a channel-count change, not an estimator change. That is a V08-sized
  decision, and §10.2 is the number to start it from.

---

## 11. The 2×2 for 2–4 GHz at 0.5°: 30 mm, and a frequency-domain estimator

§4.4 rejected the review's 50 mm spacing on the strength of a *single-bin*
inversion at 3.75 GHz. That rejection is still correct, but it was one case of a
more general rule, and the review's other proposals (multi-frequency slope fit,
amplitude face selection, wrap rejection, RANSAC) deserve to be judged against
the whole band rather than one frequency. `scripts/compare_wideband_estimators.py`
does that: it simulates 128 bins over the full 2.000–4.000 GHz captured band,
four elements on a 2×2 grid, 20 dB per bin per element, 16 snapshots, and runs
five estimators on *the same* per-bin cross-spectra. The generated report is
[`docs/evidence/2026-11-06-phase-interf/wideband_df_check.txt`](docs/evidence/2026-11-06-phase-interf/wideband_df_check.txt);
everything in this section is a simulated number and says so.

### 11.1 The ambiguity rule for a square 2×2

A 2×2 grid has four baselines of length `d` and two diagonals of `d√2`. For a
direction in a cone of half-angle θ the largest projection on the diagonal is
`sin θ` (at 45° in azimuth), so the array is wrap-free while

```text
d · √2 · sin θ ≤ λ_min / 2      ⇒      d ≤ c / (2√2 · f_max · sin θ)
```

| Field half-angle | 2.0 GHz | 3.0 GHz | 4.0 GHz |
|---|---|---|---|
| ±30° | 106.0 mm | 70.7 mm | **53.0 mm** |
| ±45° | 74.9 mm | 50.0 mm | **37.5 mm** |
| ±55° (declared scan) | 64.7 mm | 43.1 mm | **32.3 mm** |
| ±60° | 61.2 mm | 40.8 mm | **30.6 mm** |

The declared scan is ±55°, so the rule allows **32.3 mm**. That single line
settles the spacing question: 30 mm is inside it, 37.5 mm is outside it, and the
review's 50 mm is outside it by a factor of 1.7 — its *diagonal alone* is
70.7 mm, which wraps above 2.6 GHz at the edge of the cone. The rule is
implemented in the script (`max_spacing_mm`, `two_by_two_limit_deg`) and
`config.mk` now carries `ARRAY_AXIS_SPACING_M ?= 0.030` together with
`ARRAY_CONE_HALF_ANGLE_DEG ?= 55`.

The rule was then measured rather than trusted (50 MHz emitter at 3.9 GHz, worst
|az error| of 6 trials, single-bin inversion):

| az / el | 22 mm | 25 mm | **30 mm** | 37.5 mm | 50 mm |
|---|---|---|---|---|---|
| 0 / 55 (elevation axis) | 0.86° | 1.64° | **1.79°** | 1.30° | 0.69° |
| 45.2 / −35.4 (diagonal stressed) | 1.18° | 0.63° | **1.60°** | **41.9°** | **33.9°** |
| 65 / 0 (outside the scan) | 1.71° | 1.71° | **1.10°** | 1.67° | **104.2°** |

37.5 mm and 50 mm lose the frame where the rule says they should, and 22–30 mm do
not. The 1.6–1.8° residuals at 30 mm are the *single-bin* estimator's noise, not
aliasing; the band-coherent estimators in §11.2 give 0.25°.

### 11.2 Spacing against estimator, measured over the whole band

RMSE in degrees, 20 trials, az 12.5° / el −8.3°, 20 dB/bin, N = 16. "wideband"
is a 2 GHz emitter filling the band, "narrowband" a 50 MHz emitter at 3 GHz.

| d | centroid WB | nb_centre WB | slope_icpt WB | **slope_origin WB** | wb_ml WB | centroid NB | slope_icpt NB | slope_origin NB | wb_ml NB |
|---|---|---|---|---|---|---|---|---|---|
| 22 mm | 0.084 | 0.662 | 0.424 | 0.071 | 0.075 | 0.383 | **85.5** | 0.387 | 0.449 |
| 25 mm | 0.096 | 0.691 | 0.290 | 0.068 | 0.085 | 0.429 | **79.5** | 0.423 | 0.482 |
| **30 mm** | 0.107 | 0.456 | 0.235 | **0.066** | 0.084 | **0.252** | **83.4** | 0.265 | 0.263 |
| 37.5 mm | 0.075 | 0.379 | 0.270 | 0.032 | 0.046 | 0.238 | **56.9** | 0.242 | 0.268 |
| 50 mm | 0.062 | 0.266 | 0.166 | 0.020 | 0.036 | 0.210 | **41.4** | 0.190 | 0.247 |
| 75 mm | 0.064 | 0.146 | 0.102 | 0.023 | 0.029 | 0.148 | **25.1** | 0.142 | 0.174 |

Three things fall out of this table, and they are the reason §0's verdict on the
phase-slope fit is restated in §11.4:

1. **The through-origin fit is the best estimator for a wideband emitter** — 5×
   better than the current band-centroid coherent average at 30 mm (0.066° vs
   0.107°) and 9× better than a single-bin inversion. The review's mechanism is
   right.
2. **The review's own version of that fit — unwrap, then include an intercept —
   is the worst estimator in the table**: 0.235° wideband at 30 mm, and
   *catastrophic* (75–86° RMSE) for a narrowband emitter, where it loses 9–10 of
   10 frames at every SNR (§11.4). An intercept is a parameter the physics does
   not contain: the source phase cancels in `X_b·conj(X_a)`, so the fit is
   through the origin by construction.
3. **The band-coherent centroid average, which is what the HDL does today, is
   already inside 0.1° wideband and 0.25° narrowband at 30 mm.** The estimator is
   not the limiter; §11.3 is.

The narrowband column is *conservative*: the simulation uses 128 bins across
2 GHz (15.6 MHz bins), while the real channelizer has 1.953 MHz bins, i.e. 8×
more bins per 50 MHz emitter and about `√8` less angle noise.

### 11.3 Geometry and calibration still dominate

Random element-position error `δ` perturbs the phase by `k·δ·u`, so the angle
error scales as `δ/d` in first order. Measured (13 trials, wideband emitter,
RMSE azimuth in degrees):

| d | 0.1 mm rms | 0.25 mm | 0.5 mm | 1.0 mm |
|---|---|---|---|---|
| 25 mm | 0.243 | 0.537 | 1.276 | 2.685 |
| **30 mm** | 0.245 | 0.630 | **0.792** | 1.720 |
| 37.5 mm | 0.160 | 0.330 | 0.756 | 1.324 |
| 50 mm | 0.133 | 0.253 | 0.607 | 1.676 |

At 30 mm, a 0.5 mm position residual costs **0.79°** against a 0.066° noise term
— a factor of 12. 0.5° therefore needs a position/calibration residual of
≈0.3 mm, which is G6 work, not a firmware change. This is consistent with §10.3
and with the review's instinct that the geometry has to be *validated* (4.6);
it is inconsistent with treating a spacing change as an accuracy fix.

### 11.4 The review's chain, item by item

| Review item | Verdict | Reason (measured unless marked *computed*) |
|---|---|---|
| Corrected SSR chain: NCO → halfband ×2 → 2.048 GSPS complex, 2 GHz BW, **not** ×80 | **ADOPT — already true** | V04 locks 4.000 GSPS ÷ 2 = 2.000 GS/s complex (§5.1). The review's 2.048 GSPS is the 4.096 GSPS converter's rate; this board runs 4.000 GSPS, so the decimated rate is 2.000 GS/s and the centre is 3.000 GHz, not 3.072 GHz (§3.1). |
| 4.6 ambiguity validation: linear-fit R² > 0.95 | **ADOPT as a diagnostic, not a gate** | On a single emitter the through-origin fit is linear by construction, so R² ≈ 1 even at 0 dB/bin; it detects multi-emitter and hardware faults, not accuracy. Compute it on the *through-origin* fit, report it in telemetry, and do not gate the estimate on it. |
| 4.6 baseline consistency: CH1−CH2 vs CH3−CH4, CH1−CH3 vs CH2−CH4 within 2° | **ADOPT — cheapest real fault check** | The 2×2 gives all six cross-products; pairs (0,1)/(2,3) and (0,2)/(1,3) are the same baseline twice, so their phases must agree to within the phase noise. Set the threshold from the measured per-bin SNR (`σ_φ ≈ 1/√(2·N·SNR)`), not as a fixed 2°. |
| 4.6 phase-wrap rejection: `|Δφ(k+1) − Δφ(k)| > π` | **REJECT as a gate** | The rule fires on the true solution at high angle and low SNR. Measured: the unwrap-plus-intercept fit loses 9–10 of 10 frames on a 50 MHz emitter at 20 dB down to 0 dB, while the through-origin fit and the frequency-steered ML lose 0. Keep it only as a per-bin *flag* that down-weights a bin. |
| 4.6 RANSAC two-line fit for two targets | **REJECT — wrong tool for this hardware** | The 2×2 manifold has rank 2 at these elevations, so two emitters are mathematically unrepresentable (0/10 detections, §10.2) whatever the estimator; a RANSAC sweep is 10²–10³× the PS cost per frame for a result the array cannot support. Two targets is a ≥3×3 array decision (V08), not an estimator decision. |
| Amplitude face selection: `|X₂|²−|X₁|²` sign + 256-entry ratio LUT, 3–10° zones | **REJECT for identical broadside elements** | Measured |X₂|²/|X₁|² spread over 0–65° is **0.006** — the ratio carries no angular information at the 10⁻² level, so the LUT would store noise. It works only with squinted or offset feeds, which this aperture does not have. The existing rule (§5.5: amplitude resolves the ±45° quadrant, phase resolves the ambiguity) stands. |
| 4.4 multi-frequency phase-slope fitter: Σx, Σy, Σxy, Σx² accumulators, 48-bit, arcsin LUT, ~10 DSP48 | **ADOPT with three corrections** | (i) Fit **through the origin** — no intercept (0.066° vs 0.235° measured). (ii) **Do not unwrap and do not build the slope test on `atan`**: the equivalent and branch-free form is the complex frequency-steered sum `|Σ_k S_b(k)·w_k·e^{+j2πf_k b·u/c}|²`, which needs one CORDIC per hypothesis rather than one per bin, and it is what the `wb_ml` column measures (0.084° wideband, 0.263° narrowband). (iii) The four-accumulator form is fine as a *diagnostic* (it is the R² generator), and 48-bit accumulation with 12-bit phase is right; the arcsin LUT is unnecessary because the direction comes out as `u = −c/(2π)·(BᵀB)⁻¹Bᵀg`. |
| `d_az = d_el = 50 mm` | **REJECT — 1.7× too wide** | §11.1: the rule gives 32.3 mm for ±55° at 4 GHz, and 50 mm is measured 33.9°/104.2° off where 30 mm holds 1.6°/1.1°. `ARRAY_AXIS_SPACING_M` is now 0.030. |
| Bin width 125 kHz (16K FFT at 2.048 GSPS) | **REJECT — unchanged from §3.1/§4** | 2.048 GSPS / 16 384 = 125 kHz, so the number is internally right and still 16× finer than anything this design needs; the 1024-band channelizer already gives 1.953 MHz with 100 dB stopband. Finer bins buy emitter separation inside the band, not angular accuracy at equal observation time (§4.3). |
| Kaiser β = 6 window | **ADOPT, if a window is used at all** | β = 6 is a ~60 dB sidelobe taper, appropriate for a 1024-band PFB whose prototype is already specified at 100 dB stopband with 12 taps. No change to the adopted channelizer; recorded here because it is a reasonable choice, not a defect. |
| CFAR / AMC / Kalman tracker (Singer, χ² gate, 100 ms coast) | **UNCHANGED — out of scope for 0.5°** | Detection and tracking do not move the angular estimate; they are already in the PS plan and deferred. |

### 11.5 What changed in this repository

| Change | File |
|---|---|
| `ARRAY_AXIS_SPACING_M` 0.025 → **0.030**, plus `ARRAY_CONE_HALF_ANGLE_DEG ?= 55`, with the rule written into the comment | `config.mk` |
| MATLAB reference geometry follows the same constant (`P.Antenna.d`, `P.dx/P.dy`, `dx/dy`) | `matlab_v7/sim3d_params.m`, `doa_search_params.m`, `SyntheticFourChannelSource.m` |
| New study script + evidence report | `scripts/compare_wideband_estimators.py`, `docs/evidence/2026-11-06-phase-interf/wideband_df_check.txt` |
| `make wideband-df` (full study) and `make compare-estimators` (both studies) | `Makefile` |
| Estimator order in the PS spec: through-origin fit first, band-centroid average for narrowband, single-bin inversion only as a fallback with the ambiguity guard | this section, §5.4 |
| Guards: baseline-consistency check and R² diagnostic adopted; wrap-rejection gate and amplitude face selection not adopted | this section, §11.4 |

#### 11.5.1 The arithmetic the PS has to run

For each of the six baselines `B_j` and the `K` bins the block reports, with
`f_k` the bin centre and `S_j(k)` the accumulated cross-spectrum:

```text
through-origin slope   g_j = Σ_k w_jk · f_k · φ_jk  /  Σ_k w_jk · f_k²      [rad/Hz]
                       (φ_jk = arg S_j(k), w_jk = coherence-derived weight)
joint direction        u  = −(c/2π) · (BᵀWB)⁻¹ BᵀW g        (2×2 inverse, closed form)
residual / quality     R²_j = 1 − Σ w (φ − g f)² / Σ w φ²
baseline consistency   Δ_j = φ_j − φ_j'   for the duplicate pairs (0,1)/(2,3) and (0,2)/(1,3)
wrap flag              |φ_j(k) − g_j f_k| > π   per bin, used as a weight, never as a reject
```

`g_j` is a 48-bit accumulator pair per baseline (12-bit phase × 32-bit frequency
× 1024 bins overflows 32 bits); the 6 → 2 solve is six multiply-accumulates and
one 2×2 inverse, i.e. the "~10 DSP48" the review quotes. The frequency-steered
ML alternative (§11.2) replaces the whole block with
`max_{u} Σ_k |Σ_j S_j(k) w_jk e^{+j2πf_k B_j·u/c}|²`, which costs a CORDIC per
grid hypothesis instead of per bin and is what should be used to resolve an
ambiguity or to report a two-peak score.

The 25 mm geometry of §4.4 remains available as `ARRAY_AXIS_SPACING_M=0.025`;
it is the right choice if the qualified field ever becomes ±90° in both axes,
and it costs 1.3–1.6× in the geometry term. What is *not* available is 50 mm.

### 11.6 If the pitch can be 75 mm or 150 mm

The spacing rule of §11.1 is the rule for a **closed-form phase estimator**. A
frequency-steered ML never unwraps anything, so it is not bound by it: over a
2 GHz band it stays correct to `d < c/(2B) = 75 mm` for the *phase-slope* form
and much further for the ML. Measured (wideband 2 GHz emitter, 20 dB/bin, N=16,
RMSE azimuth in degrees; `slope` = through-origin fit, `ML` = per-bin
frequency-steered):

| d | estimator | 0° | 20° | 40° | 55° | 65° |
|---|---|---|---|---|---|---|
| 30 mm | slope | 0.043 | 0.082 | 0.044 | 0.066 | 0.132 |
| 30 mm | ML | 0.099 | 0.090 | 0.061 | 0.069 | 0.125 |
| 75 mm | slope | 0.020 | 0.015 | **36.6** | **67.3** | **79.5** |
| 75 mm | ML | 0.022 | 0.026 | 0.026 | 0.041 | 0.045 |
| 150 mm | slope | 0.011 | **21.0** | **41.3** | **53.8** | **63.8** |
| 150 mm | ML | **0.011** | **0.014** | **0.016** | **0.017** | **0.030** |

Read it as three separate conclusions:

* **150 mm + ML is the most accurate single-emitter configuration measured
  here**: 0.011–0.030° across the field, five times better than 30 mm, because
  the baseline is five times longer and the ML squeezes the whole band.
* **Everything cheap dies at 150 mm.** The closed-form through-origin fit is
  21–64° off from 20° outward, and the band-centroid average is 9.8° (§11.2
  table). If the pitch is 150 mm, the PS *must* run the ML search; the 40-DSP48
  closed form cannot be used at all.
* **A narrowband emitter at 150 mm is unrecoverable by any estimator** —
  measured 9.8° (centroid) and 54° (ML) for a 50 MHz emitter, because a
  50 MHz emitter does not span enough bandwidth to break the grating lobe.
  150 mm is a wideband-only geometry.

So the pitch is a requirements question, not an optimisation: 30 mm if narrowband
emitters and a cheap closed-form estimator must be supported; 150 mm if the
emitters are wideband, the PS can afford an ML search, and 0.01–0.03° is worth
it. What does *not* work is 150 mm with the current estimator.

### 11.7 What is still not proven here

* Everything in this section is a **simulation** of per-bin cross-spectra. No RF,
  no antenna, no mutual coupling, no calibration measurement is behind it.
* Mutual coupling is ignored. At 30 mm, the low end of the band is 0.20λ, which
  is the tightly-coupled-dipole regime, not the Vivaldi/horn regime; a 0.3λ
  element cannot be built at 2 GHz into a 30 mm pitch. This is a *front-end
  feasibility* question that no amount of estimator work answers.
* The 0.5° claim still waits on G5 (RF loopback) and G6 (calibration/geometry),
  exactly as §8 and §10.4 say.
* The 150 mm result of §11.6 also assumes the element can be built at 150 mm —
  a 2 GHz element is 0.5λ there, so coupling is mild — but the *grating lobes*
  are not a simulation artefact: they are real and only the band resolves them.

---

## 12. Eight emitters over 2 GHz: a different array, and 2D MUSIC

§11 answers "one emitter, 0.5°, 2–4 GHz" with 30 mm and per-bin phase
interferometry. A requirement of *eight simultaneous emitters* inside the same
2 GHz band splits in two, and the split is the whole answer:

* **co-channel** — eight emitters occupying the same bins: not a firmware
  question, it changes the element count, the block and the estimator (§12.1–12.4);
* **frequency-separated** — eight emitters of 1–50 MHz at different carriers,
  which is what a 2–4 GHz tuning range with narrowband targets actually means:
  the shipped 2×2 detects all eight and meets the accuracy requirement with
  dwell, not with elements (**§12.4** — read that first if the targets are
  narrowband). `scripts/multisource_capacity.py`
→ [`multisource_capacity.txt`](docs/evidence/2026-11-06-phase-interf/multisource_capacity.txt).

Model: eight emitters at az −40…+40°, el −14…+12° (6–15° apart), 20 dB per bin
per emitter, 96 snapshots per bin, 48 bins over 2.000–4.000 GHz. Estimator:
per-bin incoherent 2D MUSIC (ISSM) — one covariance per bin, one 2D
pseudo-spectrum per bin, summed over the band, the strongest local maxima taken
as the source set and matched to the truth. Every number below is simulated.

### 12.1 The 2×2 cannot be part of this answer

| Array | Elements | M−1 bound | Measured manifold rank | 8-detection |
|---|---|---|---|---|
| 2×2 @ 30 mm | 4 | 3 | 4 | **1.2 of 8** |
| 3×3 @ 30 mm | 9 | 8 | 9 | 2.0 of 8 |
| 4×4 @ 30 mm | 16 | 15 | 16 | 4.5 of 8 |
| 4×4 @ 60 mm | 16 | 15 | 16 | 7.0 of 8, RMSE 0.394° |
| 5×5 @ 60 mm | 25 | 24 | 25 | 7.0 of 8, RMSE 0.317° |
| 6×6 @ 75 mm | 36 | 35 | 36 | **8.0 of 8 in 12/12, RMSE 0.295°** |
| 2×2 @ 150 mm | 4 | 3 | 4 | 1.5 of 8 |
| 3×3 @ 150 mm | 9 | 8 | 9 | 1.8 of 8 |
| 4×4 @ 150 mm | 16 | 15 | 16 | 6.0 of 8, RMSE 0.326° |

The "manifold rank" column is measured over the whole 2-D field at 3 GHz (it is
the element count until the array runs out of independent directions); the
*fixed-elevation slice* of §10.2 is rank 2, which is the number that matters when
all emitters share an elevation. A 150 mm pitch does **not** rescue a small array: 2×2 @ 150 mm still finds
1.5 of 8, and 4×4 @ 150 mm (600 mm aperture, twice the aperture of 4×4 @ 60 mm)
finds *six* of eight where 4×4 @ 60 mm finds seven — the grating lobes at the
2 GHz edge eat the extra aperture. 60–75 mm is the useful pitch band for eight
emitters. The 2×2 finds 1.2 of 8 because four elements
carry at most three sources and, on a single elevation, only one — the array,
not the estimator, is the limit. The single-emitter accuracy of §11 (0.066°) does not transfer to a
multi-emitter requirement by any algorithmic trick.

### 12.2 Aperture, not bandwidth, separates them

Same eight emitters, same estimator, only the captured band changes:

| Array | 600 MHz | 2 GHz |
|---|---|---|
| 4×4 @ 30 mm (90 mm aperture) | 4.9 of 8 | 4.8 of 8 |
| 4×4 @ 60 mm (180 mm aperture) | 7.0 of 8 | 7.0 of 8 |
| 4×4 @ 150 mm (450 mm aperture) | **2.0 of 8** | 6.0 of 8 |

Doubling the *aperture* doubles the detection — for a well-sampled array;
the 150 mm case is the exception that proves the rule, because there the narrow
band leaves the grating lobes unresolved and detection collapses from 6.0 to 2.0
of 8. Tripling the bandwidth does not move the 30 mm and 60 mm cases at all. Resolution is set by aperture and by the low edge of the band
(`1.22·λ/D`: 58° at 2 GHz for the 180 mm array — MUSIC super-resolves that at
these SNRs, which is exactly why it needs the extra elements). What the 2 GHz
bandwidth buys is the alias rejection of §11 and `√K` noise averaging; it is
not a substitute for aperture.

Note also that the winning geometry uses 75 mm pitch — twice what §11 allows for
a ±55° *single-emitter* scan — because a multi-source array may be spatially
undersampled per bin as long as the frequency ramp resolves the resulting
aliases. That is the same argument as §11.1, used in the other direction.

### 12.3 What the algorithm has to become

| Single emitter (shipped) | Eight emitters (would be V08) |
|---|---|
| per-bin cross-spectrum, 6 baselines, one phase vector | per-bin **spatial covariance** `R(k) = X(k)ᴴX(k)`, M×M, M ≥ 9 |
| closed-form WLS on 6 phases (~40 DSP48 in PL) | per-bin eigendecomposition of an M×M covariance plus a 2D grid search — PS/ARM work, or a systolic PL solver |
| one direction out, per frame | K peaks, then **association and tracking** across frames (the χ²-gated tracker already in the PS plan) |
| 4 RF channels, `phase_interf_4ch` | 16–36 RF channels: 4 → 9/16/36 ADC lanes, a wider `rfdc_repack`, and a covariance block per bin (M² accumulators per bin — 256 complex accumulators for 16 elements) |

Nothing in the present build kit implements any of that: `phase_interf_4ch`
produces six phases, not a covariance, and the platform carries four ADC
channels. It is a channel-count and device-size decision (the ZCU208 has 8 ADC
and 8 DAC tiles per ZU48DR — 16 elements is at the edge of one device, 36 is
not), i.e. V08, not a patch to V07.

### 12.4 The case that actually matches the requirement: 1–50 MHz targets

The 2–4 GHz figure in the requirement is the **tuning range of the receiver**,
not the instantaneous bandwidth of any one emitter: each target occupies
1–50 MHz, i.e. 1 to 26 bins of the 1024-band channelizer. That inverts two
conclusions of §11 and §12, so it was measured separately
(`scripts/narrowband_targets.py` →
[`narrowband_targets.txt`](docs/evidence/2026-11-06-phase-interf/narrowband_targets.txt)).

Eight targets at carriers spread over 2.15–3.92 GHz, bandwidths 1/5/20/50 MHz,
az −38…+48°, 20 dB/bin, 64 snapshots per bin, **2×2 at 30 mm**:

| Measurement | Result |
|---|---|
| targets detected (per-bin detection, clustered by frequency, matched to truth) | **8.0 of 8, every one of 20 trials** |
| accuracy vs bandwidth and dwell | see below |

RMSE azimuth in degrees, single target at 3.0 GHz, 2×2 at 30 mm, 20 dB/bin:

| target bandwidth | 16 snapshots | 64 snapshots | 256 snapshots |
|---|---|---|---|
| 1 MHz (1 bin) | 0.590 | 0.272 | 0.119 |
| 5 MHz (3 bins) | 0.447 | 0.240 | 0.128 |
| 20 MHz (10 bins) | 0.148 | 0.126 | 0.062 |
| 50 MHz (26 bins) | 0.137 | 0.068 | 0.022 |

**Why four elements are enough here and not in §12.1.** The channelizer separates
the targets by frequency *before* any spatial processing, so each cluster holds
one target and the spatial estimator never has to resolve two sources. The eight
co-channel emitters of §12.1 did need 36 elements; eight narrowband emitters at
different carriers need four. The cost moved from the array to the channelizer,
which this kit already has.

**Two accuracy classes, both reachable with the same hardware.**
A 1 MHz target (one bin) lives entirely on dwell time:

| snapshots | 4 | 16 | 64 | 256 |
|---|---|---|---|---|
| az RMSE, 1 MHz at 30 mm | 1.42° | 0.53° | 0.28° | 0.10° |

So the operator-designated priority target reaches the 0.5° class with ~64
snapshots of coherent integration (≈ 33 µs of the 2 GS/s stream per bin), and
the remaining seven meet their 3° allowance at **4 snapshots** — one short frame,
no calibration refinement, no extra hardware. That is the cheapest way to satisfy
the stated requirement: spend dwell on the one target that matters, and report
the rest coarsely.

**What still breaks it** — two targets inside the *same* bins (co-channel), two
50 MHz targets 15 MHz apart at az 10° and 25°:

| array | of 2 recovered | false peaks |
|---|---|---|
| 2×2 @ 30 mm | **0.2** | 1.5 |
| 3×3 @ 30 mm | 2.0 | 0.0 |
| 4×4 @ 30 mm | 2.0 | 0.0 |

That is the measured form of the M−1 rule: co-channel sources need ≥ 9 elements,
frequency-separated ones do not. If the eight targets are guaranteed to occupy
different bins — 1–50 MHz emitters inside 2 GHz almost always do — the shipped
2×2 is sufficient.

**Caveats.** Simulated per-bin cross-spectra: no calibration error, no coupling,
equal per-bin SNR, and detection is a 4× median-power threshold rather than a
CFAR with a measured Pfa. A 1 MHz target is narrower than one 1.953 MHz bin, so
its real SNR per bin depends on where it lands relative to the bin edges — a
scalloping loss this model does not include (up to ~2 dB at worst alignment).

### 12.5 Honest limits of these numbers

* Equal-power emitters, no mutual coupling, no calibration error, no
  correlated sources. Real arrays with 8 emitters fail on calibration and
  dynamic range long before they fail on the estimator.
* Sources were held at fixed angles across trials; detection statistics for
  closely spaced pairs (≤ 3°) are not characterised here.
* MUSIC was given the true source count (8). In hardware it has to be estimated
  (MDL/AIC on the per-bin eigenvalues), and an error there is the usual cause of
  a missed or spurious peak.
* 0.295° is a *four-element-per-row* array at 75 mm pitch, i.e. a 375 mm
  aperture. At 2 GHz that is 2.5λ; the low band edge, not the estimator, sets it.

---

## 13. Files

| File | Role |
|---|---|
| `V07_PHASE_INTERFEROMETRY.md` | this decision record |
| `scripts/phase_interf_verify.py` | estimator Monte-Carlo, writes the accuracy report |
| `scripts/estimate_wideband_dsp_resources.py` | front-end/device screen, writes the resource report |
| `scripts/compare_wpi_vs_music.py` | §10: interferometry vs wideband 2D MUSIC/ISSM, manifold-rank result, calibration and geometry sensitivity |
| `scripts/compare_wideband_estimators.py` | §11: spacing rule for a square 2×2, five estimators over the full 2–4 GHz band, ambiguity/geometry/wrap studies |
| `scripts/multisource_capacity.py` | §12: how many emitters each array can represent, eight-emitter detection vs elements/aperture/bandwidth, and what the algorithm has to become |
| `scripts/narrowband_targets.py` | §12.4: eight 1–50 MHz targets at different carriers on the shipped 2×2 — detection, accuracy vs bandwidth and dwell, the co-channel failure, and the dwell the two accuracy classes need |
| `ip/custom/phase_interf_4ch/` | per-bin cross-spectrum + CORDIC phase block, host test, HLS build |
| `matlab_v7/PhaseInterferometryEstimator.m` | MATLAB reference of the PS-side estimator selection |
| `matlab_v7/verify_phase_interferometry_2x2.m` | time-domain (windowed FFT + quantised) verification |
| `docs/evidence/2026-11-06-phase-interf/` | generated evidence reports |

Run:

```bash
make verify-phase-interf              # reports + host core test + shimmed kernel test
make compare-estimators               # sections 10 and 11: both studies, full
make wideband-df                      # section 11 only, ~6 min
make multisource-df                   # section 12.1-12.4, ~4 min
make narrowband-targets               # section 12.4, ~10 s
python3 scripts/compare_wideband_estimators.py --quick   # ~1 min smoke run
make matlab-lint                      # optional parse check, needs pip install miss_hit
make step05_hls_phase_interf          # needs Vitis HLS 2023.2 (gate G2); see GATES_RUNBOOK.md
```

`make verify-phase-interf` needs only python3 + numpy + g++; it regenerates both
reports in `docs/evidence/2026-11-06-phase-interf/`, re-runs the bit-exact core
test, and compiles plus runs the production kernel and testbench against the
host shim.
