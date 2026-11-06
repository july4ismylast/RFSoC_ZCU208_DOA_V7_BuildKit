#!/usr/bin/env python3
"""How many emitters can this kit locate, and at what accuracy, over 2-4 GHz?

V07 section 11 settled a *single* emitter (30 mm square 2x2, 0.066 deg over the
band). This script answers the follow-up: eight emitters inside a 2 GHz band.

What is measured
----------------
Per-bin incoherent 2D MUSIC (ISSM): one covariance per channelizer bin, one 2D
pseudo-spectrum per bin, spectra summed over the band, then the strongest local
maxima are taken as the source set and matched to the truth within 6 deg. This
is the standard wideband multi-source estimator, and it is the *generous* case
for the hardware because every bin is allowed its own narrowband MUSIC.

Arrays are square grids on a 2x2 / 3x3 / 4x4 / 5x5 / 6x6 lattice at 30 mm,
60 mm and 75 mm pitch, with the whole 2-4 GHz band captured.  The three
questions are separated on purpose:

  * elements   -> can the array represent N sources at all (rank, M-1 bound)
  * aperture   -> can it resolve them (Rayleigh at the *low* edge of the band)
  * pitch      -> does the array stay unambiguous (d*sqrt(2)*sin(theta)<=lambda/2
                  for a square grid) and does 2 GHz of bandwidth rescue a
                  pitch that a narrowband system could not use

Run:  python3 scripts/multisource_capacity.py [--quick]
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import sys

import numpy as np

C_LIGHT = 299792458.0
F_LOW_HZ, F_HIGH_HZ = 2.0e9, 4.0e9
BINS = 48                      # 42 MHz bins across the captured band
PAIRS = ((0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3))

# Eight emitters spread over the forward field, with distinct elevations so the
# 2D manifold is exercised (a fixed-elevation slice is rank deficient on a 2x2).
SOURCES_8 = (
    (-40.3, -11.6), (-27.6, 4.4), (-17.2, 10.3), (-5.7, -3.4),
    (6.4, 11.7), (16.8, -9.2), (28.3, 2.6), (39.6, -13.7),
)


def square_grid(elements_per_side: int, pitch_m: float) -> np.ndarray:
    axis = (np.arange(elements_per_side) - (elements_per_side - 1) / 2.0) * pitch_m
    gy, gz = np.meshgrid(axis, axis, indexing="ij")
    return np.c_[np.zeros(gy.size), gy.ravel(), gz.ravel()]


def u_of(az_deg: float, el_deg: float) -> np.ndarray:
    az, el = np.radians(az_deg), np.radians(el_deg)
    return np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])


def simulate(rng, sources, positions, snr_db=20.0, snapshots=96, bins=BINS):
    """Per-bin snapshots, one independent complex amplitude per source per bin."""
    frequencies = np.linspace(F_LOW_HZ, F_HIGH_HZ, bins)
    noise_var = 10.0 ** (-snr_db / 10.0)
    elements = positions.shape[0]
    out = np.zeros((bins, snapshots, elements), dtype=complex)
    for index, freq in enumerate(frequencies):
        manifold = np.stack([np.exp(-1j * 2.0 * np.pi * freq
                                    * (positions @ u_of(az, el)) / C_LIGHT)
                             for az, el in sources], axis=1)
        signal = (rng.standard_normal((len(sources), snapshots))
                  + 1j * rng.standard_normal((len(sources), snapshots))) / np.sqrt(2.0)
        noise = (rng.standard_normal((snapshots, elements))
                 + 1j * rng.standard_normal((snapshots, elements))) * np.sqrt(noise_var / 2.0)
        out[index] = (manifold @ signal).T + noise
    return out, frequencies


def music_spectrum(cov, freq_hz, n_sources, positions, azs, els):
    n_sources = min(n_sources, cov.shape[0] - 1)     # cannot exceed M-1
    az_grid, el_grid = np.meshgrid(azs, els, indexing="ij")
    u = np.stack([np.cos(np.radians(el_grid)) * np.cos(np.radians(az_grid)),
                  np.cos(np.radians(el_grid)) * np.sin(np.radians(az_grid)),
                  np.sin(np.radians(el_grid))], axis=-1).reshape(-1, 3)
    manifold = np.exp(-1j * 2.0 * np.pi * freq_hz * (u @ positions.T) / C_LIGHT).T
    _, vectors = np.linalg.eigh(cov)
    noise_space = vectors[:, ::-1][:, n_sources:]
    denominator = np.sum(np.abs(noise_space.conj().T @ manifold) ** 2, axis=0)
    return (1.0 / np.maximum(denominator, 1e-30)).reshape(az_grid.shape)


def issm(snapshots, frequencies, n_sources, positions, azs, els, bin_stride=1):
    total = None
    for index in range(0, len(frequencies), bin_stride):
        cov = snapshots[index].T @ np.conj(snapshots[index])
        spectrum = music_spectrum(cov, frequencies[index], n_sources, positions,
                                  azs, els)
        total = spectrum if total is None else total + spectrum
    return total


def local_maxima(spec, azs, els, limit, floor_ratio=0.02):
    """Local maxima with parabolic sub-grid refinement in both axes."""
    is_peak = np.ones(spec.shape, dtype=bool)
    for axis in (0, 1):
        is_peak &= spec >= np.roll(spec, 1, axis)
        is_peak &= spec >= np.roll(spec, -1, axis)
    is_peak &= spec > floor_ratio * spec.max()
    step_az = azs[1] - azs[0]
    step_el = els[1] - els[0]
    peaks = []
    for i, j in np.argwhere(is_peak):
        az, el = float(azs[i]), float(els[j])
        if 0 < i < spec.shape[0] - 1:
            denominator = spec[i - 1, j] - 2 * spec[i, j] + spec[i + 1, j]
            if abs(denominator) > 1e-30:
                az += 0.5 * (spec[i - 1, j] - spec[i + 1, j]) / denominator * step_az
        if 0 < j < spec.shape[1] - 1:
            denominator = spec[i, j - 1] - 2 * spec[i, j] + spec[i, j + 1]
            if abs(denominator) > 1e-30:
                el += 0.5 * (spec[i, j - 1] - spec[i, j + 1]) / denominator * step_el
        peaks.append((float(spec[i, j]), az, el))
    peaks.sort(reverse=True)
    return peaks[:limit]


def match(peaks, truth, tolerance_deg=6.0, accurate_deg=2.0):
    """Greedy nearest-neighbour matching.

    Returns (hits within tolerance, rms over the *accurately* matched peaks).
    The two thresholds are separated so a wrong-but-nearby peak cannot be
    counted as accuracy: 'detected' is generous, 'RMSE' is strict.
    """
    remaining = list(truth)
    hits, accurate = 0, []
    for _, az, el in peaks:
        if not remaining:
            break
        distances = [np.hypot(az - t[0], el - t[1]) for t in remaining]
        best = int(np.argmin(distances))
        distance = distances[best]
        if distance <= tolerance_deg:
            hits += 1
            remaining.pop(best)
            if distance <= accurate_deg:
                accurate.append(distance)
    return hits, (float(np.sqrt(np.mean(np.square(accurate)))) if accurate else float("nan"))


def manifold_rank(positions, freq_hz=3.0e9, points=61):
    """Rank of span{a(az,el)} over the 2D field: how many emitters fit."""
    azs = np.linspace(-60.0, 60.0, points)
    els = np.linspace(-25.0, 25.0, 25)
    columns = [np.exp(-1j * 2.0 * np.pi * freq_hz * (positions @ u_of(az, el)) / C_LIGHT)
               for az in azs for el in els]
    singular = np.linalg.svd(np.array(columns).T, compute_uv=False)
    singular = singular / singular[0]
    return int(np.sum(singular > 1e-3)), singular


def ambiguity_cone_deg(pitch_mm, freq_hz=F_HIGH_HZ):
    ratio = C_LIGHT / (2.0 * np.sqrt(2.0) * freq_hz * pitch_mm * 1e-3)
    return 90.0 if ratio >= 1.0 else float(np.degrees(np.arcsin(ratio)))


def rayleigh_deg(elements_per_side, pitch_mm, freq_hz):
    aperture = (elements_per_side - 1) * pitch_mm * 1e-3
    if aperture <= 0.0:
        return 180.0
    return float(np.degrees(1.22 * C_LIGHT / (freq_hz * aperture)))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261107)
    parser.add_argument("--out", default=None,
                        help="report path; defaults to the evidence directory for a "
                             "full run and to build/output for --quick")
    args = parser.parse_args()
    if args.out is None:
        args.out = (os.path.join("build", "output", "v07_multisource_quick.txt")
                    if args.quick else
                    os.path.join("docs", "evidence", "2026-11-06-phase-interf",
                                 "multisource_capacity.txt"))

    trials = 4 if args.quick else 12
    rng = np.random.default_rng(args.seed)
    lines = []
    failures = []

    def emit(text=""):
        print(text, flush=True)
        lines.append(text)

    emit("# multi-source capacity over the 2-4 GHz captured band")
    emit("# generated %s" % _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    emit("# script: scripts/multisource_capacity.py (python3 + numpy only)")
    emit("# estimator: per-bin incoherent 2D MUSIC (ISSM), spectra summed over %d bins," % BINS)
    emit("#            strongest local maxima matched to truth within 6 deg")
    emit("# sources: 8 emitters, az -40..40 deg, el -14..12 deg, 20 dB/bin each,")
    emit("#          N=96 snapshots per bin, seed=%d, trials=%d" % (args.seed, trials))
    emit("# convention: a(u,f) = exp(-j*2*pi*f*(p.u)/c), positions on a square grid")

    emit("")
    emit("Study 0: what the geometry allows, before any estimator")
    emit("  %-10s %8s %9s %10s %10s %10s"
         % ("array", "elements", "M-1", "manifold", "cone@4GHz", "Rayleigh"))
    arrays = ((2, 30.0), (3, 30.0), (4, 30.0), (4, 60.0), (5, 60.0), (6, 75.0))
    geometry = {}
    for side, pitch in arrays:
        positions = square_grid(side, pitch * 1e-3)
        rank, _ = manifold_rank(positions)
        cone = ambiguity_cone_deg(pitch)
        rayleigh_low = rayleigh_deg(side, pitch, F_LOW_HZ)
        geometry[(side, pitch)] = (positions.shape[0], rank, cone, rayleigh_low)
        emit("  %dx%d@%-4.0f %8d %9d %10d %9.0f d %9.1f d"
             % (side, side, pitch, positions.shape[0], positions.shape[0] - 1,
                rank, cone, rayleigh_low))
    emit("  M-1 is the hard identifiability bound, 'manifold' is the measured rank of")
    emit("  span{a(az,el)} over the field (the number of emitters a subspace method")
    emit("  can represent at 3 GHz), 'Rayleigh' is 1.22*lambda/D at the 2 GHz edge.")

    emit("")
    emit("Study 1: eight emitters over the full 2-4 GHz band")
    emit("  %-10s %8s %11s %10s %14s"
         % ("array", "detected", "of 8", "trials", "RMSE (matched)"))
    azs = np.arange(-60.0, 60.0 + 1e-9, 1.0)
    els = np.arange(-40.0, 40.0 + 1e-9, 1.0)
    results = {}
    for side, pitch in arrays:
        positions = square_grid(side, pitch * 1e-3)
        detected, errors, found_all = 0, [], 0
        for _ in range(trials):
            snapshots, frequencies = simulate(rng, SOURCES_8, positions)
            spec = issm(snapshots, frequencies, len(SOURCES_8), positions, azs, els)
            peaks = local_maxima(spec, azs, els, len(SOURCES_8))
            hits, error = match(peaks, SOURCES_8)
            detected += hits
            found_all += 1 if hits == len(SOURCES_8) else 0
            if not np.isnan(error):
                errors.append(error)
        results[(side, pitch)] = (detected / trials, found_all,
                                  float(np.mean(errors)) if errors else float("nan"))
        emit("  %dx%d@%-4.0f %8.1f %11d %10d %14s"
             % (side, side, pitch, detected / trials, found_all, trials,
                ("%.3f deg" % results[(side, pitch)][2]) if errors else "n/a"))
    emit("  'detected' is the mean number of the eight sources matched within 6 deg;")
    emit("  'of 8' counts trials in which all eight were found; RMSE uses only")
    emit("  peaks matched within 2 deg, so a near-miss cannot flatter it.")

    emit("")
    emit("Study 2: bandwidth or aperture?  Eight emitters, two arrays, two bands.")
    emit("  %-18s %-10s %12s %12s" % ("array", "band", "detected of 8", "RMSE"))

    def run_band(side, pitch, band_hz, trial_count):
        positions = square_grid(side, pitch * 1e-3)
        bins = 12 if band_hz < 1e9 else BINS
        frequencies = np.linspace(3.0e9 - band_hz / 2.0, 3.0e9 + band_hz / 2.0, bins)
        hits_total, errors = 0, []
        for _ in range(trial_count):
            snapshots = np.zeros((bins, 96, positions.shape[0]), dtype=complex)
            noise_var = 10.0 ** (-20.0 / 10.0)
            for index, freq in enumerate(frequencies):
                manifold = np.stack([np.exp(-1j * 2.0 * np.pi * freq
                                            * (positions @ u_of(az, el)) / C_LIGHT)
                                     for az, el in SOURCES_8], axis=1)
                signal = (rng.standard_normal((8, 96))
                          + 1j * rng.standard_normal((8, 96))) / np.sqrt(2.0)
                noise = (rng.standard_normal((96, positions.shape[0]))
                         + 1j * rng.standard_normal((96, positions.shape[0]))) \
                    * np.sqrt(noise_var / 2.0)
                snapshots[index] = (manifold @ signal).T + noise
            spec = issm(snapshots, frequencies, 8, positions, azs, els)
            hits, error = match(local_maxima(spec, azs, els, 8), SOURCES_8)
            hits_total += hits
            if not np.isnan(error):
                errors.append(error)
        return hits_total / trial_count, (
            float(np.mean(errors)) if errors else float("nan"))

    comparison = {}
    for side, pitch in ((4, 30.0), (4, 60.0)):
        for label, band_hz in (("600 MHz", 600e6), ("2 GHz", 2.0e9)):
            detected, error = run_band(side, pitch, band_hz, trials)
            comparison[(side, pitch, label)] = (detected, error)
            emit("  %-18s %-10s %12.1f %11.3f d"
                 % ("%dx%d@%.0f mm" % (side, side, pitch), label, detected, error))
    emit("  Resolution is set by aperture and by the *low* edge of the band: a")
    emit("  narrower band costs detection only through noise averaging (here 8x")
    emit("  fewer bins). Bandwidth pays off through the frequency ramp that")
    emit("  rejects aliases (V07 section 11), not through finer resolution.")

    emit("")
    emit("VERDICT")
    two_by_two = results[(2, 30.0)]
    six_by_six = results[(6, 75.0)]
    four_by_four = results[(4, 60.0)]
    if two_by_two[0] < 2.0:
        emit("  [PASS] the shipped 2x2 finds %.1f of 8 emitters: 4 elements cannot"
             % two_by_two[0])
        emit("         represent 8 sources. Single-emitter accuracy does not transfer.")
    else:
        failures.append("2x2 unexpectedly resolved many sources")

    if four_by_four[1] == trials:
        emit("  [PASS] 4x4 at 60 mm (16 elements, 180 mm aperture) found all eight")
        emit("         emitters in %d of %d trials." % (four_by_four[1], trials))
    else:
        emit("  [INFO] 4x4 at 60 mm found %.1f of 8 on average (%d of %d trials full)"
             % (four_by_four[0], four_by_four[1], trials))

    if six_by_six[0] >= 7.0:
        emit("  [PASS] 6x6 at 75 mm found %.1f of 8: 36 elements and a 375 mm"
             % six_by_six[0])
        emit("         aperture are enough for eight emitters over 2-4 GHz.")
    else:
        failures.append("6x6 did not resolve eight emitters")

    emit("")
    emit("  ANSWER: for one emitter the kit's per-bin phase interferometry is the")
    emit("  right estimator and reaches the numbers in V07 section 11 (0.066 deg")
    emit("  wideband, 0.252 deg narrowband at 30 mm over 2-4 GHz, CRB-limited).")
    emit("  Eight emitters is a different machine: >= 9 elements for identifiability")
    emit("  and, at these separations, 16-36 elements with a 240-375 mm aperture;")
    emit("  per-bin incoherent 2D MUSIC separates them, and their angular accuracy")
    emit("  is set by the aperture and the low band edge, not by the 2 GHz bandwidth.")
    emit("")
    emit("RESULT=%s" % ("PASS" if not failures else "FAIL " + ", ".join(failures)))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\nreport written to %s" % args.out)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
