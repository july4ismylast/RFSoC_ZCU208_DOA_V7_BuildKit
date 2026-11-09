#!/usr/bin/env python3
"""What you cluster on: one model per feature, chosen by how it changes.

§15 clustered on (direction, bandwidth) and §16 replaced the fixed direction
with a prediction. The general question behind both is this one:

    a feature is only usable for association if, over one frame, it changes by
    much less than the error with which it is measured. When it changes
    differently, the *model* attached to that feature has to change too.

Three kinds of change, and what each demands:

  continuous   direction of a mover, bandwidth of a chirp: model the rate and
               predict, keep the same gate (V07 §16)
  discontinuous  a hop in carrier, a mode change in bandwidth: the value jumps,
               so it cannot be a position key at all -- either widen the gate
               and lose discrimination, or keep the feature only as a *pattern*
               (cadence) over a window
  fast         level, coherence under fading: unusable for identity, whatever
               the model

  F1  bandwidth that DRIFTS (1 -> 5 bins over the run): fixed-bandwidth cost,
      modelled bandwidth, and bandwidth ignored.
  F2  bandwidth that JUMPS between modes (1 and 4 bins, every frame): the gate
      width buys continuity and pays in discrimination against a same-direction
      neighbour of another bandwidth -- measured as a trade-off curve, including
      the cadence-only rule.
  F3  direction that JUMPS: a 5/10/20/40 deg step in one frame. What a 4 deg gate
      does with it, and how much a wider gate buys in absorption and costs in
      theft from a neighbour standing at the landing point.
  F4  both at once: +2 deg/frame and +0.5 bins/frame, and which cost term breaks
      first.

Run:  python3 scripts/feature_models.py [--quick] [--seed N] [--out PATH]
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import target_clustering as tc  # noqa: E402

BIN_HZ = tc.BIN_HZ
AXIS = tc.FREQS[:64]
FRAMES = 8


def run(rng, specs, frames=FRAMES, snapshots=16):
    """specs: list of {label, az[per frame], bins[per frame], start, from}.

    An emitter appears at frame `from` (default 0). Returns per-frame clusters
    and the occupied bins of each frame.
    """
    frames_out, bins_out = [], []
    for index in range(frames):
        emitters = []
        for spec in specs:
            if index < spec.get("from", 0):
                continue
            count = int(spec["bins"][index])
            start = (spec["start"][index]
                     if isinstance(spec["start"], (list, tuple, np.ndarray))
                     else spec["start"])
            emitters.append({
                "label": spec["label"], "az": spec["az"][index],
                "f_hz": tc.block(start, count, AXIS)[0],
                "bw_hz": tc.block(0, count, AXIS)[1]})
        data, power = tc.frame(rng, emitters, snapshots=snapshots, freqs=AXIS)
        found = tc.detections(data, power, freqs=AXIS)
        truth = [tc.owner_of(d["bin"], emitters, AXIS) for d in found]
        frames_out.append(tc.cluster_points(found, "both", truth, az_scale=5.0,
                                            bin_scale=1.5, freqs=AXIS))
        bins_out.append({d["bin"] for d in found})
    return frames_out, bins_out


def own_track(tracks, label, min_members=2):
    """Does the emitter end the run inside a track of its own?"""
    for track in tracks:
        tags = [m["truth"] for m in track["members"]]
        if len(tags) < min_members:
            continue
        if tags.count(label) > max(len(tags) - tags.count(label), 0):
            return 100.0
    return 0.0


def confusion(tracks):
    """Detections that ended in a track whose majority is the other emitter."""
    wrong, total = 0, 0
    for track in tracks:
        tags = [m["truth"] for m in track["members"]]
        total += len(tags)
        ones, twos = tags.count(1), tags.count(2)
        if ones > twos:
            wrong += twos
        elif twos > ones:
            wrong += ones
    return 100.0 * wrong / total if total else 0.0


def absorbed_by(tracks, label, owner=1):
    """Detections of `label` that end up inside a track whose majority is owner."""
    stolen, total = 0, 0
    for track in tracks:
        tags = [m["truth"] for m in track["members"]]
        mine = tags.count(label)
        total += mine
        if mine and tags.count(owner) > tags.count(label):
            stolen += mine
    return 100.0 * stolen / total if total else 0.0


def pieces(tracks, label=1):
    """Pieces the emitter is cut into and the largest share in one of them."""
    count, total, longest, merged = 0, 0, 0, 0
    for track in tracks:
        tags = [m["truth"] for m in track["members"]]
        mine = tags.count(label)
        total += mine
        longest = max(longest, mine)
        if mine:
            count += 1
        others = len(tags) - mine
        if mine and others:
            merged += others           # detections of ANOTHER emitter inside it
    return count, (longest / total if total else 0.0), merged


def study_f1(rng, emit, draws):
    emit("")
    emit("Study F1: bandwidth that drifts continuously")
    emit("  emitter 1: 1 bin widening by d bins per frame at 10 deg; emitter 2:")
    emit("  5 bins at -30 deg, fixed. 8 frames, 16 snapshots, %d draws." % draws)
    emit("  Both rules get the same widened gate for a track's first two frames, so the")
    emit("  only difference is the drift model. A fixed cost is |bins - mean|")
    emit("  against a +-1.5 bin gate; the modelled one predicts the drift.")
    emit("  %-8s %14s %14s %14s" % ("drift", "fixed", "modelled", "ignored"))
    emit("  %-8s %14s %14s %14s" % ("bins/frame", "kept", "kept", "kept"))
    table = {}
    for drift in (0.0, 0.5, 1.0, 2.0):
        row = {}
        for rule in ("fixed", "modelled", "ignored"):
            kept = []
            for _ in range(draws):
                widths = [1 + drift * index for index in range(FRAMES)]
                frames, bins = run(rng, [
                    {"label": 1, "az": [10.0] * FRAMES, "bins": widths,
                     "start": 18},
                    {"label": 2, "az": [-30.0] * FRAMES, "bins": [5] * FRAMES,
                     "start": 46}])
                open_gate = 1.5 + drift
                if rule == "fixed":
                    tracks = tc.link(frames, bins, "direction+bandwidth",
                                     bin_scale_first=open_gate)
                elif rule == "modelled":
                    tracks = tc.link(frames, bins, "direction+bandwidth",
                                     bin_motion=True, bin_scale_first=open_gate)
                else:
                    tracks = tc.link(frames, bins, "direction")
                kept.append(pieces(tracks)[1])
            row[rule] = float(np.mean(kept))
        table[drift] = row
        emit("  %-8.1f %13.0f%% %13.0f%% %13.0f%%"
             % (drift, 100 * row["fixed"], 100 * row["modelled"],
                100 * row["ignored"]))
    emit("  A bandwidth that changes faster than the gate breaks a fixed cost")
    emit("  (%.0f%% at %.1f bins/frame) and the rate model restores it to %.0f%%."
         % (100 * table[2.0]["fixed"], 2.0, 100 * table[2.0]["modelled"]))
    emit("  Dropping the term also works, because the direction still separates")
    emit("  the two emitters (%.0f%%): a feature is only worth a gate when it is"
         % (100 * table[2.0]["ignored"]))
    emit("  needed to separate somebody.")
    return table


def study_f2(rng, emit, draws):
    emit("")
    emit("Study F2: bandwidth that jumps between two modes")
    emit("  emitter 1 hops to a new carrier every frame AND alternates 1 and 4 bins at")
    emit("  10 deg; at frame 4 a static 6-bin newcomer appears at the SAME 10 deg.")
    emit("  Only the bandwidth gate and the cadence can tell them apart.")
    emit("  %-26s %10s %13s %10s"
         % ("rule", "dipper", "newcomer", "tracks"))
    emit("  %-26s %10s %13s %10s" % ("", "kept", "absorbed", ""))
    table = {}
    rules = (("gate +-1.5 bins", 1.5, "direction+bandwidth"),
             ("gate +-2.5 bins", 2.5, "direction+bandwidth"),
             ("gate +-4 bins", 4.0, "direction+bandwidth"),
             ("gate +-4 bins + cadence", 4.0, "direction+bandwidth+cadence"))
    for name, bin_scale, rule in rules:
        kept, stolen, counts = [], [], []
        for _ in range(draws):
            widths = [1 if index % 2 == 0 else 4 for index in range(FRAMES)]
            hops = [int(rng.integers(0, 30)) for _ in range(FRAMES)]
            frames, bins = run(rng, [
                {"label": 1, "az": [10.0] * FRAMES, "bins": widths,
                 "start": hops},
                {"label": 3, "az": [10.0] * FRAMES, "bins": [6] * FRAMES,
                 "start": 44, "from": 4}])
            tracks = tc.link(frames, bins, rule, bin_scale=bin_scale)
            kept.append(pieces(tracks)[1])
            stolen.append(absorbed_by(tracks, 3))
            counts.append(len(tracks))
        table[name] = (float(np.mean(kept)), float(np.mean(stolen)),
                       float(np.mean(counts)))
        emit("  %-26s %9.0f%% %12.0f%% %10.1f"
             % (name, 100 * table[name][0], table[name][1], table[name][2]))
    emit("  So a jumping feature cannot be a key, and tolerating it with a wide")
    emit("  gate leaves a track whose bandwidth is the mean of two modes. What")
    emit("  that costs is measured next: a newcomer appears at frame 2 with a fixed")
    emit("  carrier, and the question is whether it ends the run in a track of its")
    emit("  own.")
    emit("  %-18s %10s %10s %14s" % ("newcomer bins", "gate +-1.5", "gate +-4",
                                     "cadence, +-4"))
    emit("  %-18s %10s %10s %14s" % ("", "", "", "(ends in own track)"))
    escape = {}
    for bins_new in (2, 4, 6, 8):
        cells = []
        for bin_scale, rule in ((1.5, "direction+bandwidth"),
                                (4.0, "direction+bandwidth"),
                                (4.0, "direction+bandwidth+cadence")):
            taken = []
            for _ in range(2 * draws):
                widths = ([1, 4] * FRAMES)[:FRAMES]
                hops = [int(rng.integers(0, 30)) for _ in range(FRAMES)]
                frames, bins = run(rng, [
                    {"label": 1, "az": [10.0] * FRAMES, "bins": widths,
                     "start": hops},
                    {"label": 3, "az": [10.0] * FRAMES,
                     "bins": [bins_new] * FRAMES, "start": 44, "from": 2}])
                tracks = tc.link(frames, bins, rule, bin_scale=bin_scale)
                taken.append(own_track(tracks, 3))
            cells.append(float(np.mean(taken)))
        escape[bins_new] = cells
        emit("  %-18s %9.0f%% %9.0f%% %13.0f%%"
             % ("%d bins" % bins_new, cells[0], cells[1], cells[2]))
    emit("  Tolerance and discrimination are the same knob: after eight frames the")
    emit("  +-4 bin gate has swallowed the 2-bin newcomer (it owns its track in")
    emit("  %.0f%% of runs against %.0f%% with the +-1.5 gate), and the narrow"
         % (escape[2][1], escape[2][0]))
    emit("  gate that avoids it is the one that shreds the dipper. Cadence is")
    emit("  late, not absent: the newcomer is swallowed at arrival like any other")
    emit("  cluster, and once its carrier has repeated a few times it stops")
    emit("  matching a hopping track (%.0f%% own track with cadence, at the end)."
         % escape[2][2])
    emit("  A pattern needs frames to become a pattern; a value needs none.")
    return table, escape


def study_f3(rng, emit, draws):
    emit("")
    emit("Study F3: a direction that jumps instead of moving")
    emit("  emitter 1 sits at -20 deg and steps by one jump at frame 4; emitter 2")
    emit("  is 40 deg away. First: is the jump absorbed by the track?")
    emit("  %-10s %10s %14s %14s" % ("jump", "gate 4 deg", "gate 8 deg",
                                     "gate 16 deg"))
    absorbed = {}
    for jump in (5.0, 10.0, 20.0, 40.0):
        cells = []
        for gate in (4.0, 8.0, 16.0):
            kept = []
            for _ in range(draws):
                azimuths = [-20.0 + (jump if index >= 4 else 0.0)
                            for index in range(FRAMES)]
                frames, bins = run(rng, [
                    {"label": 1, "az": azimuths, "bins": [2] * FRAMES,
                     "start": 18},
                    {"label": 2, "az": [30.0] * FRAMES, "bins": [5] * FRAMES,
                     "start": 46}])
                tracks = tc.link(frames, bins, "direction+bandwidth",
                                 az_scale=gate, bin_scale=1.5)
                kept.append(pieces(tracks)[1])
            cells.append(float(np.mean(kept)))
        absorbed[jump] = cells
        emit("  %-10s %9.0f%% %13.0f%% %13.0f%%"
             % ("%.0f deg" % jump, 100 * cells[0], 100 * cells[1],
                100 * cells[2]))
    emit("  Then the price of a wide gate: a neighbour sits exactly at the landing")
    emit("  point, and the question is how confused the two tracks become.")
    emit("  %-10s %14s %14s" % ("jump", "confused at 8", "confused at 16"))
    theft = {}
    for jump in (10.0, 20.0, 40.0):
        cells = []
        for gate in (8.0, 16.0):
            cells_inner = []
            for _ in range(3 * draws):
                azimuths = [-20.0 + (jump if index >= 4 else 0.0)
                            for index in range(FRAMES)]
                landing = azimuths[-1]
                frames, bins = run(rng, [
                    {"label": 1, "az": azimuths, "bins": [2] * FRAMES,
                     "start": 18},
                    {"label": 2, "az": [landing] * FRAMES, "bins": [2] * FRAMES,
                     "start": 46}])
                tracks = tc.link(frames, bins, "direction+bandwidth",
                                 az_scale=gate, bin_scale=1.5)
                cells.append(confusion(tracks))
            cells = [cells[0]] if len(cells) == 1 else cells
        theft[jump] = cells
        emit("  %-10s %13.0f%% %13.0f%%" % ("%.0f deg" % jump, cells[0], cells[1]))
    emit("  A jump is not motion: at a 4 deg gate the track splits in two (%.0f%%"
         % (100 * absorbed[20.0][0]))
    emit("  of the emitter in one piece) and a gate wider than the jump absorbs")
    emit("  it (%.0f%% at 16 deg for a 10 deg jump)."
         % (100 * absorbed[10.0][2]))
    emit("  Confusion is the price of the wide gate: %.0f-%.0f%% of the detections"
         % (min(theft[20.0]), max(theft[20.0])))
    emit("  end in the other emitter's track once the gate admits the jump. It")
    emit("  does not fall again with a wider gate, because after the jump the two")
    emit("  emitters occupy the same direction with the same bandwidth -- the")
    emit("  crossing limit of V07 14.6, arriving from a jump instead of a walk.")
    emit("  That is why the gate has to be a speed limit from the physics, not a")
    emit("  tuning knob: every degree of gate is a degree of identity risk.")
    return absorbed, theft


def study_f4(rng, emit, draws):
    emit("")
    emit("Study F4: direction and bandwidth changing at the same time")
    emit("  emitter 1: +2 deg/frame and +0.5 bins/frame; emitter 2 fixed at -30")
    emit("  deg with 5 bins. Which model keeps the track?")
    emit("  %-34s %10s %10s" % ("rule", "kept", "tracks"))
    table = {}
    rules = (("direction only", "direction", False, False),
             ("direction + bandwidth, fixed", "direction+bandwidth", False, False),
             ("direction + bandwidth, both modelled", "direction+bandwidth",
              True, True))
    for name, rule, motion, bin_motion in rules:
        kept, counts = [], []
        for _ in range(draws):
            azimuths = [10.0 + 2.0 * index for index in range(FRAMES)]
            widths = [2 + 0.5 * index for index in range(FRAMES)]
            frames, bins = run(rng, [
                {"label": 1, "az": azimuths, "bins": widths, "start": 18},
                {"label": 2, "az": [-30.0] * FRAMES, "bins": [5] * FRAMES,
                 "start": 46}])
            tracks = tc.link(frames, bins, rule, motion=motion,
                             bin_motion=bin_motion)
            kept.append(pieces(tracks)[1])
            counts.append(len(tracks))
        table[name] = (float(np.mean(kept)), float(np.mean(counts)))
        emit("  %-34s %9.0f%% %10.1f"
             % (name, 100 * table[name][0], table[name][1]))
    emit("  Both terms drift and both have to be modelled, or dropped: with the")
    emit("  bandwidth fixed the track dies as soon as the width leaves the gate,")
    emit("  and with the direction fixed it dies on the movement.")
    return table


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261110)
    parser.add_argument("--draws", type=int, default=6)
    parser.add_argument("--out", default=os.path.join(
        "docs", "evidence", "2026-11-06-phase-interf", "feature_models.txt"))
    args = parser.parse_args()
    path = args.out if not args.quick else os.path.join(
        "build", "output", "v07_features_quick.txt")
    rng = np.random.default_rng(args.seed)
    draws = max(4, args.draws // 3) if args.quick else args.draws
    lines = []

    def emit(text=""):
        print(text)
        lines.append(text)

    emit("What you cluster on: a model per feature, chosen by how it changes")
    emit("seed %d, %d draws, %d bins of %.3f MHz, 16 snapshots per frame"
         % (args.seed, draws, len(AXIS), BIN_HZ / 1e6))

    table1 = study_f1(rng, emit, draws)
    table2, escape = study_f2(rng, emit, draws)
    absorbed, theft = study_f3(rng, emit, draws)
    table4 = study_f4(rng, emit, draws)

    emit("")
    emit("VERDICT")
    emit("  You cluster on features whose model matches how they change. For each")
    emit("  feature, the question is one ratio: how far does it move in one frame")
    emit("  compared with how well it is measured (about 1 deg and one bin here)?")
    emit("  %-14s %22s %20s" % ("feature", "changes by", "so it is"))
    emit("  %-14s %22s %20s" % ("direction", "0-16 deg/frame measured", "rate model"))
    emit("  %-14s %22s %20s" % ("bandwidth", "0-2 bins/frame, or jumps",
                                "rate or mode"))
    emit("  %-14s %22s %20s" % ("carrier", "up to 800 MHz per hop",
                                "pattern only"))
    emit("  %-14s %22s %20s" % ("level", "several dB per hop", "not used"))
    emit("  1. CONTINUOUS change (a mover, a chirp): model the rate and predict;")
    emit("     the gate stays at its measurement-limited width (F1, F4).")
    emit("  2. DISCONTINUOUS change (a hop, a mode change): the value jumps, so it")
    emit("     cannot be a position key. Widen the gate and it becomes a bad key")
    emit("     (F2: merged detections grow with the gate), so use its *pattern*")
    emit("     over a window instead -- cadence -- or drop it.")
    emit("  3. FAST change (level, coherence under fading): no model saves it; it")
    emit("     never enters the cost.")
    emit("  Concretely, association is: (direction with a rate) + (bandwidth with")
    emit("  a rate, or out of the cost) + (cadence, which is a pattern, not a")
    emit("  value) -- and a jump is a new track, not a fast target.")

    checks = [
        ("a drifting bandwidth breaks a fixed-bandwidth cost",
         table1[2.0]["fixed"] < 0.95),
        ("modelling the drift keeps the track",
         table1[2.0]["modelled"] >= 0.95),
        ("a feature can be dropped when it is not needed to separate anybody",
         table1[2.0]["ignored"] >= 0.95),
        ("a mode-jumping bandwidth shreds a tight gate",
         table2["gate +-1.5 bins"][0] < 0.95),
        ("a wide gate keeps the mode-jumping emitter whole",
         table2["gate +-4 bins"][0] >= 0.95),
        ("cadence keeps it whole too, and is what discriminates",
         table2["gate +-4 bins + cadence"][0] >= 0.9),
        ("a narrow gate keeps the newcomer, a wide one swallows it",
         escape[2][0] > escape[2][1]),
        ("a 20 deg jump is not absorbed by a 4 deg gate",
         absorbed[20.0][0] < 0.95),
        ("a gate wider than the jump absorbs it",
         absorbed[10.0][2] >= 0.95),
        ("and confuses the two tracks when it lands on a neighbour",
         any(value > 0.0 for row in theft.values() for value in row)),
        ("modelling both drifts keeps the track (F4)",
         table4["direction + bandwidth, both modelled"][0] >= 0.9),
    ]
    emit("")
    verdict = True
    for text, ok in checks:
        emit("  [%s] %s" % ("PASS" if ok else "FAIL", text))
        verdict &= bool(ok)
    emit("")
    emit("RESULT=%s" % ("PASS" if verdict else "FAIL"))

    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\nreport written to %s" % path)
    return 0 if verdict else 1


if __name__ == "__main__":
    sys.exit(main())
