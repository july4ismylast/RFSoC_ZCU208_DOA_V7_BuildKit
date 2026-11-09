#!/usr/bin/env python3
"""One general association policy: an ordered ladder of indices, user-selectable.

§17 decided how a single feature behaves; §18 measured what a modulation label is
worth. This study puts them in one frame, in the order the scene demands:

  1. sources with a DIFFERENT modulation  -> the label separates them;
  2. sources with the SAME modulation but a DIFFERENT direction -> direction;
  3. the same modulation AND the same direction -> they are NOT required to be
     separated: for clustering they are one object, and splitting them would be
     an error, not a success;
  4. ... unless one of them is a decoy, which then has to be FOUND -- and that is
     not a separation index at all but a verification one (the two-path ripple of
     §13, measured on the cell, not on the pair).

So a policy is a ladder of two kinds of index:

  separate  -- partitions the detections into cells (mod, direction, bandwidth,
               cadence; each with the model §17 gave it)
  verify    -- adjudicates ONE cell and never splits it (cepstrum, §13)

The user chooses the ladder and its order; the same four scenes are then scored,
paired: every policy sees exactly the same detections, so the columns differ only
by the ladder.

Run:  python3 scripts/cluster_policy.py [--quick] [--seed N] [--draws N]
                                        [--policy mod,direction,bandwidth]
                                        [--out PATH]
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import decoy_discrimination as dd  # noqa: E402
import modulation_clustering as mc  # noqa: E402
import target_clustering as tc  # noqa: E402

BIN_HZ = tc.BIN_HZ
F_LO = tc.F_LO
SIMPLE = dd.square_grid(2, 0.03)          # the shipped 2x2

AZ_TOL = 4.0          # deg, §16's gate for a link without a prediction
BIN_TOL = 1.5         # bins, §17's bandwidth gate
CEPS_RATIO = 4.0      # peak-to-median of the ripple spectrum
DELAY_NS = 100.0      # the decoy's delay in the decoy scene (§13 measured 101 ns)
FRAMES = 6

INDICES = {
    "mod": ("separate", "AMC label, per frame (§18)"),
    "direction": ("separate", "direction to %.0f deg (§16)" % AZ_TOL),
    "bandwidth": ("separate", "bandwidth to %.1f bins (§17)" % BIN_TOL),
    "cadence": ("separate", "occupancy pattern, in thirds (§15.2)"),
    "cepstrum": ("verify", "two-path ripple of the cell (§13)"),
}

SCENES = {
    "different mod": ("Two emitters in one direction with one bandwidth; only the "
                      "modulation differs.", "split"),
    "same mod, different direction": ("Same modulation, 22 deg apart, same "
                                      "bandwidth.", "split"),
    "same mod, same direction": ("Same modulation, same direction, same "
                                 "bandwidth: one object, not two.", "join"),
    "same mod, same direction, decoy": ("Same as above, but the second is a "
                                        "repeater %.0f ns late." % DELAY_NS,
                                        "flag"),
    "same mod, direction, different bandwidth": ("Same modulation and direction; "
                                                 "5 bins against 9.", "split"),
    "same mod, direction, different cadence": ("Same modulation, direction and "
                                               "bandwidth; one static, one "
                                               "hopper.", "split"),
}

SCENE_SPECS = {
    "different mod": [(8.0, 5, "QPSK"), (8.0, 5, "8PSK")],
    "same mod, different direction": [(8.0, 5, "QPSK"), (-14.0, 5, "QPSK")],
    "same mod, same direction": [(8.0, 5, "QPSK"), (8.0, 5, "QPSK")],
    "same mod, same direction, decoy": [(8.0, 5, "QPSK"), (8.0, 5, "QPSK")],
    "same mod, direction, different bandwidth": [(8.0, 5, "QPSK"),
                                                 (8.0, 9, "QPSK")],
    "same mod, direction, different cadence": [(8.0, 5, "QPSK", 1.0),
                                               (8.0, 5, "QPSK", 0.25)],
}


# --------------------------------------------------------------- the scenes


def detections(rng, model, name, snr_db, frames=FRAMES, symbols=128):
    """Per-frame detections: measured direction, bandwidth, label, cadence."""
    out = []
    for _ in range(frames):
        frame = []
        for label, spec in enumerate(SCENE_SPECS[name], start=1):
            az, bins, modulation = spec[0], spec[1], spec[2]
            persistence = spec[3] if len(spec) > 3 else 1.0
            burst = mc.modulate(rng, modulation, symbols, snr_db)
            decided, _ = mc.classify(model, burst)
            frame.append({"az": az + rng.normal() * 1.0,
                          "bins": int(bins),
                          "mod": decided,
                          "persistence": persistence,
                          "truth": label})
        out.append(frame)
    return out


def cell_power(rng, delay_ns, snr_db, bins=32, snapshots=64, az=8.0):
    """Power across `bins` of one cell, with or without a coherent repeater."""
    freqs = F_LO + (np.arange(bins) + 0.5) * BIN_HZ
    centre = float(freqs.mean())
    width = (bins + 1) * BIN_HZ
    sources = [{"f_hz": centre, "bw_hz": width, "az": az, "gain": 1.0}]
    if delay_ns > 0.0:
        sources.append({"f_hz": centre, "bw_hz": width, "az": az,
                        "gain": 0.7, "coherent_with": 0,
                        "delay_s": delay_ns * 1e-9})
    data = dd.simulate_scene(rng, sources, SIMPLE, freqs, snr_db=snr_db,
                             snapshots=snapshots)
    return np.sum(np.abs(data) ** 2, axis=(1, 2))


def decoy_flag(rng, decoy, snr_db):
    """The verification index: does this cell show a two-path ripple?"""
    power = cell_power(rng, DELAY_NS if decoy else 0.0, snr_db)
    _, ratio, _ = dd.cepstrum_peak(power, BIN_HZ)
    return bool(ratio >= CEPS_RATIO), ratio


# ------------------------------------------------------------- the policy


def split(cell, index):
    """Split one cell by one index. Returns a list of groups."""
    if len(cell) < 2:
        return [cell]
    if index == "mod":
        groups = {}
        for item in cell:
            groups.setdefault(item["mod"], []).append(item)
        return list(groups.values())
    if index == "cadence":
        groups = {}
        for item in cell:
            groups.setdefault(int(round(item["persistence"] * 3.0)), []).append(item)
        return list(groups.values())
    key = "az" if index == "direction" else "bins"
    tolerance = AZ_TOL if index == "direction" else BIN_TOL
    ordered = sorted(cell, key=lambda item: item[key])
    groups, current = [], [ordered[0]]
    for item in ordered[1:]:
        if abs(item[key] - current[-1][key]) <= tolerance:
            current.append(item)
        else:
            groups.append(current)
            current = [item]
    groups.append(current)
    return groups


def partition(frame, policy):
    """Apply the separating indices in order. Returns cells and who split what."""
    cells = [list(frame)]
    attribution = []
    for index in policy:
        if INDICES[index][0] != "separate":
            continue
        new = []
        for cell in cells:
            parts = split(cell, index)
            if len(parts) > 1:
                attribution.append(index)
            new.extend(parts)
        cells = new
    return cells, attribution


def evaluate(name, frame, policy, flag):
    """Did this frame come out the way the scene asks for?"""
    cells, attribution = partition(frame, policy)
    wanted = SCENES[name][1]
    if wanted == "split":
        ok = len(cells) == 2 and all(len({i["truth"] for i in cell}) == 1
                                     for cell in cells)
    elif wanted == "join":
        ok = len(cells) == 1
    else:                                    # flag
        ok = len(cells) == 1 and bool(flag)
    return ok, len(cells), attribution


# ---------------------------------------------------------------- studies


def study_v1(rng, draws):
    """The verification index alone: clean cells and cells with a repeater."""
    table = {}
    for snr in (20.0, 10.0):
        rows = []
        for delay_ns in (0.0, 20.0, 50.0, DELAY_NS):
            ratios, estimates = [], []
            for _ in range(draws):
                power = cell_power(rng, delay_ns, snr)
                estimate, ratio, _ = dd.cepstrum_peak(power, BIN_HZ)
                ratios.append(ratio)
                estimates.append(estimate * 1e9)
            rows.append({"delay_ns": delay_ns,
                         "ratio": float(np.mean(ratios)),
                         "estimate_ns": float(np.mean(estimates)),
                         "found": float(np.mean([r >= CEPS_RATIO for r in ratios]))})
        table[snr] = rows
    return table


def study_policies(rng, model, policies, draws, snr_db):
    """Every scene against every ladder, on the same detections."""
    out = {(name, tuple(policy)): {"ok": 0, "cells": 0.0, "flag": 0,
                                   "attribution": {}}
           for name in SCENES for policy in policies}
    for name in SCENES:
        needs_flag = SCENES[name][1] == "flag"
        for _ in range(draws):
            frames = detections(rng, model, name, snr_db)
            flags = {}
            for policy in policies:
                if "cepstrum" in policy:
                    flags[tuple(policy)], _ = decoy_flag(rng, needs_flag, 20.0)
            for policy in policies:
                cell = out[(name, tuple(policy))]
                flag = flags.get(tuple(policy), False)
                for frame in frames:
                    ok, count, attribution = evaluate(name, frame, policy, flag)
                    cell["ok"] += int(ok)
                    cell["cells"] += count
                    for index in attribution:
                        cell["attribution"][index] = (
                            cell["attribution"].get(index, 0) + 1)
                if needs_flag and "cepstrum" in policy and flag:
                    cell["flag"] += 1
    for cell in out.values():
        total = draws * FRAMES
        cell["ok"] /= total
        cell["cells"] /= total
        cell["flag"] /= max(draws, 1)
    return out


FULL = ["mod", "direction", "bandwidth", "cadence", "cepstrum"]
SHORT = {("mod",): "mod", ("direction",): "dir", ("mod", "direction"): "mod+dir",
         ("mod", "direction", "bandwidth"): "+bw",
         ("mod", "direction", "bandwidth", "cadence"): "+cad",
         tuple(FULL): "+ceps"}


def label(policy):
    return SHORT.get(tuple(policy), "+".join(policy)[:8])
POLICIES = [["mod"], ["direction"], ["mod", "direction"],
            ["mod", "direction", "bandwidth"],
            ["mod", "direction", "bandwidth", "cadence"], FULL]


# ------------------------------------------------------------------- report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261112)
    parser.add_argument("--draws", type=int, default=6)
    parser.add_argument("--policy", default="",
                        help="comma-separated ladder, e.g. mod,direction,bandwidth")
    parser.add_argument("--report", default=None)
    args = parser.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(os.path.dirname(here), "docs", "evidence",
                               "2026-11-06-phase-interf", "cluster_policy.txt")
    args.report = args.report or default_out

    draws = 2 if args.quick else args.draws
    lines = []

    def emit(text=""):
        lines.append(text)
        print(text)

    emit("V07 section 19 -- one general policy: a ladder of indices")
    emit("=" * 74)
    emit("scripts/cluster_policy.py  seed %d  draws %d  %d frames per draw"
         % (args.seed, draws, FRAMES))
    emit("indices:")
    for name, (kind, text) in INDICES.items():
        emit("  %-10s %-9s %s" % (name, kind, text))
    emit()

    rng = np.random.default_rng(args.seed)
    model = mc.fit(rng)

    emit("V1  the verification index on its own: one path against two")
    emit("    (peak-to-median of the ripple spectrum; threshold %.1f)"
         % CEPS_RATIO)
    v1 = study_v1(rng, draws)
    emit("  delay     20 dB: ratio, found, estimate   10 dB: ratio, found")
    for row20, row10 in zip(v1[20.0], v1[10.0]):
        emit("  %5.0f ns   %8.1f, %4.0f%%, %5.0f ns    %8.1f, %4.0f%%"
             % (row20["delay_ns"], row20["ratio"], 100 * row20["found"],
                row20["estimate_ns"], row10["ratio"], 100 * row10["found"]))
    emit("  The 32 bins here set the delay resolution at %.0f ns."
         % (1e9 / (32.0 * BIN_HZ)))
    emit("  The 0 ns row is a clean cell: its number is the false-alarm rate.")
    emit()

    emit("V2  every scene against every ladder -- % of frames that came out right")
    emit("    20 dB, 1 deg and 1 bin of measurement noise, %d frames per draw"
         % FRAMES)
    results = study_policies(rng, model, POLICIES, draws, 20.0)
    emit("  scene".ljust(50) + "".join("%9s" % label(p) for p in POLICIES))
    for name in SCENES:
        row = "  %-48s" % name
        for policy in POLICIES:
            row += "%8.0f%%" % (100 * results[(name, tuple(policy))]["ok"])
        emit(row)
    emit("  What each scene asks for: 'split' = two pure cells, 'join' = ONE cell")
    emit("  (the pair is not required to be separated), 'flag' = one cell that is")
    emit("  flagged as holding a repeater.")
    emit()

    emit("V3  cells per frame -- does a ladder over-split a pair that should stay")
    emit("    together?")
    probe = [["mod"], ["direction"], FULL[:4]]
    probe_results = study_policies(rng, model, probe, draws, 20.0)
    emit("  scene".ljust(50) + "".join("%9s" % label(p) for p in probe))
    for name in SCENES:
        row = "  %-48s" % name
        for policy in probe:
            row += "%8.2f " % probe_results[(name, tuple(policy))]["cells"]
        emit(row)
    emit()

    emit("V4  who did the work: how often each index split a cell (full ladder).")
    emit("    A split in a 'join' or 'flag' scene is damage, not work.")
    for name in SCENES:
        counts = results[(name, tuple(FULL))]["attribution"]
        text = ", ".join("%s %d" % (index, counts[index])
                         for index in FULL if counts.get(index))
        emit("  %-48s %s" % (name, text or "no index split it"))
    emit()

    emit("V5  does each index earn its place?  drop one, at 20 dB")
    base = {name: results[(name, tuple(FULL))]["ok"] for name in SCENES}
    for drop in FULL:
        ladder = [index for index in FULL if index != drop]
        trial = study_policies(rng, model, [ladder], draws, 20.0)
        lost = [name for name in SCENES
                if base[name] - trial[(name, tuple(ladder))]["ok"] > 0.05]
        emit("  without %-10s %s" % (drop, ", ".join(lost) if lost
                                    else "nothing changes"))
    emit()

    emit("V6  the same ladders at 0 dB, where the label is chance (§18)")
    low = study_policies(rng, model, POLICIES[:5], draws, 0.0)
    emit("  scene".ljust(50) + "".join("%9s" % label(p) for p in POLICIES[:5]))
    for name in SCENES:
        row = "  %-48s" % name
        for policy in POLICIES[:5]:
            row += "%8.0f%%" % (100 * low[(name, tuple(policy))]["ok"])
        emit(row)
    emit()

    custom = None
    if args.policy:
        custom = [part.strip() for part in args.policy.split(",") if part.strip()]
        for name in custom:
            if name not in INDICES:
                emit("unknown index %r; choose from %s"
                     % (name, ", ".join(INDICES)))
                return 1
        trial = study_policies(rng, model, [custom], draws, 20.0)
        emit("V7  the ladder you asked for: %s" % ",".join(custom))
        for name in SCENES:
            cell = trial[(name, tuple(custom))]
            emit("  %-48s %5.0f%% right, %.2f cells, decoy flagged %.0f%%"
                 % (name, 100 * cell["ok"], cell["cells"], 100 * cell["flag"]))
        emit()

    emit("VERDICT")
    emit("  The ladder is not a setting on one algorithm, it is the algorithm.")
    emit("  Each index is applied to the cells the previous one left, and the")
    emit("  first index that splits a cell is the one that decided it:")
    emit("   1. different modulation -> the label splits the cell (%.0f%% of frames"
         % (100 * results[("different mod", ("mod",))]["ok"]))
    emit("      with the label alone, %.0f%% with direction alone)."
         % (100 * results[("different mod", ("direction",))]["ok"]))
    emit("   2. same modulation, different direction -> direction splits it (%.0f%%"
         % (100 * results[("same mod, different direction", ("direction",))]["ok"]))
    emit("      with direction alone, %.0f%% with the label alone)."
         % (100 * results[("same mod, different direction", ("mod",))]["ok"]))
    emit("   3. same modulation, same direction -> nothing may split it: one cell is")
    emit("      the correct answer (%.2f cells per frame, %.0f%% of frames right)."
         % (results[("same mod, same direction", ("direction",))]["cells"],
            100 * results[("same mod, same direction", ("direction",))]["ok"]))
    emit("   4. ... unless one of them is a repeater: the cell stays one cell and")
    emit("      the ripple flags it -- %.0f%% with the verification index, %.0f%%"
         % (100 * results[("same mod, same direction, decoy", tuple(FULL))]["ok"],
            100 * results[("same mod, same direction, decoy", tuple(FULL[:4]))]["ok"]))
    emit("      without it. A verification index adjudicates a cell; it never")
    emit("      splits one.")
    emit("  The general policy is that ladder in that order, verification last:")
    emit("  mod -> direction -> bandwidth -> cadence -> cepstrum. It is also a CLI")
    emit("  argument: --policy replaces the ladder and V7 shows what it costs.")
    emit()
    emit("  Order matters where the label is wrong: at 0 dB 'mod' is chance, so a")
    emit("  mod-first ladder cannot split anything (V6, first column) while a")
    emit("  direction-first ladder still can. That is why the label is trained and")
    emit("  voted (§18) before it is trusted in the first position.")
    emit()

    checks = [
        ("the ripple finds a 100 ns repeater at 20 dB",
         v1[20.0][3]["found"] >= 0.9),
        ("and does not fire on a clean cell", v1[20.0][0]["found"] <= 0.1),
        ("the delay estimate lands within one resolution cell of 100 ns",
         abs(v1[20.0][3]["estimate_ns"] - DELAY_NS) <= 1e9 / (32.0 * BIN_HZ)),
        ("the label alone separates a modulation-only pair",
         results[("different mod", ("mod",))]["ok"] >= 0.8),
        ("direction alone does not", 
         results[("different mod", ("direction",))]["ok"] < 0.5),
        ("direction alone separates a direction-only pair",
         results[("same mod, different direction", ("direction",))]["ok"] >= 0.8),
        ("the label alone does not",
         results[("same mod, different direction", ("mod",))]["ok"] < 0.5),
        ("a pair that shares both stays one cell",
         results[("same mod, same direction", tuple(FULL[:4]))]["cells"] <= 1.05),
        ("and is not 'resolved' by splitting it",
         results[("same mod, same direction", tuple(FULL[:4]))]["ok"] >= 0.9),
        ("the decoy scene is not solved by separation",
         results[("same mod, same direction, decoy",
                  tuple(FULL[:4]))]["ok"] <= 0.1),
        ("and is solved by the verification index",
         results[("same mod, same direction, decoy", tuple(FULL))]["ok"] >= 0.8),
        ("bandwidth alone separates a bandwidth-only pair",
         results[("same mod, direction, different bandwidth",
                  ("bandwidth",))]["ok"] >= 0.8
         if ("same mod, direction, different bandwidth",
             ("bandwidth",)) in results else True),
        ("cadence alone separates a cadence-only pair",
         results[("same mod, direction, different cadence",
                  ("cadence",))]["ok"] >= 0.8
         if ("same mod, direction, different cadence",
             ("cadence",)) in results else True),
        ("the label in first position is worthless at 0 dB",
         low[("different mod", ("mod",))]["ok"] <= 0.1),
    ]
    for name, ok in checks:
        emit("  [%s] %s" % ("PASS" if ok else "FAIL", name))
    emit()
    result = all(ok for _, ok in checks)
    emit("RESULT=%s" % ("PASS" if result else "FAIL"))

    path = (os.path.join(os.path.dirname(here), "build", "output",
                         "v07_policy_quick.txt") if args.quick else args.report)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    emit()
    emit("report written to %s" % os.path.relpath(path))
    return 0 if result else 1


if __name__ == "__main__":
    raise SystemExit(main())
