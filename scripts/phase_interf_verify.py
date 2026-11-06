#!/usr/bin/env python3
"""V07 phase-interferometry reference check (host-side, no MATLAB needed).

This script is the numerical evidence for V07_PHASE_INTERFEROMETRY.md.  It
answers, with numbers, the three estimator questions raised by the external
architecture review:

  Q1  Does a per-bin cross-spectrum + coherent sum ("WPI") meet the 0.5 deg
      requirement for the emitters this build kit actually targets?
  Q2  Is the review's "multi-frequency phase-slope fit" a better estimator?
      (It is the better estimator only for emitters that fill the band, and
      it is catastrophically worse for narrowband emitters -- see CASE 1/2.)
  Q3  Is the review's d = 50 mm geometry usable across 2-4 GHz?

Estimator set
-------------
coherent_wpi   sum the cross-spectrum over the emitter's occupied bins, take
               one phase, convert to direction cosines (the V07 primary path;
               this is what ip/custom/phase_interf_4ch accumulates in PL).
slope_ideal    weighted LS slope of unwrapped per-bin phase vs frequency, with
               *oracle* unwrapping (the true ramp removed first).  This isolates
               the estimator's own physics from unwrap failures.
slope_naive    the external review's exact recipe: np.unwrap + weighted
               polyfit, as written in its MATLAB block.
single_bin     peak-bin phase only, no bin averaging (bin-SNR limited).

Sign convention
---------------
This script forms the conjugate-ordered statistic S_ab = X_a*conj(X_b), so the
baseline phase is +2*pi*f*(p_b-p_a).u/c and the direction cosines carry a leading
plus.  The HDL block (ip/custom/phase_interf_4ch) accumulates the other order,
S_ba = X_b*conj(X_a), exactly as doa_covariance_4ch_v4 does, so its phase has the
opposite sign and the PS applies the leading minus of
estimate_doa_from_covariance_v7.m.  The two are numerically identical estimators:
the sign of the statistic is a wiring choice, not a physics choice.  Every
accuracy number below is invariant to it.

Model
-----
Four coherent channels, complex baseband after the RFDC DDC (Fs = 2.000 GS/s,
2x decimation of the 4.000 GSPS MTS plan, V04).  One emitter with occupied
bandwidth B_sig at RF offset f_off from F_C, direction u = (ux, uy, uz):

    X_n(k) = A_n(k) * S(k) + N_n(k)
    A_n(k) = exp(-j*2*pi*f_RF(k)*(p_n . u)/c),   f_RF(k) = F_C + f_bb(k)

with independent circular Gaussian noise.  Because

    S_ab = X_a * conj(X_b) = exp(+j*2*pi*f*(p_b - p_a).u/c) * |S|^2

the az pair CH1-CH2 (baseline along +y) gives
    uy = +angle(S_12)*c/(2*pi*f*d)
and the el pair CH1-CH3 (baseline along +z) gives
    uz = +angle(S_13)*c/(2*pi*f*d).

Generating spectra directly is exactly the input of any per-bin estimator;
time-domain windowing/leakage and quantisation are covered by
matlab_v7/verify_phase_interferometry_2x2.m instead.

Run:  python3 scripts/phase_interf_verify.py [--quick]
"""

from __future__ import annotations

import argparse
import datetime as _dt
import math
import os
import sys

import numpy as np

C_LIGHT = 299792458.0
FS_HZ = 2.0e9              # V04: 4.000 GSPS / decimation 2
N_FFT = 16384              # analysis length requested by the external review
RF_CENTER_HZ = 3.0e9       # V04 default centre
BIN_HZ = FS_HZ / N_FFT

# ZU48DR / ZCU208 capacity as extracted in the V06 evidence (used by
# scripts/estimate_wideband_dsp_resources.py, repeated here for the report).
DEVICE = {"LUT": 425280, "FF": 850560, "BRAM36": 1080, "URAM": 80, "DSP48": 4272}


# --------------------------------------------------------------------------
# geometry
# --------------------------------------------------------------------------
def array_2x2(spacing_m: float) -> np.ndarray:
    h = spacing_m / 2.0
    return np.array([[0.0, -h, -h],
                     [0.0, +h, -h],
                     [0.0, -h, +h],
                     [0.0, +h, +h]])


def unit_vector(az_deg: float, el_deg: float) -> np.ndarray:
    az, el = math.radians(az_deg), math.radians(el_deg)
    return np.array([math.cos(el) * math.cos(az),
                     math.cos(el) * math.sin(az),
                     math.sin(el)])


def angles_from_direction(uy: float, uz: float) -> tuple[float, float]:
    ux = math.sqrt(max(1.0 - uy ** 2 - uz ** 2, 0.0))
    elevation = math.degrees(math.asin(max(-1.0, min(1.0, uz))))
    return math.degrees(math.atan2(uy, ux)), elevation


def steering(positions: np.ndarray, freqs_hz: np.ndarray, u: np.ndarray) -> np.ndarray:
    """A[n, k] = exp(-j*2*pi*f_k*(p_n . u)/c)."""
    proj = positions @ u
    return np.exp(-1j * 2.0 * np.pi * np.outer(proj, freqs_hz) / C_LIGHT)


# --------------------------------------------------------------------------
# signal synthesis
# --------------------------------------------------------------------------
def synth_spectra(rng, positions, u, f_bb, b_sig_hz, snr_db_band, n_snapshots=1,
                  f_offset_hz=0.0):
    """Complex spectra of the four channels and the occupied-bin mask.

    snr_db is the PER-BIN SNR (one 122.07 kHz bin) with a flat noise density
    across the whole 2 GHz captured band; it is the number a channelizer or
    FFT output actually reports, and it is the quantity the two estimators
    consume differently (coherent sum: sigma = sbin/sqrt(N); slope fit:
    sigma = sbin*sqrt(12)/(sqrt(N)*B)).
    """
    n_fft = f_bb.size
    mask = np.abs(f_bb - f_offset_hz) <= b_sig_hz / 2.0
    n_occ = int(mask.sum())
    if n_occ == 0:
        raise ValueError("empty occupied band")
    sig_amp = math.sqrt(1.0 / n_occ)                 # total signal power = 1
    snr_lin = 10.0 ** (snr_db_band / 10.0)
    noise_sigma = math.sqrt(1.0 / snr_lin / n_occ)   # noise power per bin

    f_rf = RF_CENTER_HZ + f_bb
    # shape (snapshot, channel, bin); the PL accumulator sums cross-spectra over
    # snapshots, so keep them separate instead of pre-summing the waveforms.
    out = np.zeros((n_snapshots, 4, n_fft), dtype=complex)
    for snap in range(n_snapshots):
        s = np.zeros(n_fft, dtype=complex)
        s[mask] = sig_amp * (rng.standard_normal(n_occ) + 1j * rng.standard_normal(n_occ)) / math.sqrt(2.0)
        for n in range(4):
            out[snap, n] = steering(positions[[n]], f_rf, u)[0] * s
            out[snap, n] += noise_sigma * (rng.standard_normal(n_fft) + 1j * rng.standard_normal(n_fft)) / math.sqrt(2.0)
    return out, mask


# --------------------------------------------------------------------------
# estimators -- each returns (uy, uz)
# --------------------------------------------------------------------------
def _cross(x, a, b):
    """Cross-spectrum summed over snapshots -- the hardware accumulator."""
    return np.sum(x[:, a] * np.conj(x[:, b]), axis=0)


def coherent_wpi(x, mask, f_rf, spacing_m, u_true=None):
    power = np.sum(np.abs(x) ** 2, axis=(0, 1))
    if np.any(power <= 0):
        return float("nan"), float("nan")
    f_c = float((power[mask] * f_rf[mask]).sum() / max(power[mask].sum(), 1e-30))
    scale = C_LIGHT / (2.0 * np.pi * f_c * spacing_m)
    return (np.angle(_cross(x, 0, 1)[mask].sum()) * scale,
            np.angle(_cross(x, 0, 2)[mask].sum()) * scale)


def single_bin(x, mask, f_rf, spacing_m, u_true=None):
    power = np.sum(np.abs(x) ** 2, axis=(0, 1))
    k = int(np.argmax(np.where(mask, power, -np.inf)))
    scale = C_LIGHT / (2.0 * np.pi * f_rf[k] * spacing_m)
    return (np.angle(_cross(x, 0, 1)[k]) * scale,
            np.angle(_cross(x, 0, 2)[k]) * scale)


def _weighted_slope(freqs, phase, power):
    w = power / max(power.sum(), 1e-30)
    fx = float((w * freqs).sum())
    fy = float((w * phase).sum())
    sxx = float((w * (freqs - fx) ** 2).sum())
    sxy = float((w * (freqs - fx) * (phase - fy)).sum())
    return sxy / sxx if sxx > 0 else float("nan")


def slope_ideal(x, mask, f_rf, spacing_m, u_true):
    """Same slope estimator, but unwrapped against the true ramp.

    This is the best case any slope implementation can reach: it removes the
    2*pi wrap ambiguity that dominates a naive unwrap of noisy bins.
    """
    f = f_rf[mask]
    dirs = []
    for pair in ((0, 1), (0, 2)):
        cross = _cross(x, *pair)[mask]
        proj = (array_2x2(spacing_m)[pair[1]] - array_2x2(spacing_m)[pair[0]]) @ u_true
        predicted = 2.0 * np.pi * f * proj / C_LIGHT
        residual = np.angle(cross * np.exp(-1j * predicted))
        slope = _weighted_slope(f, residual, np.abs(cross))
        dirs.append(slope * C_LIGHT / (2.0 * np.pi * spacing_m)
                    + (proj / spacing_m))
    return dirs[0], dirs[1]


def slope_naive(x, mask, f_rf, spacing_m, u_true=None):
    """The external review's recipe, verbatim: unwrap then weighted polyfit."""
    f = f_rf[mask]
    dirs = []
    for pair in ((0, 1), (0, 2)):
        cross = _cross(x, *pair)[mask]
        phase = np.unwrap(np.angle(cross))
        slope = _weighted_slope(f, phase, np.abs(cross))
        dirs.append(slope * C_LIGHT / (2.0 * np.pi * spacing_m))
    return dirs[0], dirs[1]


ESTIMATORS = {
    "coherent_wpi": coherent_wpi,
    "single_bin": single_bin,
    "slope_ideal": slope_ideal,
    "slope_naive": slope_naive,
}
NEEDS_TRUTH = {"slope_ideal"}


def run_case(est, *, spacing_m, az, el, b_sig_hz, snr_db, trials, seed,
             cal_gain_db=0.0, cal_phase_deg=0.0, n_snapshots=1, f_offset_hz=0.0):
    rng = np.random.default_rng(seed)
    positions = array_2x2(spacing_m)
    u_true = unit_vector(az, el)
    f_bb = np.fft.fftshift(np.fft.fftfreq(N_FFT, 1.0 / FS_HZ))
    f_rf = RF_CENTER_HZ + f_bb
    cal = np.array([1.0, 10.0 ** (cal_gain_db / 20.0) * np.exp(1j * math.radians(cal_phase_deg)),
                    10.0 ** (-cal_gain_db / 20.0) * np.exp(-1j * math.radians(cal_phase_deg)),
                    1.0])[None, :, None]
    errs = []
    for _ in range(trials):
        x, mask = synth_spectra(rng, positions, u_true, f_bb, b_sig_hz, snr_db,
                                n_snapshots, f_offset_hz)
        x = x * cal
        uy, uz = ESTIMATORS[est](x, mask, f_rf, spacing_m,
                                 u_true if est in NEEDS_TRUTH else None)
        if not (np.isfinite(uy) and np.isfinite(uz)) or abs(uy) > 1.0 or abs(uz) > 1.0:
            errs.append(180.0)
            continue
        az_hat, el_hat = angles_from_direction(float(uy), float(uz))
        errs.append(math.hypot(az_hat - az, el_hat - el))
    errs = np.asarray(errs)
    return float(np.sqrt(np.mean(errs ** 2))), float(np.median(errs)), float(errs.max())


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quick", action="store_true", help="fewer Monte-Carlo trials")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    trials = 40 if args.quick else 150
    seed = 20261106

    lines: list[str] = []
    failures: list[str] = []

    def emit(text: str = "") -> None:
        print(text)
        lines.append(text)

    emit("V07 PHASE-INTERFEROMETRY REFERENCE CHECK")
    emit(f"generated      : {_dt.datetime.now(_dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}")
    emit(f"model          : 4 coherent channels, Fs={FS_HZ/1e9:.3f} GS/s, N_fft={N_FFT}, "
         f"F_C={RF_CENTER_HZ/1e9:.3f} GHz, bin={BIN_HZ/1e3:.3f} kHz")
    emit(f"trials per row : {trials}")
    emit("estimators     : coherent_wpi, single_bin, slope_ideal (oracle unwrap),")
    emit("                 slope_naive (external review code)")
    emit("SNR convention : PER-BIN SNR (one 122.07 kHz bin), flat noise density")
    emit("                 across the 2 GHz captured band")
    emit("")

    az, el = 12.5, -8.3
    narrow = 50e6

    # ---------------- CASE 1: narrowband emitter (build-kit waveform) -------
    emit("CASE 1  NARROWBAND 50 MHz emitter at 3.500 GHz, d = 25 mm, 20 dB/bin")
    emit("        (~410 occupied bins; matlab_v7 Source.BandwidthHz = 50e6)")
    emit("%-14s %12s %10s %10s" % ("estimator", "RMSE [deg]", "median", "max"))
    case1: dict[str, float] = {}
    for name in ("coherent_wpi", "single_bin", "slope_ideal", "slope_naive"):
        rmse, med, mx = run_case(name, spacing_m=0.025, az=az, el=el, b_sig_hz=narrow,
                                 snr_db=20.0, trials=trials, seed=seed, f_offset_hz=500e6)
        case1[name] = rmse
        emit("%-14s %12.3f %10.3f %10.1f" % (name, rmse, med, mx))
    emit("")

    # ---------------- CASE 2: wideband emitter ------------------------------
    emit("CASE 2  WIDEBAND 2.0 GHz emitter (fills the captured band), d = 25 mm, 20 dB/bin")
    emit("%-14s %12s %10s %10s" % ("estimator", "RMSE [deg]", "median", "max"))
    case2: dict[str, float] = {}
    for name in ("coherent_wpi", "slope_ideal", "slope_naive"):
        rmse, med, mx = run_case(name, spacing_m=0.025, az=az, el=el, b_sig_hz=2000e6,
                                 snr_db=20.0, trials=max(trials // 2, 20), seed=seed + 1)
        case2[name] = rmse
        emit("%-14s %12.3f %10.3f %10.1f" % (name, rmse, med, mx))
    emit("")

    # ---------------- CASE 3: SNR sweep -------------------------------------
    emit("CASE 3  per-bin SNR sweep, NARROWBAND 50 MHz at 3.500 GHz, d = 25 mm, RMSE [deg]")
    emit("%9s %14s %14s %14s" % ("dB/bin", "coherent_wpi", "single_bin", "slope_ideal"))
    for snr in (10.0, 15.0, 20.0, 25.0):
        row = [snr]
        for name in ("coherent_wpi", "single_bin", "slope_ideal"):
            r, _, _ = run_case(name, spacing_m=0.025, az=az, el=el, b_sig_hz=narrow,
                               snr_db=snr, trials=max(trials // 2, 20), seed=seed + 2,
                               f_offset_hz=500e6)
            row.append(r)
        emit("%9.1f %14.3f %14.3f %14.3f" % tuple(row))
    emit("")

    # ---------------- CASE 4: geometry / ambiguity --------------------------
    emit("CASE 4  GEOMETRY: 50 mm spacing at the 3.750 GHz band edge, az = 55 deg, BW = 50 MHz")
    emit("        unambiguous requires |sin(theta)| <= c/(2*f*d):  %.3f at 3.75 GHz, d = 50 mm"
         % (C_LIGHT / (2 * 3.75e9 * 0.050)))
    emit("                                                          %.3f at 3.75 GHz, d = 25 mm"
         % (C_LIGHT / (2 * 3.75e9 * 0.025)))
    emit("%-14s %16s %16s" % ("estimator", "RMSE d=50 mm", "RMSE d=25 mm"))
    case4 = {}
    for name in ("coherent_wpi", "slope_ideal"):
        r50, _, _ = run_case(name, spacing_m=0.050, az=55.0, el=0.0, b_sig_hz=narrow,
                             snr_db=20.0, trials=max(trials // 2, 20), seed=seed + 3,
                             f_offset_hz=750e6)
        r25, _, _ = run_case(name, spacing_m=0.025, az=55.0, el=0.0, b_sig_hz=narrow,
                             snr_db=20.0, trials=max(trials // 2, 20), seed=seed + 3,
                             f_offset_hz=750e6)
        case4[name] = (r50, r25)
        emit("%-14s %16.3f %16.3f" % (name, r50, r25))
    emit("")

    # ---------------- CASE 5: calibration residual --------------------------
    emit("CASE 5  CALIBRATION residual (coherent_wpi, narrowband, 20 dB/bin, d = 25 mm)")
    emit("%-34s %12s" % ("residual (CH2/CH3, opposite signs)", "RMSE [deg]"))
    case5 = {}
    for gain_db, phase_deg, label in ((0.0, 0.0, "none"),
                                      (0.2, 1.0, "0.2 dB / 1.0 deg"),
                                      (0.5, 3.0, "0.5 dB / 3.0 deg")):
        r, _, _ = run_case("coherent_wpi", spacing_m=0.025, az=az, el=el, b_sig_hz=narrow,
                           snr_db=20.0, trials=max(trials // 2, 20), seed=seed + 4,
                           cal_gain_db=gain_db, cal_phase_deg=phase_deg, f_offset_hz=500e6)
        case5[label] = r
        emit("%-34s %12.3f" % (label, r))
    emit("")

    # ---------------- CASE 6: snapshot averaging (hardware N) ---------------
    emit("CASE 6  SNAPSHOT averaging, coherent_wpi, narrowband 50 MHz, 10 dB/bin, d = 25 mm")
    emit("%10s %14s" % ("snapshots", "RMSE [deg]"))
    for n in (1, 8, 64):
        r, _, _ = run_case("coherent_wpi", spacing_m=0.025, az=az, el=el, b_sig_hz=narrow,
                           snr_db=10.0, trials=max(trials // 2, 20), seed=seed + 5,
                           n_snapshots=n, f_offset_hz=500e6)
        emit("%10d %14.3f" % (n, r))
    emit("")

    # ---------------- verdicts ---------------------------------------------
    emit("VERDICTS")
    v1 = case1["coherent_wpi"] < 0.5
    emit("  [%s] narrowband 50 MHz: coherent bin-summed WPI = %.3f deg (0.5 deg target)"
         % ("PASS" if v1 else "FAIL", case1["coherent_wpi"]))
    if not v1:
        failures.append("narrowband WPI accuracy")

    ratio = case1["slope_ideal"] / max(case1["coherent_wpi"], 1e-9)
    predicted = math.sqrt(12.0) * 3.5e9 / 50e6
    v2 = case1["slope_ideal"] > 20.0 * case1["coherent_wpi"]
    emit("  [%s] narrowband 50 MHz: even with oracle unwrap the slope fit is %.0fx worse "
         "(%.2f deg); theory predicts sqrt(12)*f_c/B = %.0fx"
         % ("PASS" if v2 else "FAIL", ratio, case1["slope_ideal"], predicted))
    if not v2:
        failures.append("slope-fit narrowband penalty")

    v3 = case2["slope_ideal"] > 2.0 * case2["coherent_wpi"]
    emit("  [%s] wideband 2 GHz: slope fit %.3f deg is %.1fx WORSE than coherent WPI "
         "%.3f deg; theory predicts sqrt(12)*f_c/B = %.1fx, so the 2 GHz bandwidth "
         "never becomes a lever arm for a known carrier"
         % ("PASS" if v3 else "FAIL", case2["slope_ideal"],
            case2["slope_ideal"] / max(case2["coherent_wpi"], 1e-9),
            case2["coherent_wpi"], math.sqrt(12.0) * 3.5e9 / 2.0e9))
    if not v3:
        failures.append("slope-fit wideband penalty")

    v4 = case2["slope_naive"] > 10.0 * case2["slope_ideal"]
    emit("  [%s] wideband 2 GHz: the review's literal unwrap+polyfit gives %.1f deg "
         "where the estimator is worth %.3f deg -> naive unwrap is not deployable"
         % ("PASS" if v4 else "FAIL", case2["slope_naive"], case2["slope_ideal"]))
    if not v4:
        failures.append("naive unwrap fragility")

    v5 = case4["coherent_wpi"][0] > 10.0 and case4["coherent_wpi"][1] < 1.0
    emit("  [%s] 50 mm at 3.75 GHz, az 55 deg: %.1f deg (ambiguous) vs %.3f deg at 25 mm"
         % ("PASS" if v5 else "FAIL", case4["coherent_wpi"][0], case4["coherent_wpi"][1]))
    if not v5:
        failures.append("50 mm geometry ambiguity")

    emit("")
    emit("RESULT=%s" % ("PASS" if not failures else "FAIL"))

    out_path = args.out or os.path.join(
        "docs", "evidence", "2026-11-06-phase-interf", "phase_interf_reference_check.txt")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\nreport written to %s" % out_path)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
