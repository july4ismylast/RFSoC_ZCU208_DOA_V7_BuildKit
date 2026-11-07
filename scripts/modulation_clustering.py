#!/usr/bin/env python3
"""What you cluster on when the MODULATION is what stays constant.

§17 settled the rule: a feature is usable for association when its change per
frame is far below its measurement error. Modulation is the odd case -- it does
not drift and it does not jitter, it *is* a mode. So the question is not "how
well is it measured" but "how often is the label right", and the answer decides
whether an automatic modulation classifier (AMC) can be a clustering feature.

What is measured here, on synthetic I/Q (rectangular pulses, 4 samples/symbol,
complex AWGN at a stated per-sample SNR):

  M1  AMC accuracy per modulation against SNR, for a 1024-sample burst.
  M2  the same against burst length, at 10 dB.
  M3  the confusion matrix at 10 dB -- which pairs are hopeless.
  M4  label stability over frames: single frame vs a 3- and 5-frame vote.
  M5  clustering three emitters where two share direction AND bandwidth and
      differ only in modulation: no modulation, per-frame label, voted label.
  M6  the limit: two emitters with the SAME modulation are not separated by a
      perfect classifier, because the label carries no information about them.

The classifier is deliberately boring -- seven features and a nearest class mean
trained at 20 dB -- because the point is what a feature *is worth*, not the state
of the art. Assumed available: the burst is already isolated in its frequency
bin, and the residual carrier offset is a small fraction of the symbol rate.

Run:  python3 scripts/modulation_clustering.py [--quick] [--seed N]
                                                [--draws N] [--out PATH]
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import target_clustering as tc  # noqa: E402

BIN_HZ = tc.BIN_HZ
SPS = 4                      # samples per symbol
MODS = ("BPSK", "QPSK", "8PSK", "16QAM", "4FSK")
FEATURES = ("|C40|", "C42", "sigma_ap", "gamma_max", "freq_std", "spike")


# ------------------------------------------------------------- the signals


def symbols(rng, mod, count):
    """Unit-average-power symbols for one modulation."""
    if mod == "BPSK":
        return rng.choice([-1.0, 1.0], count) + 0j
    if mod == "QPSK":
        return (rng.choice([-1.0, 1.0], count)
                + 1j * rng.choice([-1.0, 1.0], count)) / np.sqrt(2.0)
    if mod == "8PSK":
        phase = 2.0 * np.pi * rng.integers(0, 8, count) / 8.0
        return np.exp(1j * phase)
    if mod == "16QAM":
        levels = np.array([-3.0, -1.0, 1.0, 3.0]) / np.sqrt(10.0)
        return rng.choice(levels, count) + 1j * rng.choice(levels, count)
    if mod == "4FSK":
        # deviation chosen so that one symbol advances the phase by a
        # quarter turn at the outer tone: 4 levels, unit power.
        level = rng.integers(0, 4, count) - 1.5     # -1.5, -0.5, 0.5, 1.5
        return level.astype(float)
    raise ValueError(mod)


def modulate(rng, mod, n_symbols, snr_db=20.0, sps=SPS, cfo=0.0):
    """One burst: symbols repeated over `sps` samples, and complex AWGN.

    `cfo` is the residual carrier as a fraction of the SAMPLE rate; the default
    is 0 because the burst is assumed carrier-recovered (study M1b measures what
    a residual offset costs).
    """
    if mod == "4FSK":
        level = symbols(rng, mod, n_symbols)
        step = 2.0 * np.pi * 0.25 * level / sps      # rad per sample
        phase = np.cumsum(np.repeat(step, sps))
        base = np.exp(1j * phase)
    else:
        base = np.repeat(symbols(rng, mod, n_symbols), sps)
    if cfo:
        base = base * np.exp(2j * np.pi * cfo * np.arange(base.size))
    base = base * np.exp(2j * np.pi * rng.random())
    amplitude = 10.0 ** (-snr_db / 20.0)
    noise = (rng.normal(size=base.size) + 1j * rng.normal(size=base.size))
    return base + amplitude * noise / np.sqrt(2.0)


# -------------------------------------------------------------- AMC features


def features(x):
    """Six cheap features: cumulants, amplitude moments, phase-increment ones."""
    power = np.mean(np.abs(x) ** 2) + 1e-30
    c20 = np.mean(x ** 2) / power
    c40 = abs(np.mean(x ** 4) - 3.0 * c20 ** 2) / power
    c42 = float(np.mean(np.abs(x) ** 4) / power ** 2)

    amplitude = np.abs(x)
    mean_a = amplitude.mean() + 1e-30
    sigma_ap = float(amplitude.std() / mean_a)
    centred = amplitude / mean_a - 1.0
    spectrum = np.abs(np.fft.fft(centred)) ** 2
    gamma_max = float(spectrum.max() / max(centred.size, 1))

    phase = np.unwrap(np.angle(x))
    step = np.diff(phase) / (2.0 * np.pi)            # cycles per sample
    freq_std = float(np.std(step) * SPS)             # normalised by symbol rate
    spike = float(np.mean(np.abs(step) * SPS > 0.25))
    return np.array([c40, c42, sigma_ap, gamma_max, freq_std, spike])


def fit(rng, train_snrs=(0.0, 5.0, 10.0, 15.0, 20.0, 25.0), n_symbols=256,
        draws=30):
    """Nearest class mean on standardised features, trained over an SNR range.

    Training over the range, not at one SNR, is the whole difference between a
    classifier that works below its training point and one that does not: see
    study M0.
    """
    table = []
    for mod in MODS:
        rows = np.array([features(modulate(rng, mod, n_symbols, snr))
                         for snr in train_snrs for _ in range(draws)])
        table.append(rows)
    stacked = np.vstack(table)
    centre = stacked.mean(axis=0)
    spread = stacked.std(axis=0) + 1e-12
    means = {mod: (np.array(table[i]).mean(axis=0) - centre) / spread
             for i, mod in enumerate(MODS)}
    return means, centre, spread


def classify_from_features(model, vector):
    """Label and the margin to the runner-up, from the six features.

    Shared with the R5 firmware port (scripts/amc_port_check.py): the same
    expression runs on both sides of the comparison.
    """
    means, centre, spread = model
    z = (np.asarray(vector, dtype=float) - centre) / spread
    scores = {mod: float(np.linalg.norm(z - mean)) for mod, mean in means.items()}
    order = sorted(scores.items(), key=lambda item: item[1])
    return order[0][0], order[1][1] - order[0][1]


def classify(model, x):
    """Label and the margin to the runner-up (both in z-units)."""
    return classify_from_features(model, features(x))


def accuracy(model, rng, mod, snr_db, n_symbols, draws):
    hits = 0
    for _ in range(draws):
        label, _ = classify(model, modulate(rng, mod, n_symbols, snr_db))
        hits += int(label == mod)
    return hits / draws


# --------------------------------------------------------------- clustering


def scene(rng, model, modulation, az, bins, snr_db, frames=8, n_symbols=256):
    """Per-frame clusters over three emitters, two of them coincident."""
    specs = [{"az": az[0], "bins": bins[0], "mod": modulation[0]},
             {"az": az[1], "bins": bins[1], "mod": modulation[1]},
             {"az": az[2], "bins": bins[2], "mod": modulation[2]}]
    out = []
    for frame_index in range(frames):
        clusters = []
        for label, spec in enumerate(specs, start=1):
            burst = modulate(rng, spec["mod"], n_symbols, snr_db)
            measured, margin = classify(model, burst)
            clusters.append({"az": spec["az"] + rng.normal() * 1.0,
                             "bin": int(spec["bins"]),
                             "bins": int(spec["bins"]), "f_hz": 1e9,
                             "truth": label, "mod": measured, "margin": margin})
        out.append(clusters)
    return out, specs


def link_with(frame_list, key, rng):
    """§15's link(), with the modulation label added as a flat term.

    The detections are shuffled inside every frame: their order is not a feature,
    and leaving it sorted would let a stable tie-break masquerade as identity.
    """
    per_frame = []
    for frame in frame_list:
        order = rng.permutation(len(frame))
        per_frame.append([{**frame[i], "mod": frame[i]["mod"] if key else None}
                          for i in order])
    bins = [[cluster["bins"] for cluster in frame] for frame in per_frame]
    if key is None:
        return tc.link(per_frame, bins, rule="direction+bandwidth",
                       az_scale=4.0, bin_scale=1.5)
    return tc.link(per_frame, bins, rule="direction+bandwidth",
                   az_scale=4.0, bin_scale=1.5, mod_weight=1.0,
                   mod_vote=(key == "vote"))


def score(tracks, min_frames=2):
    """Tracks, emitters covered by a mature track, and purity of those tracks."""
    mature = [t for t in tracks if len(t["members"]) >= min_frames]
    if not mature:
        return len(tracks), 0, 0.0
    purity, total, covered = 0.0, 0, set()
    for track in mature:
        tags = [member["truth"] for member in track["members"]]
        values, counts = np.unique(tags, return_counts=True)
        purity += counts.max()
        total += len(tags)
        owner = int(values[np.argmax(counts)])
        if counts.max() >= 0.75 * len(tags):
            covered.add(owner)
    return len(tracks), len(covered), purity / total


# ----------------------------------------------------------------- studies


def study_m0(rng, draws):
    """One training SNR against the whole range, measured below the range."""
    single = fit(rng, train_snrs=(20.0,))
    wide = fit(rng, train_snrs=(0.0, 5.0, 10.0, 15.0, 20.0, 25.0))
    snrs = (0.0, 5.0, 10.0)
    out = {}
    for name, model in (("trained at 20 dB", single), ("trained 0-25 dB", wide)):
        out[name] = [float(np.mean([accuracy(model, rng, mod, snr, 256, draws)
                                    for mod in MODS])) for snr in snrs]
    out["snrs"] = snrs
    return out


def study_m1(rng, model, draws, quick):
    snrs = (0.0, 5.0, 10.0, 20.0)
    table = {}
    for mod in MODS:
        table[mod] = [accuracy(model, rng, mod, snr, 256, draws) for snr in snrs]
    return snrs, table


def study_m1b(rng, model, draws):
    """What a residual carrier costs: the same burst with a rotating phase."""
    offsets = (0.0, 1e-4, 1e-3)
    table = {}
    for mod in MODS:
        cells = []
        for offset in offsets:
            hits = 0
            for _ in range(draws):
                burst = modulate(rng, mod, 256, 20.0, cfo=offset)
                label, _ = classify(model, burst)
                hits += int(label == mod)
            cells.append(hits / draws)
        table[mod] = cells
    return offsets, table


def study_m2(rng, model, draws):
    lengths = (8, 16, 32, 64, 128)
    table = {}
    for mod in MODS:
        table[mod] = [accuracy(model, rng, mod, 10.0, n, draws) for n in lengths]
    return lengths, table


def study_m3(rng, model, draws):
    matrix = np.zeros((len(MODS), len(MODS)))
    for i, mod in enumerate(MODS):
        for j, decided in enumerate(MODS):
            hits = 0
            for _ in range(draws):
                label, _ = classify(model, modulate(rng, mod, 256, 0.0))
                hits += int(label == decided)
            matrix[i, j] = hits / draws
    return matrix


def study_m4(rng, model, draws, frames=8):
    """A constant emitter over `frames` frames: accuracy, and how the label flips.

    The vote is not there to raise accuracy -- with a *biased* classifier more
    frames cannot help. It is there to make the emitted label sticky, which is
    what a track needs.
    """
    out = {}
    for snr in (5.0, 10.0, 20.0):
        cells = []
        for window in (1, 3):
            hits, flips = 0, 0
            for _ in range(draws):
                for mod in MODS:
                    emitted = []
                    for _ in range(frames):
                        labels = [classify(model,
                                           modulate(rng, mod, 256, snr))[0]
                                  for _ in range(window)]
                        votes = {}
                        for value in labels:
                            votes[value] = votes.get(value, 0) + 1
                        emitted.append(max(votes.items(),
                                           key=lambda item: item[1])[0])
                    hits += sum(1 for value in emitted if value == mod)
                    flips += sum(1 for a, b in zip(emitted, emitted[1:])
                                 if a != b)
            cells.append((hits / (draws * len(MODS) * frames),
                          flips / (draws * len(MODS) * (frames - 1))))
        out[snr] = cells
    return out


def study_m5(rng, model, draws):
    """Two emitters coincide in direction and bandwidth; only the mod differs."""
    az = (8.0, -12.0, -12.0)
    bins = (6, 5, 5)
    out = {}
    for snr in (20.0, 10.0, 0.0):
        # emitters 2 and 3 share (az, bins); only their modulation differs --
        # or, in the second row, does not.
        for name, modulation in (("different mod", ("BPSK", "QPSK", "8PSK")),
                                 ("same mod", ("QPSK", "QPSK", "QPSK"))):
            rows = []
            for key in (None, "mod", "vote"):
                collected = []
                for _ in range(3 * draws):
                    frames, _ = scene(rng, model, modulation, az, bins, snr)
                    collected.append(score(link_with(frames, key, rng),
                                          min_frames=3))
                rows.append((key or "off",
                             float(np.mean([r[0] for r in collected])),
                             float(np.mean([r[1] for r in collected])),
                             float(np.mean([r[2] for r in collected]))))
            out[(snr, name)] = rows
    return out


# ------------------------------------------------------------------- report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261111)
    parser.add_argument("--draws", type=int, default=8)
    parser.add_argument("--out", default=None)
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.join(os.path.dirname(here), "docs", "evidence",
                           "2026-11-06-phase-interf", "modulation_clusters.txt")
    parser.add_argument("--report", default=default)
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    draws = 3 if args.quick else args.draws
    lines = []

    def emit(text=""):
        lines.append(text)
        print(text)

    emit("V07 section 18 -- what you cluster on when the modulation is the constant")
    emit("=" * 74)
    emit("scripts/modulation_clustering.py  seed %d  draws %d" % (args.seed, draws))
    emit("AMC: 6 features, nearest class mean trained over 0-25 dB, 256 symbols")
    emit("(1024 samples); SNR is per sample, complex AWGN.")
    emit()

    emit("M0  what does the TRAINING set cost?  (mean accuracy over the five mods)")
    m0 = study_m0(rng, draws)
    emit("  training            " + "".join("%9.0f dB" % s for s in m0["snrs"]))
    for name in ("trained at 20 dB", "trained 0-25 dB"):
        emit("  %-18s" % name + "".join("%11.0f%%" % (100 * v) for v in m0[name]))
    emit()

    model = fit(rng)

    emit("M1  does the label survive noise?   (1024-sample burst, accuracy per mod)")
    snrs, m1 = study_m1(rng, model, draws, args.quick)
    emit("  mod       " + "".join("%8.0f dB" % s for s in snrs))
    for mod in MODS:
        emit("  %-8s  " % mod + "".join("%11.0f%%" % (100 * v) for v in m1[mod]))
    emit()

    emit("M1b is the carrier recovered?   (20 dB, residual offset per sample)")
    offsets, m1b = study_m1b(rng, model, draws)
    emit("  mod       " + "".join("%12s" % ("%.0e" % o) for o in offsets))
    for mod in MODS:
        emit("  %-8s  " % mod + "".join("%11.0f%%" % (100 * v) for v in m1b[mod]))
    emit()

    emit("M2  does a longer burst help?       (10 dB, accuracy against symbols)")
    lengths, m2 = study_m2(rng, model, draws)
    emit("  mod       " + "".join("%9d" % n for n in lengths) + "   symbols")
    for mod in MODS:
        emit("  %-8s  " % mod + "".join("%9.0f%%" % (100 * v) for v in m2[mod]))
    emit()

    emit("M3  which pairs are hopeless?       (0 dB, % in the column's decision)")
    matrix = study_m3(rng, model, draws)
    emit("  truth     " + "".join("%7s" % mod for mod in MODS))
    for i, mod in enumerate(MODS):
        emit("  %-8s  " % mod + "".join("%7.0f%%" % (100 * v) for v in matrix[i]))
    emit()

    emit("M4  is the label stable over frames?  (constant emitter, k-frame vote)")
    m4 = study_m4(rng, model, draws)
    emit("  SNR       one frame: accuracy, flips   3-vote: accuracy, flips")
    for snr, cells in m4.items():
        emit("  %5.0f dB  %16.0f%%,  %4.2f   %16.0f%%,  %4.2f"
             % (snr, 100 * cells[0][0], cells[0][1],
                100 * cells[1][0], cells[1][1]))
    emit()

    emit("M5  two emitters share direction AND bandwidth, differ only in modulation")
    emit("    az 8 and -12 deg, 6 and 5 bins; 8 frames; tracked with and without")
    emit("    the label.  covered = emitters with a >=75% pure track (of 3)")
    m5 = study_m5(rng, model, draws)
    for (snr, name), rows in m5.items():
        emit("  %4.0f dB, %-13s" % (snr, name))
        for key, tracks, covered, purity in rows:
            emit("    %-6s tracks %5.2f   covered %.2f   purity %.2f"
                 % (key, tracks, covered, purity))
    emit()

    emit("M6  the limit: with the SAME modulation a classifier says nothing")
    emit("    (the 'same mod' rows above: covered stays where it was, at every SNR,")
    emit("    because the label of two emitters is the same label).")
    emit()

    emit("VERDICT")
    same = {snr: [r for (s, n), rows in m5.items() if s == snr and n == "same mod"
                  for r in rows] for snr in (20.0, 10.0, 0.0)}
    diff = {snr: [r for (s, n), rows in m5.items() if s == snr and n == "different mod"
                  for r in rows] for snr in (20.0, 10.0, 0.0)}
    emit("  Modulation is a MODE, not a value. It does not drift, it does not")
    emit("  jitter: it *is* a class, and it changes only when the emitter")
    emit("  reconfigures. So the rule of V07 17 applies with a different error:")
    emit("  the error of a label is a probability, not a degree.")
    emit("   - the label is right %.0f%% of frames at 20 dB, %.0f%% at 10 dB and"
         % (100 * np.mean([m1[m][3] for m in MODS]),
            100 * np.mean([m1[m][2] for m in MODS])))
    emit("     %.0f%% at 0 dB -- which is chance for five classes."
         % (100 * np.mean([m1[m][0] for m in MODS])))
    emit("   - a vote cannot fix a biased classifier, only a random one: at 5 dB")
    emit("     it moves the accuracy %.0f%% -> %.0f%% and the flips %.2f -> %.2f per"
         % (100 * m4[5.0][0][0], 100 * m4[5.0][1][0],
            m4[5.0][0][1], m4[5.0][1][1]))
    emit("     frame. It buys stability, not truth.")
    emit("   - two emitters that share direction and bandwidth and differ only in")
    emit("     modulation are separated at 20 dB (covered %.2f of 3 with the label,"
         % diff[20.0][1][2])
    emit("     %.2f without) and at 10 dB (%.2f against %.2f), and not at 0 dB"
         % (diff[20.0][0][2], diff[10.0][1][2], diff[10.0][0][2]))
    emit("     (%.2f with against %.2f without)." % (diff[0.0][1][2], diff[0.0][0][2]))
    emit("   - two emitters with the SAME modulation are never separated by AMC:")
    emit("     covered %.2f of 3 with the label at 20 dB against %.2f without."
         % (same[20.0][1][2], same[20.0][0][2]))
    emit("  So AMC enters the cost as a MODE term with a vote, after direction and")
    emit("  bandwidth, and only where they fail. It is an identity aid, not an")
    emit("  authenticator: an emitter that switches modulation switches its own")
    emit("  label, and a decoy that copies the waveform copies the label with it.")
    emit()

    checks = [
        ("training across SNR beats training at one point",
         m0["trained 0-25 dB"][1] > m0["trained at 20 dB"][1] + 0.15),
        ("the four linear modulations are separable at 10 dB",
         min(m1[mod][2] for mod in ("BPSK", "QPSK", "8PSK", "16QAM")) >= 0.9),
        ("4FSK is separable from the linear set at 10 dB", m1["4FSK"][2] >= 0.9),
        ("at 0 dB the label is chance", np.mean([m1[mod][0] for mod in MODS]) < 0.4),
        ("128 symbols are enough at 10 dB",
         min(m2[mod][4] for mod in MODS) >= 0.9),
        ("8 symbols are not", min(m2[mod][0] for mod in MODS) < 0.9),
        ("the 3-frame vote reduces the label flips",
         m4[5.0][1][1] < m4[5.0][0][1]),
        ("a residual carrier of 1e-3 rotates the 4th-order cumulant away",
         min(m1b["BPSK"][2], m1b["QPSK"][2]) < 0.5),
        ("the label separates two coincident emitters at 20 dB",
         diff[20.0][1][2] > diff[20.0][0][2] + 1.0),
        ("and at 10 dB", diff[10.0][1][2] > diff[10.0][0][2]),
        ("and does nothing at 0 dB",
         diff[0.0][1][2] <= diff[0.0][0][2] + 0.5),
        ("the same modulation buys nothing at 20 dB",
         same[20.0][1][2] <= same[20.0][0][2] + 0.3),
        ("tracks stay pure when the label is right",
         diff[20.0][1][3] >= 0.95),
    ]
    for name, ok in checks:
        emit("  [%s] %s" % ("PASS" if ok else "FAIL", name))
    emit()
    result = all(ok for _, ok in checks)
    emit("RESULT=%s" % ("PASS" if result else "FAIL"))

    path = (os.path.join(os.path.dirname(here), "build", "output",
                         "v07_modulation_quick.txt") if args.quick
            else args.report)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    emit()
    emit("report written to %s" % os.path.relpath(path))
    return 0 if result else 1


if __name__ == "__main__":
    raise SystemExit(main())
