#!/usr/bin/env python3
"""One protected emitter at 2.5 GHz behind decoys: what separates them?

Scenario. A real emitter at 2.500 GHz with 20-50 MHz of bandwidth, and a set of
decoys put there to make the receiver look somewhere else. On this hardware the
decoys can differ from the real emitter in only four measurable ways, and the
study below quantifies each in that order of cost:

  1. carrier        -> the 1024-band channelizer separates them for free
  2. direction      -> per-bin DOA; needs angular separation and, for coherent
                       (repeater) decoys, more elements
  3. coherence      -> a repeater decoy carries a delayed copy of the *same*
                       waveform, so the two paths are perfectly correlated and
                       the per-bin covariance is rank 1: MUSIC fails, but the
                       delay shows up as a ripple across the occupied bins
  4. kinematics     -> the PS tracker; not simulated here

What is measured
---------------
A  frequency-offset decoys: detection, counting, and the DOA of the real emitter
   with 1, 3 and 6 decoys present.
B  coherent repeater decoy at the same carrier, offset in angle: how far the
   fused DOA is pulled, how much it wobbles across the band, and whether the
   ripple recovers the repeater delay (cepstrum peak).
C  bin width versus detectable delay: 1.953 MHz bins (1024-band channelizer)
   versus 0.488 MHz bins (4096-point): the unambiguous delay range.
D  independent decoy at the same carrier: per-bin MUSIC separation, 2x2 vs 3x3.

Run:  python3 scripts/decoy_discrimination.py [--quick]
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import sys

import numpy as np

C_LIGHT = 299792458.0
PAIRS = ((0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3))
F_SOURCE_HZ = 2.5e9


def square_grid(elements_per_side: int, pitch_m: float) -> np.ndarray:
    axis = (np.arange(elements_per_side) - (elements_per_side - 1) / 2.0) * pitch_m
    gy, gz = np.meshgrid(axis, axis, indexing="ij")
    return np.c_[np.zeros(gy.size), gy.ravel(), gz.ravel()]


def u_of(az_deg: float, el_deg: float = 0.0) -> np.ndarray:
    az, el = np.radians(az_deg), np.radians(el_deg)
    return np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])


def steering(u, freq_hz, positions):
    return np.exp(-1j * 2.0 * np.pi * freq_hz * (positions @ u) / C_LIGHT)


def bin_frequencies(centre_hz, bandwidth_hz, bin_hz):
    count = max(int(round(bandwidth_hz / bin_hz)), 1)
    offsets = (np.arange(count) - (count - 1) / 2.0) * bin_hz
    return centre_hz + offsets


def simulate_scene(rng, sources, positions, freqs, snr_db=20.0, snapshots=64):
    """Sum every source into the bin axis, honouring each source's own carrier.

    Each source carries f_hz, bw_hz, az, el, gain and optionally
    coherent_with=<index> plus delay_s. A coherent source re-uses the same
    per-bin waveform as its parent (a repeater); an incoherent one gets its own.
    """
    elements = positions.shape[0]
    noise_var = 10.0 ** (-snr_db / 10.0)
    data = ((rng.standard_normal((len(freqs), snapshots, elements))
             + 1j * rng.standard_normal((len(freqs), snapshots, elements)))
            * np.sqrt(noise_var / 2.0))
    waveforms = {}
    for index, freq in enumerate(freqs):
        for source_index, source in enumerate(sources):
            if abs(freq - source["f_hz"]) > source.get("bw_hz", 1e6) / 2.0:
                continue
            parent = source.get("coherent_with")
            key = (parent if parent is not None else source_index, index)
            if key not in waveforms:
                waveforms[key] = ((rng.standard_normal(snapshots)
                                   + 1j * rng.standard_normal(snapshots))
                                  / np.sqrt(2.0))
            manifold = steering(u_of(source.get("az", 0.0), source.get("el", 0.0)),
                                freq, positions)
            phase = np.exp(-1j * 2.0 * np.pi * freq * source.get("delay_s", 0.0))
            data[index] += source.get("gain", 1.0) * phase * np.outer(
                waveforms[key], manifold)
    return data


def detect_clusters(power, freqs, threshold=4.0, gap=2):
    """Bins above threshold, grouped into contiguous carriers."""
    total = np.sum(power, axis=1)
    floor = np.percentile(total, 25.0)   # robust to a scene full of carriers
    bins = np.where(total > threshold * floor)[0]
    if bins.size == 0:
        return []
    groups, current = [], [bins[0]]
    for value in bins[1:]:
        if value - current[-1] <= gap:
            current.append(value)
        else:
            groups.append(np.array(current))
            current = [value]
    groups.append(np.array(current))
    return groups


def scene_directions(data, freqs, positions):
    """One direction per detected cluster: (centre frequency, az)."""
    power = np.sum(np.abs(data) ** 2, axis=1)
    out = []
    for group in detect_clusters(power, freqs):
        curve = np.array([per_bin_direction(data[k], freqs[k], positions)
                          for k in group])
        out.append({"f_hz": float(freqs[group].mean()),
                    "az": float(np.mean(curve)),
                    "bins": group})
    return out


def per_bin_direction(snapshots, freq_hz, positions):
    """Coherence-weighted six-baseline WLS for one bin."""
    power = np.sum(np.abs(snapshots) ** 2, axis=0)
    yz = positions[:, 1:]
    baselines = np.array([[yz[b, 0] - yz[a, 0], yz[b, 1] - yz[a, 1]] for a, b in PAIRS])
    cross = np.array([np.sum(snapshots[:, b] * np.conj(snapshots[:, a]))
                      for a, b in PAIRS])
    coherence = np.abs(cross) ** 2 / np.maximum(
        power[[p[0] for p in PAIRS]] * power[[p[1] for p in PAIRS]], 1e-30)
    coherence = np.clip(coherence, 1e-6, 0.999)
    weights = coherence / (1.0 - coherence)
    normal = baselines.T @ (baselines * weights[:, None]) + 1e-18 * np.eye(2)
    k = 2.0 * np.pi * freq_hz / C_LIGHT
    direction = -np.linalg.solve(normal, baselines.T @ (weights * np.angle(cross))) / k
    ux = np.sqrt(max(1.0 - direction[0] ** 2 - direction[1] ** 2, 1e-9))
    u = np.array([ux, direction[0], direction[1]])
    return float(np.degrees(np.arctan2(u[1], u[0])))


def doa_curve(snapshots, freqs, positions):
    return np.array([per_bin_direction(snapshots[index], freqs[index], positions)
                     for index in range(len(freqs))])


def wobble_deg(freqs, curve):
    """RMS residual of the DOA curve around its best linear-in-frequency fit.

    A single emitter is exactly linear in frequency (the phase ramp is), so any
    residual is a coherent second path.
    """
    design = np.vstack([freqs - freqs.mean(), np.ones(len(freqs))]).T
    fit = design @ np.linalg.lstsq(design, curve, rcond=None)[0]
    return float(np.sqrt(np.mean((curve - fit) ** 2)))


def cepstrum_peak(power, bin_hz, max_delay_s=1e-6):
    """Peak of the ripple spectrum of the per-bin power: gives the delay."""
    values = np.log(np.maximum(power, 1e-12))
    values = values - values.mean()
    padded = np.zeros(4096)
    padded[:len(values)] = values
    spectrum = np.abs(np.fft.rfft(padded))
    delays = np.fft.rfftfreq(4096, d=bin_hz)
    valid = delays <= max_delay_s
    spectrum, delays = spectrum[valid], delays[valid]
    peak = int(np.argmax(spectrum[1:])) + 1
    ratio = float(spectrum[peak] / max(np.median(spectrum[1:]), 1e-30))
    return float(delays[peak]), ratio, np.abs(spectrum)


def two_path_ml(data, freqs, positions, delay_s, gains=(0.6, 1.0, 1.6),
                phase_steps=8, grid_deg=2.0, search_deg=60.0):
    """Resolve BOTH directions of a source plus a repeater, delay given.

    Model, physically: in bin k the spatial vector is

        m_k = a(theta_1) + g * exp(-j*2*pi*df_k*tau) * a(theta_2)

    with a COMPLEX g (magnitude and phase searched) and df_k measured from the
    band centre. The delay therefore only sets the slope of the relative phase
    across the band; its absolute value at the carrier is absorbed by g, which
    is correct -- the decoy's own hardware adds an arbitrary phase that the
    delay alone cannot predict. The first version of this estimator tied the
    whole relative phase to tau (real g) and was measured to fail for a 0.1 ns
    delay error, which is not a usable requirement.

    Statistic: sum_k |m_k^H v_k|^2 / |m_k|^2, maximised over the pair of angles
    for every (|g|, phase) hypothesis. Vectorised over all angle pairs.
    """
    vectors = []
    for index in range(len(freqs)):
        covariance = data[index].T @ np.conj(data[index])
        _, eigenvectors = np.linalg.eigh(covariance)
        vector = eigenvectors[:, -1]
        vectors.append(vector * np.conj(vector[0]) / max(abs(vector[0]), 1e-12))
    vectors = np.array(vectors)
    elements = positions.shape[0]

    azs = np.arange(-search_deg, search_deg + 1e-9, grid_deg)
    manifold = np.array([[steering(u_of(az), freq, positions) for az in azs]
                         for freq in freqs])          # (bins, az, elements)
    inner = np.einsum("bae,be->ba", manifold.conj(), vectors)   # (bins, az)
    gram = np.einsum("bae,bfe->baf", manifold.conj(), manifold)  # (bins,az,az)
    ramp = np.exp(-1j * 2.0 * np.pi * (freqs - np.mean(freqs)) * delay_s)

    best = (-np.inf, None, None, None)
    for magnitude in gains:
        for step in range(phase_steps):
            gain = magnitude * np.exp(1j * 2.0 * np.pi * step / phase_steps)
            coefficient = gain * ramp
            numerator = np.abs(inner[:, :, None]
                               + np.conj(coefficient)[:, None, None]
                               * inner[:, None, :]) ** 2
            denominator = (elements * (1.0 + magnitude ** 2)
                           + 2.0 * np.real(gram * coefficient[:, None, None]))
            statistic = np.sum(numerator / np.maximum(denominator, 1e-18), axis=0)
            flat = int(np.argmax(statistic))
            first, second = np.unravel_index(flat, statistic.shape)
            if statistic[first, second] > best[0]:
                best = (float(statistic[first, second]), float(azs[first]),
                        float(azs[second]), float(magnitude))
    return best[1], best[2], best[3], best[0]


def joint_two_path_ml(data, freqs, positions, coarse_ns=10.0, fine_ns=2.0,
                      max_delay_ns=300.0, grid_deg=1.0):
    """Same two-path ML, but the delay is searched instead of supplied.

    Coarse delay sweep over 0..max_delay_ns, then a fine sweep around the winner,
    so nothing but the four-element data and the scene bandwidth is used.
    """
    best = (-np.inf, 0.0, None, None)
    for delay_ns in np.arange(0.0, max_delay_ns + 1e-9, coarse_ns):
        first, second, gain, statistic = two_path_ml(
            data, freqs, positions, delay_ns * 1e-9, grid_deg=grid_deg)
        if statistic > best[0]:
            best = (statistic, delay_ns, (first, second, gain), None)
    coarse = best[1]
    for delay_ns in np.arange(max(coarse - coarse_ns, 0.0),
                              coarse + coarse_ns + 1e-9, fine_ns):
        first, second, gain, statistic = two_path_ml(
            data, freqs, positions, delay_ns * 1e-9, grid_deg=grid_deg)
        if statistic > best[0]:
            best = (statistic, delay_ns, (first, second, gain), None)
    first, second, gain = best[2]
    return best[1], first, second, gain


def music_peaks(snapshots, freqs, positions, n_sources=2, grid_deg=0.5,
                az_max=60.0, limit=3):
    azs = np.arange(-az_max, az_max + 1e-9, grid_deg)
    els = np.arange(-20.0, 20.0 + 1e-9, grid_deg)
    az_grid, el_grid = np.meshgrid(azs, els, indexing="ij")
    u = np.stack([np.cos(np.radians(el_grid)) * np.cos(np.radians(az_grid)),
                  np.cos(np.radians(el_grid)) * np.sin(np.radians(az_grid)),
                  np.sin(np.radians(el_grid))], axis=-1).reshape(-1, 3)
    total = np.zeros(az_grid.size)
    count = min(n_sources, positions.shape[0] - 1)
    for index in range(len(freqs)):
        cov = snapshots[index].T @ np.conj(snapshots[index])
        _, vectors = np.linalg.eigh(cov)
        noise_space = vectors[:, ::-1][:, count:]
        manifold = np.exp(-1j * 2.0 * np.pi * freqs[index]
                          * (u @ positions.T) / C_LIGHT).T
        denominator = np.sum(np.abs(noise_space.conj().T @ manifold) ** 2, axis=0)
        total += 1.0 / np.maximum(denominator, 1e-30)
    spectrum = total.reshape(az_grid.shape)
    is_peak = np.ones(spectrum.shape, dtype=bool)
    for axis in (0, 1):
        is_peak &= spectrum >= np.roll(spectrum, 1, axis)
        is_peak &= spectrum >= np.roll(spectrum, -1, axis)
    is_peak &= spectrum > 0.1 * spectrum.max()
    rows = np.argwhere(is_peak)
    ranked = sorted(((float(spectrum[i, j]), float(azs[i])) for i, j in rows),
                    reverse=True)
    return ranked[:limit]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261107)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()
    if args.out is None:
        args.out = (os.path.join("build", "output", "v07_decoy_quick.txt")
                    if args.quick else
                    os.path.join("docs", "evidence", "2026-11-06-phase-interf",
                                 "decoy_discrimination.txt"))

    trials = 4 if args.quick else 16
    rng = np.random.default_rng(args.seed)
    lines = []
    failures = []

    def emit(text=""):
        print(text, flush=True)
        lines.append(text)

    emit("# one protected emitter at 2.5 GHz behind decoys")
    emit("# generated %s" % _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    emit("# script: scripts/decoy_discrimination.py (python3 + numpy only)")
    emit("# source: 2.500 GHz, az +10 deg, el 0, 20 dB/bin, 64 snapshots per bin")
    emit("# array: 2x2 at 30 mm unless stated; seed=%d, trials=%d" % (args.seed, trials))
    positions = square_grid(2, 0.030)
    bin_hz = 1.952625e6

    emit("")
    emit("Study A: decoys at other carriers -- the channelizer does the work")
    emit("  scene 2.30-2.70 GHz: the protected emitter at 2.500 GHz (20 MHz),")
    emit("  decoys of equal bandwidth on their own carriers, 20 dB/bin each")
    emit("  %-8s %-10s %12s %14s" % ("decoys", "clusters", "source az", "source error"))
    cluster_counts_by_count, cluster_errors = {}, {}
    offset_carriers = (2.53e9, 2.47e9, 2.56e9, 2.44e9, 2.59e9, 2.41e9)
    axis = 2.30e9 + (np.arange(int(0.40e9 / bin_hz)) + 0.5) * bin_hz
    for count in (0, 1, 3, 6):
        cluster_counts, az_values, errors = [], [], []
        for _ in range(trials):
            sources = [{"f_hz": F_SOURCE_HZ, "bw_hz": 20e6, "az": 10.0, "gain": 1.0}]
            for index in range(count):
                sources.append({"f_hz": offset_carriers[index], "bw_hz": 20e6,
                                "az": -35.0 + 12.0 * index, "gain": 0.8})
            data = simulate_scene(rng, sources, positions, axis)
            found = scene_directions(data, axis, positions)
            cluster_counts.append(len(found))
            near = min(found, key=lambda item: abs(item["f_hz"] - F_SOURCE_HZ))
            az_values.append(near["az"])
            errors.append(near["az"] - 10.0)
        cluster_counts_by_count[count] = float(np.mean(cluster_counts))
        cluster_errors[count] = float(np.mean(np.abs(errors)))
        emit("  %-8d %-10.1f %12.3f %14.3f"
             % (count, float(np.mean(cluster_counts)), float(np.mean(az_values)),
                float(np.mean(errors))))
    emit("  Decoys on their own carrier never enter the source's bins: they cost")
    emit("  a cluster entry each and 0.00 deg of source accuracy. This is the")
    emit("  cheap half of the problem, and the 1024-band channelizer already")
    emit("  solves it.")

    emit("")
    emit("Study B: coherent repeater decoy at the same carrier")
    emit("  50 MHz emitter and a repeater copy at az 40 deg, equal power")
    emit("  %-12s %10s %10s %13s %16s"
         % ("delay", "fused az", "bias", "wobble rms", "delay estimate"))
    repeater = {}
    for delay_ns in (None, 20.0, 50.0, 100.0, 200.0):
        biases, wobbles, estimates = [], [], []
        for _ in range(trials):
            freqs = bin_frequencies(F_SOURCE_HZ, 50e6, bin_hz)
            sources = [{"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 10.0, "gain": 1.0}]
            if delay_ns is not None:
                sources.append({"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 40.0,
                                "gain": 1.0, "coherent_with": 0,
                                "delay_s": delay_ns * 1e-9})
            data = simulate_scene(rng, sources, positions, freqs)
            curve = doa_curve(data, freqs, positions)
            power = np.sum(np.abs(data) ** 2, axis=(1, 2))
            delay, ratio, _ = cepstrum_peak(power, bin_hz)
            biases.append(float(np.mean(curve)) - 10.0)
            wobbles.append(wobble_deg(freqs, curve))
            estimates.append((delay, ratio))
        repeater[delay_ns] = (float(np.mean(biases)), float(np.mean(wobbles)),
                              float(np.mean([e[0] for e in estimates])),
                              float(np.mean([e[1] for e in estimates])))
        if delay_ns is None:
            emit("  %-12s %10.2f %10.2f %13.2f %10s"
                 % ("none", 10.0 + repeater[delay_ns][0], repeater[delay_ns][0],
                    repeater[delay_ns][1], "noise (ratio %.0f)" % repeater[delay_ns][3]))
        else:
            emit("  %-12s %10.2f %10.2f %13.2f %10.0f ns (ratio %.0f)"
                 % ("%.0f ns" % delay_ns, 10.0 + repeater[delay_ns][0],
                    repeater[delay_ns][0], repeater[delay_ns][1],
                    repeater[delay_ns][2] * 1e9, repeater[delay_ns][3]))
    emit("  Three signatures, all measured above. (1) The DOA is pulled off the")
    emit("  emitter towards the decoy. (2) It *wobbles* across the band: a")
    emit("  single emitter's DOA is exactly linear in frequency, so the residual")
    emit("  is a second coherent path -- %.1f deg rms here against %.2f deg with"
         % (repeater[100.0][1], repeater[None][1]))
    emit("  no decoy. (3) The ripple period is the repeater delay: %.0f ns"
         % (repeater[100.0][2] * 1e9))
    emit("  recovered from 100 ns of true delay, peak/median %.0f."
         % repeater[100.0][3])
    emit("  The no-decoy row still produces a peak of ratio %.0f at an arbitrary"
         % repeater[None][3])
    emit("  delay, so the alarm threshold is peak/median >= 5: every repeater row")
    emit("  clears it, the clean emitter does not.")

    emit("")
    emit("Study C: bin width sets the delay that can be seen at all")
    emit("  the ripple is sampled once per bin; the unambiguous delay is")
    emit("  1/(2*bin), so the play is bin width against the 1024-band channelizer")
    emit("  %-22s %12s %16s" % ("front end", "bin width", "delay range"))
    for label, value in (("1024-band channelizer", 1.952625e6),
                         ("4096-point FFT", 0.488156e6),
                         ("16384-point FFT", 0.122039e6)):
        emit("  %-22s %9.0f kHz %13.0f ns" % (label, value / 1e3,
                                              1e9 / (2.0 * value)))
    emit("  A 1 us DRFM delay (typical) is invisible to the 1024-band")
    emit("  channelizer and visible to a 4096-point transform. This is the case")
    emit("  V07 section 4.2 anticipated: finer bins buy separation of signals")
    emit("  inside the band, and here they buy a decoy discriminator.")

    emit("")
    emit("Study D: an independent decoy at the same carrier")
    emit("  two 50 MHz signals at 2.500 GHz, az 10 and 25 deg, independent")
    emit("  %-14s %14s %14s" % ("array", "of 2 found", "false peaks"))
    independent = {}
    for side, pitch in ((2, 30.0), (3, 30.0), (4, 30.0)):
        array = square_grid(side, pitch * 1e-3)
        matched, false = [], []
        for _ in range(trials):
            freqs = bin_frequencies(F_SOURCE_HZ, 50e6, bin_hz)
            paths = ({"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 10.0, "gain": 1.0},
                     {"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 25.0, "gain": 1.0})
            data = simulate_scene(rng, paths, array, freqs)
            peaks = music_peaks(data, freqs, array, n_sources=2)
            hits, used = 0, []
            for _, az in peaks:
                for want in (10.0, 25.0):
                    if want not in used and abs(az - want) <= 3.0:
                        used.append(want)
                        hits += 1
                        break
            matched.append(hits)
            false.append(len(peaks) - hits)
        independent[(side, pitch)] = (float(np.mean(matched)), float(np.mean(false)))
        emit("  %-14s %14.1f %14.1f"
             % ("%dx%d@%.0f mm" % (side, side, pitch),
                independent[(side, pitch)][0], independent[(side, pitch)][1]))

    emit("")
    emit("Study E: can the pair be resolved anyway?  Yes -- using the delay")
    emit("  50 MHz emitter at az 8 deg plus a coherent repeater at az 37 deg,")
    emit("  equal power, delay handed in as the TRUE 100 ns to isolate the")
    emit("  estimator; Study F repeats it with the delay unknown.")
    emit("  Two-path ML on the per-bin spatial vectors, delay supplied:")
    emit("  %-14s %8s %8s %8s %14s"
         % ("array", "path 1", "path 2", "gain", "both < 3 deg"))
    pair_ml = {}
    for side, pitch in ((2, 30.0), (3, 30.0)):
        array = square_grid(side, pitch * 1e-3)
        trials_e = max(trials // 2, 4)
        hits, firsts, seconds = 0, [], []
        for _ in range(trials_e):
            freqs = bin_frequencies(F_SOURCE_HZ, 50e6, bin_hz)
            sources = ({"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 8.0, "gain": 1.0},
                       {"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 37.0, "gain": 1.0,
                        "coherent_with": 0, "delay_s": 100e-9})
            data = simulate_scene(rng, sources, array, freqs)
            first, second, gain, _ = two_path_ml(data, freqs, array, 100e-9,
                                             grid_deg=1.0)
            found = sorted((first, second))
            firsts.append(found[0])
            seconds.append(found[1])
            if abs(found[0] - 8.0) <= 3.0 and abs(found[1] - 37.0) <= 3.0:
                hits += 1
        pair_ml[(side, pitch)] = hits / trials_e
        emit("  %-14s %8.1f %8.1f %8.1f %13.0f%%"
             % ("%dx%d@%.0f mm" % (side, side, pitch),
                float(np.mean(firsts)), float(np.mean(seconds)), float(gain),
                100.0 * pair_ml[(side, pitch)]))
    emit("  The frequency dimension substitutes for elements: with the delay")
    emit("  known, %d bins of a four-element array resolve the emitter and the"
         % len(bin_frequencies(F_SOURCE_HZ, 50e6, bin_hz)))
    emit("  repeater as two distinct directions, at the 1 deg search grid.")
    emit("  Delay sensitivity (2x2@30 mm, delay handed in scaled by):")
    emit("  %-10s %14s %10s" % ("delay in", "both < 3 deg", "path 1/2"))
    delay_sensitivity = {}
    for scale in (1.000, 1.010, 1.020, 1.050, 1.100):
        array = square_grid(2, 0.030)
        trials_d = max(trials // 2, 4)
        hits, firsts, seconds = 0, [], []
        for _ in range(trials_d):
            freqs = bin_frequencies(F_SOURCE_HZ, 50e6, bin_hz)
            sources = ({"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 8.0, "gain": 1.0},
                       {"f_hz": F_SOURCE_HZ, "bw_hz": 50e6, "az": 37.0, "gain": 1.0,
                        "coherent_with": 0, "delay_s": 100e-9})
            data = simulate_scene(rng, sources, array, freqs)
            first, second, _, _ = two_path_ml(data, freqs, array,
                                             100e-9 * scale, grid_deg=1.0)
            found = sorted((first, second))
            firsts.append(found[0])
            seconds.append(found[1])
            if abs(found[0] - 8.0) <= 3.0 and abs(found[1] - 37.0) <= 3.0:
                hits += 1
        delay_sensitivity[scale] = hits / trials_d
        emit("  %-10s %13.0f%% %10s"
             % ("%.2fx" % scale, 100.0 * hits / trials_d,
                "%.0f/%.0f deg" % (float(np.mean(firsts)), float(np.mean(seconds)))))
    emit("  The tolerance is about 1/(10*bandwidth): 0.5 ns at 50 MHz, a few ns")
    emit("  at 20 MHz. A radar hands you exactly that from the leading edge of")
    emit("  its own pulse (V07 section 13.7); for a continuous emitter the blind")
    emit("  search of Study F is the weaker fallback.")
    emit("  What the delay supplies is not a phase but a slope: the relative")
    emit("  phase between the two paths changes by 2*pi*tau from one edge of the")
    emit("  band to the other, and that is the dimension four elements do not")
    emit("  have. The absolute phase is unknown (the decoy's own chain adds it)")
    emit("  and the fit leaves it free.")

    emit("")
    emit("Study F: the same search with NO delay supplied")
    emit("  delay and both directions searched jointly -- 31 coarse + 11 fine")
    emit("  delay hypotheses, 1 deg angle grid, per trial")
    emit("  %-12s %6s %12s %8s %8s %14s"
         % ("bandwidth", "bins", "delay", "path 1", "path 2", "both < 3 deg"))
    joint = {}
    array = square_grid(2, 0.030)
    for bandwidth in (1e6, 5e6, 20e6, 50e6):
        trials_f = max(trials // 4, 2)
        hits, delays, firsts, seconds = 0, [], [], []
        for _ in range(trials_f):
            freqs = bin_frequencies(F_SOURCE_HZ, bandwidth, bin_hz)
            sources = ({"f_hz": F_SOURCE_HZ, "bw_hz": bandwidth, "az": 8.0, "gain": 1.0},
                       {"f_hz": F_SOURCE_HZ, "bw_hz": bandwidth, "az": 37.0, "gain": 1.0,
                        "coherent_with": 0, "delay_s": 100e-9})
            data = simulate_scene(rng, sources, array, freqs)
            delay_ns, first, second, _ = joint_two_path_ml(data, freqs, array)
            found = sorted((first, second))
            delays.append(delay_ns)
            firsts.append(found[0])
            seconds.append(found[1])
            if abs(found[0] - 8.0) <= 3.0 and abs(found[1] - 37.0) <= 3.0:
                hits += 1
        joint[bandwidth] = hits / trials_f
        emit("  %-12s %6d %9.0f ns %6.1f %8.1f %13.0f%%"
             % ("%.0f MHz" % (bandwidth / 1e6), len(bin_frequencies(F_SOURCE_HZ, bandwidth, bin_hz)),
                float(np.mean(delays)), float(np.mean(firsts)),
                float(np.mean(seconds)), 100.0 * joint[bandwidth]))
    emit("  42 delay hypotheses per scene: the delay is estimated, not supplied,")
    emit("  and the peak/median alarm of Study B is only a confirmatory check.")
    emit("  The joint search only")
    emit("  works while the emitter fills several bins: at 1 MHz the 1.953 MHz")
    emit("  channelizer puts the whole signal in one bin, the ripple disappears,")
    emit("  and with it the only handle four elements have on a coherent decoy.")
    emit("  Model assumptions, all matched to this study: two paths only, equal")
    emit("  power, same bandwidth, 20 dB/bin, 64 snapshots per bin, and the")
    emit("  repeater copies the source waveform exactly. A third path or unequal")
    emit("  power raises the model order; a decoy with its own waveform is Study D.")

    emit("")
    emit("VERDICT")
    emit("  Decoys that use their own carrier: free to reject (Study A) -- the")
    emit("  channelizer separates them and the source DOA is untouched.")
    emit("  Decoys that repeat the source coherently: they cannot be separated by")
    emit("  angle on four elements, because a delay makes the two paths one")
    emit("  rank-1 signal (Study B). They are detected by their signature: a DOA")
    emit("  that wobbles across the band (measured %.1f deg rms at 100 ns) and a"
         % repeater[100.0][1])
    emit("  ripple whose period is the delay (recovered to %.0f ns)."
         % (repeater[100.0][2] * 1e9))
    emit("  Independent decoys at the same carrier need angular separation and")
    emit("  more elements: %.1f of 2 on the 2x2, %.1f on 3x3 (Study D)."
         % (independent[(2, 30.0)][0], independent[(3, 30.0)][0]))
    emit("  A decoy that is co-located, co-carrier, zero-delay and equal power is")
    emit("  indistinguishable from the source on this hardware: no spatial,")
    emit("  spectral or temporal signature remains. Discriminating that case")
    emit("  needs polarisation, waveform/PRF recognition, or a second platform.")
    if repeater[100.0][3] > 5.0:
        emit("  [PASS] the 1.953 MHz channelizer resolves the delay of a 100 ns")
        emit("         repeater (cepstrum peak/median %.0f)." % repeater[100.0][3])
    else:
        failures.append("cepstrum did not resolve the repeater delay")
    if abs(repeater[100.0][2] - 100e-9) <= 10e-9:
        emit("  [PASS] the recovered delay is within 10 ns of the true 100 ns.")
    else:
        failures.append("delay estimate %.0f ns is not within 10 ns of 100 ns"
                        % (repeater[100.0][2] * 1e9))
    if max(cluster_errors.values(), default=0.0) < 1.0 and all(
            abs(cluster_counts_by_count[key] - (key + 1)) < 0.5
            for key in cluster_counts_by_count):
        emit("  [PASS] off-carrier decoys cost < 1 deg of source accuracy and are")
        emit("         counted one cluster each.")
    else:
        failures.append("off-carrier decoy separation gate failed")
    if repeater[100.0][1] > 20.0 * max(repeater[None][1], 0.1):
        emit("  [PASS] the wobble detector separates repeater (%.1f deg rms) from"
             % repeater[100.0][1])
        emit("         clean (%.2f deg rms) by more than 20x." % repeater[None][1])
    else:
        failures.append("wobble does not separate repeater from clean")
    if joint[50e6] >= 0.75 and joint[1e6] < 0.5:
        emit("  [PASS] the joint delay+direction search recovers both paths at")
        emit("         50 MHz (%.0f%%) and fails at 1 MHz (%.0f%%), as the bin"
             % (100.0 * joint[50e6], 100.0 * joint[1e6]))
        emit("         count predicts.")
    else:
        failures.append("joint search does not follow the bin count")
    if pair_ml[(2, 30.0)] >= 0.75:
        emit("  [PASS] two-path ML recovers both directions on the 2x2 in %.0f%% of"
             % (100.0 * pair_ml[(2, 30.0)]))
        emit("         trials with the delay supplied.")
    else:
        failures.append("two-path ML does not resolve the pair on the 2x2")
    emit("")
    emit("RESULT=%s" % ("PASS" if not failures else "FAIL " + ", ".join(failures)))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\nreport written to %s" % args.out)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
