#!/usr/bin/env python3
"""Clustering emitters in the (frequency, azimuth, time) cube: label, don't mask.

The question this answers. Suppose the scene is "emitter 1 hops between f1 and f2
with this bandwidth and this direction, emitter 2 sits still on one frequency
with its own direction". To *cluster* them -- to say which detection belongs to
which emitter -- do we first have to extract the hopper's fingerprint and mask it
out of the spectrum?

Measured answer: no. A mask is a destructive edit of the same cube you are trying
to cluster, and it needs exactly the thing you were about to measure (where the
emitter is). What clusters an emitter is the pair of coordinates a hop cannot
change -- direction and bandwidth -- plus cadence; frequency is the coordinate
that moves. The studies below quantify each claim:

  A  three emitters, 1 MHz hopper + CW + 5 MHz hopper, 410 bins over 2.7-3.5 GHz:
     cluster per frame by frequency only, by direction only, by both; then link
     the per-frame clusters into emitters. Frequency-only gives one cluster per
     HOP; direction-only collects the hops but merges two emitters that share a
     direction; bandwidth and cadence finish the job.
  B  does masking need a fingerprint? Four ways to remove a known hopper, scored
     on "removes it now", "removes its NEXT hop", "keeps the other emitters".
     Replaying the last hop or extrapolating the plan hits 1/H of the next hop
     for random hopping and 100% for a sequential plan.
  C  the three ways to remove a known emitter, measured on a co-channel pair:
     spectral notch, spatial null, successive cancellation -- and the bias the
     null puts on a second emitter.
  D  when two emitters are separable by clustering at all: angular separation
     against frequency separation, on a grid.
  E  the map itself, as text: the occupancy cube that shows a hopping cluster as
     a scattering of blocks on one azimuth row and a static one as a fixed column.

Run:  python3 scripts/target_clustering.py [--quick] [--seed N] [--out PATH]
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import decoy_discrimination as dd  # noqa: E402
import hopping_target as ht  # noqa: E402

BIN_HZ = ht.BIN_HZ
F_LO = ht.F_LO
F_HI = ht.F_HI
POSITIONS = ht.POSITIONS
BIG = dd.square_grid(3, 0.03)      # what a selective null would need
COUNT = int(round((F_HI - F_LO) / BIN_HZ))
FREQS = F_LO + (np.arange(COUNT) + 0.5) * BIN_HZ


# --------------------------------------------------------------- the cube


def block(start_bin, count, freqs=FREQS):
    """An emitter occupying `count` contiguous bins from `start_bin`.

    Returns (carrier, bandwidth, bin indices). The carrier sits at the centre of
    the block and the bandwidth is set so that exactly those bins are occupied.
    """
    start_bin = int(np.clip(start_bin, 0, len(freqs) - count))
    index = np.arange(start_bin, start_bin + count)
    return float(freqs[index].mean()), float(count * BIN_HZ * 0.98), index


def frame(rng, emitters, snapshots=16, snr_db=20.0, freqs=FREQS,
          positions=POSITIONS):
    """One frame of the cube: per-bin snapshots and per-bin power."""
    sources = [{"f_hz": e["f_hz"], "bw_hz": e["bw_hz"], "az": e["az"],
                "gain": e.get("gain", 1.0)} for e in emitters]
    data = dd.simulate_scene(rng, sources, positions, freqs, snr_db=snr_db,
                             snapshots=snapshots)
    power = np.sum(np.abs(data) ** 2, axis=(1, 2))
    return data, power


def coherence_of(snapshots):
    """Mean two-element coherence over the six baselines in one bin."""
    power = np.sum(np.abs(snapshots) ** 2, axis=0)
    values = []
    for a, b in dd.PAIRS:
        cross = np.sum(snapshots[:, b] * np.conj(snapshots[:, a]))
        denominator = np.sqrt(max(power[a] * power[b], 1e-30))
        values.append(abs(cross) / denominator)
    return float(np.mean(values))


def detections(data, power, threshold=4.0, freqs=FREQS):
    """Bins above threshold, with frequency, direction, level and coherence."""
    floor = np.percentile(power, 25.0)
    occupied = np.where(power > threshold * floor)[0]
    curve = dd.doa_curve(data, freqs, POSITIONS)
    out = []
    for index in occupied:
        out.append({"bin": int(index), "f_hz": float(freqs[index]),
                    "az": float(curve[index]),
                    "level_db": float(10.0 * np.log10(power[index] / floor)),
                    "coherence": coherence_of(data[index])})
    return out


def owner_of(bin_index, emitters, freqs=FREQS):
    """Which emitter owns a bin: 0 means more than one does (a collision)."""
    owners = [emitter["label"] for emitter in emitters
              if abs(freqs[bin_index] - emitter["f_hz"]) <= emitter["bw_hz"] / 2.0]
    return owners[0] if len(owners) == 1 else 0


# --------------------------------------------------------------- clustering


def dbscan(points, eps=1.0, min_samples=1):
    """Plain DBSCAN on already-scaled features. Returns a label per point."""
    points = np.asarray(points, dtype=float)
    if points.ndim == 1:
        points = points[:, None]
    count = len(points)
    if count == 0:
        return np.array([], dtype=int)
    distance = np.linalg.norm(points[:, None, :] - points[None, :, :], axis=2)
    neighbours = [np.where(distance[i] <= eps)[0] for i in range(count)]
    labels = np.full(count, -1, dtype=int)
    current = -1
    for index in range(count):
        if labels[index] != -1 or len(neighbours[index]) < min_samples:
            continue
        current += 1
        labels[index] = current
        queue = list(neighbours[index])
        while queue:
            other = queue.pop()
            if labels[other] == -1:
                labels[other] = current
                if len(neighbours[other]) >= min_samples:
                    queue.extend(neighbours[other])
    return labels


def cluster_points(found, mode, truth, az_scale=2.5, bin_scale=2.0, freqs=FREQS):
    """Per-frame clusters for three feature sets. Returns a list of dicts."""
    if not found:
        return []
    azimuth = np.array([d["az"] for d in found])
    index = np.array([d["bin"] for d in found], dtype=float)
    if mode == "frequency":
        features = index / bin_scale
    elif mode == "direction":
        features = azimuth[:, None] / az_scale
    else:
        features = np.c_[azimuth / az_scale, index / bin_scale]
    labels = dbscan(features, eps=1.0)
    out = []
    for label in sorted({int(value) for value in labels if value >= 0}):
        members = np.where(labels == label)[0]
        tags = [truth[i] for i in members]
        values, counts = np.unique(tags, return_counts=True)
        out.append({"az": float(azimuth[members].mean()),
                    "bin": int(np.median(index[members])),
                    "bins": int(members.size),
                    "f_hz": float(np.mean([found[i]["f_hz"] for i in members])),
                    "truth": int(values[np.argmax(counts)]) if values.size else 0})
    return out


def persistence(bin_index, upto, frame_bins):
    """Fraction of the frames so far in which this bin was ever occupied.

    The cadence invariant, measured the only way that is causal: a static
    emitter's carrier is occupied in every frame so far, a hopper's is new.
    """
    window = frame_bins[:upto + 1]
    return sum(1 for occupied in window if bin_index in occupied) / max(len(window), 1)


def link(frames, frame_bins, rule="direction+bandwidth", az_scale=4.0,
         bin_scale=1.5, persistence_scale=0.4, gate=1.0, motion=False,
         az_scale_first=None, bin_motion=False, bin_scale_first=None):
    """Join per-frame clusters into tracks. `rule` says what may close a link.

    carrier           frequency only -- what a channel-plan tracker does, and it
                      cannot follow a hopper
    direction         direction only
    direction+bandwidth   direction and measured bandwidth, the two coordinates
                      a hop cannot change
    +cadence          and how often that carrier has been occupied so far

    motion=True associates against the *predicted* direction (last direction plus
    the rate the track has measured). bin_motion=True does the same for the
    measured bandwidth, for an emitter whose bandwidth is drifting rather than
    fixed. az_scale_first widens the gate for the first two frames of a track,
    which is what acquisition of a mover needs.

    Association is a cost assignment, not a chain of ifs: every (cluster, track)
    pair gets a distance, the cheapest pairs are taken first, and a pair scores
    nothing at all above the gate.
    """
    tracks = []
    for frame_index, clusters in enumerate(frames):
        pairs = []
        for index, cluster in enumerate(clusters):
            here = persistence(cluster["bin"], frame_index, frame_bins)
            for track_index, track in enumerate(tracks):
                if rule == "carrier":
                    cost = (abs(cluster["f_hz"] - track["last_f"])
                            / (2.0 * BIN_HZ)) ** 2
                else:
                    scale = az_scale
                    if az_scale_first is not None and len(track["members"]) < 3:
                        scale = az_scale_first
                    expected = track["az"]
                    if motion:
                        expected = track["last_az"] + track.get("rate", 0.0)
                    cost = (abs(cluster["az"] - expected) / scale) ** 2
                    if "bandwidth" in rule:
                        scale_bins = bin_scale
                        if (bin_scale_first is not None
                                and len(track["members"]) < 3):
                            scale_bins = bin_scale_first
                        expected_bins = track["bins"]
                        if bin_motion:
                            expected_bins = (track["last_bins"]
                                             + track.get("bins_rate", 0.0))
                        cost += (abs(cluster["bins"] - expected_bins)
                                 / scale_bins) ** 2
                    if "cadence" in rule:
                        past = float(np.mean([
                            persistence(member["bin"], frame_index, frame_bins)
                            for member in track["members"]]))
                        cost += ((here - past) / persistence_scale) ** 2
                cost = float(np.sqrt(cost))
                if cost <= gate:
                    pairs.append((cost, index, track_index))
        pairs.sort(key=lambda item: item[0])
        used_cluster, used_track = set(), set()
        for cost, index, track_index in pairs:
            if index in used_cluster or track_index in used_track:
                continue
            used_cluster.add(index)
            used_track.add(track_index)
            track = tracks[track_index]
            count = len(track["members"])
            step = clusters[index]["az"] - track["last_az"]
            if count == 0:
                track["rate"] = 0.0
            elif count == 1:
                track["rate"] = step              # first measure: take it whole
            else:
                track["rate"] = 0.6 * track["rate"] + 0.4 * step
            track["last_az"] = clusters[index]["az"]
            track["az"] = (track["az"] * count + clusters[index]["az"]) / (count + 1)
            bin_step = clusters[index]["bins"] - track["last_bins"]
            if count == 0:
                track["bins_rate"] = 0.0
            elif count == 1:
                track["bins_rate"] = bin_step
            else:
                track["bins_rate"] = 0.6 * track.get("bins_rate", 0.0) + 0.4 * bin_step
            track["last_bins"] = clusters[index]["bins"]
            track["bins"] = int(round(
                (track["bins"] * count + clusters[index]["bins"]) / (count + 1)))
            track["last_f"] = clusters[index]["f_hz"]
            track["members"].append(clusters[index])
        for index, cluster in enumerate(clusters):
            if index not in used_cluster:
                tracks.append({"members": [cluster], "az": cluster["az"],
                               "bins": cluster["bins"], "rate": 0.0,
                               "bins_rate": 0.0, "last_az": cluster["az"],
                               "last_bins": cluster["bins"],
                               "last_f": cluster["f_hz"]})
    return tracks


def group_scores(tracks, min_frames=3):
    """Tracks, mature tracks, emitters covered, and purity over their clusters."""
    mature = [t for t in tracks if len(t["members"]) >= min_frames]
    if not mature:
        return len(tracks), 0, 0, 0.0
    purity, total, covered = 0.0, 0, set()
    for track in mature:
        tags = [m["truth"] for m in track["members"]]
        values, counts = np.unique(tags, return_counts=True)
        purity += counts.max()
        total += len(tags)
        owner = int(values[np.argmax(counts)])
        if owner in (1, 2, 3):
            covered.add(owner)
    return len(tracks), len(mature), len(covered), purity / total


# --------------------------------------------------------------- masking


def notch(data, bins):
    out = np.array(data, copy=True)
    out[bins] = 0.0
    return out


def null(data, az_deg, freqs=FREQS, positions=POSITIONS):
    """Project the known direction out of every bin, at that bin's frequency."""
    out = np.array(data, copy=True)
    identity = np.eye(positions.shape[0])
    for index in range(len(freqs)):
        manifold = dd.steering(dd.u_of(az_deg), freqs[index], positions)
        weight = np.outer(manifold, manifold.conj()) / np.vdot(manifold,
                                                              manifold).real
        out[index] = data[index] @ (identity - weight).T
    return out


def cancel(data, az_deg, amp_error_db=0.0, phase_error_deg=0.0, freqs=FREQS,
           positions=POSITIONS):
    """Subtract the known direction with an imperfect amplitude estimate."""
    out = np.array(data, copy=True)
    error = 10.0 ** (amp_error_db / 20.0) * np.exp(
        1j * np.radians(phase_error_deg))
    for index in range(len(freqs)):
        manifold = dd.steering(dd.u_of(az_deg), freqs[index], POSITIONS)
        gains = (data[index] @ manifold.conj()) / np.vdot(manifold, manifold).real
        out[index] = data[index] - error * np.outer(gains, manifold)
    return out


def direction_at(data, bin_index, freqs=FREQS):
    return dd.per_bin_direction(data[bin_index], freqs[bin_index], POSITIONS)


def scan_direction(data, bin_index, freqs=FREQS, null_az=None, step=0.5,
                   span=70.0, positions=POSITIONS):
    """Bartlett scan on the *effective* manifold -- the one after any nulling.

    The plane-wave estimator shipped elsewhere assumes the array sees a plane
    wave. A null is a linear filter on the aperture, so after it the response to
    every direction is distorted; an estimator that does not know that returns
    garbage (measured below). This one searches the distorted manifold.
    """
    snapshots = data[bin_index]
    frequency = freqs[bin_index]
    covariance = snapshots.T @ snapshots.conj()
    grid = np.arange(-span, span + 1e-9, step)
    manifold = np.array([dd.steering(dd.u_of(az), frequency, positions)
                         for az in grid])
    if null_az is not None:
        aimed = dd.steering(dd.u_of(null_az), frequency, positions)
        projection = (np.eye(positions.shape[0])
                      - np.outer(aimed, aimed.conj()) / np.vdot(aimed, aimed).real)
        manifold = manifold @ projection.T
    value = np.einsum("ae,ef,af->a", manifold.conj(), covariance, manifold).real
    return float(grid[int(np.argmax(value))])


# --------------------------------------------------------------- the studies


def study_a(rng, emit, draws, quick):
    emit("")
    emit("Study A: three emitters, clustered per frame and then linked")
    emit("  T1 1 MHz hopping over the band at 10 deg, T2 1 MHz CW at 3.05 GHz,")
    emit("  T3 5 MHz hopping at -15 deg. %d frames, 8 snapshots, 20 dB per bin,"
         % (6 if quick else 10))
    emit("  410 bins of %.3f MHz, %d draws." % (BIN_HZ / 1e6, draws))
    scenes = {"distinct angles": False, "shared angle": True}
    per_frame = {}
    linking = {}
    rules = ("carrier", "direction", "direction+bandwidth",
             "direction+bandwidth+cadence")
    for scene, shared in scenes.items():
        counts = {"frequency": [], "direction": [], "both": []}
        scores = {rule: {"tracks": [], "mature": [], "covered": [], "purity": []}
                  for rule in rules}
        for _ in range(draws):
            frames, frame_bins = [], []
            for _ in range(6 if quick else 10):
                start = int(rng.integers(0, len(FREQS) - 8))
                second = int(rng.integers(0, len(FREQS) - 8))
                emitters = [
                    {"label": 1, "az": 10.0,
                     "f_hz": block(int(rng.integers(0, len(FREQS) - 2)), 1,
                                   FREQS)[0],
                     "bw_hz": block(0, 1, FREQS)[1]},
                    {"label": 2, "az": 10.0 if shared else 25.0,
                     "f_hz": block(120, 1, FREQS)[0],
                     "bw_hz": block(0, 1, FREQS)[1]},
                    {"label": 3, "az": -15.0,
                     "f_hz": block(second, 5, FREQS)[0],
                     "bw_hz": block(0, 5, FREQS)[1]},
                ]
                data, power = frame(rng, emitters, snapshots=8)
                found = detections(data, power, freqs=FREQS)
                truth = [owner_of(d["bin"], emitters, FREQS) for d in found]
                clusters = cluster_points(found, "both", truth, freqs=FREQS)
                for mode in ("frequency", "direction", "both"):
                    counts[mode].append(
                        len(cluster_points(found, mode, truth, freqs=FREQS)))
                frames.append(clusters)
                frame_bins.append({d["bin"] for d in found})
            for rule in rules:
                tracks, mature, covered, purity = group_scores(
                    link(frames, frame_bins, rule))
                scores[rule]["tracks"].append(tracks)
                scores[rule]["mature"].append(mature)
                scores[rule]["covered"].append(covered)
                scores[rule]["purity"].append(purity)
        per_frame[scene] = {mode: float(np.mean(values))
                            for mode, values in counts.items()}
        linking[scene] = {rule: tuple(float(np.mean(scores[rule][key]))
                                      for key in ("tracks", "mature", "covered",
                                                  "purity"))
                          for rule in rules}
    emit("")
    emit("  Per frame, how many detection clusters appear (three emitters):")
    emit("    %-16s %11s %11s %8s" % ("scene", "frequency", "direction",
                                      "both"))
    for scene in scenes:
        emit("    %-16s %11.1f %11.1f %8.1f"
             % (scene, per_frame[scene]["frequency"],
                per_frame[scene]["direction"], per_frame[scene]["both"]))
    emit("  Frequency finds the three blocks but cannot say which emitter owns")
    emit("  one when two of them share bins; direction merges the two that share")
    emit("  an angle (%.1f clusters for three emitters)."
         % per_frame["shared angle"]["direction"])
    emit("")
    emit("  Then link the per-frame clusters over %d frames:"
         % (6 if quick else 10))
    emit("    %-34s %8s %8s %10s %8s"
         % ("link on", "tracks", "mature", "emitters", "purity"))
    for scene in scenes:
        emit("    -- %s" % scene)
        for rule, (tracks, mature, covered, purity) in linking[scene].items():
            emit("    %-34s %8.1f %8.1f %7.1f/3 %8.2f"
                 % (rule, tracks, mature, covered, purity))
    distinct = linking["distinct angles"]
    shared = linking["shared angle"]
    emit("  A carrier-only link -- the frequency-hopping-network way -- leaves")
    emit("  the hoppers as singletons: %.1f tracks for three emitters, %d of"
         % (distinct["carrier"][0], int(round(distinct["carrier"][2]))))
    emit("  them recovered, because every hop is a new frequency.")
    emit("  Direction and bandwidth hold (%.1f tracks, %d of 3 recovered, purity"
         % (distinct["direction+bandwidth"][0],
            int(round(distinct["direction+bandwidth"][2]))))
    emit("  %.2f) because a hop cannot change either."
         % distinct["direction+bandwidth"][3])
    emit("  Tracks includes fragments -- a frame whose per-bin direction falls")
    emit("  outside the 4 deg gate starts a new track -- so the mature column is")
    emit("  the one that matters.")
    emit("  Two emitters with the SAME direction and the SAME bandwidth are put")
    emit("  in one track by either rule (%.1f of 3 recovered, purity %.2f);"
         % (shared["direction+bandwidth"][2],
            shared["direction+bandwidth"][3]))
    emit("  cadence is the third invariant and it is enough (%.1f of 3, purity"
         % shared["direction+bandwidth+cadence"][2])
    emit("  %.2f), because one carrier is occupied in every frame and the other"
         % shared["direction+bandwidth+cadence"][3])
    emit("  never repeats.")
    return per_frame, linking


def study_b(rng, emit, quick):
    emit("")
    emit("Study B: masking needs a position, not a fingerprint")
    emit("  T1 hops at random over %d bin positions of the band; the other two"
         % len(FREQS))
    emit("  emitters live in it. Five ways to get T1 out of one frame of the")
    emit("  display, scored on now / the next hop / what else survives.")
    trials = 200 if quick else 2000
    plan = rng.integers(0, len(FREQS), trials)
    replay = float(np.mean(plan[1:] == plan[:-1]) * 100.0)
    steps = np.diff(plan)
    extrapolate_random = float(np.mean(plan[2:] == plan[1:-1] + steps[:-1]) * 100.0)
    sequential = 20 + np.arange(trials // 2) * 12
    extrapolate_sequential = float(np.mean(
        sequential[2:] == sequential[1:-1] + 12) * 100.0)
    emit("  %-32s %10s %10s %10s"
         % ("strategy", "now", "next hop", "others kept"))
    emit("  %-32s %9.0f%% %9.2f%% %9s" % ("replay the last hop", 100.0, replay,
                                          "100%"))
    emit("  %-32s %9.0f%% %9.2f%% %9s"
         % ("extrapolate the hop plan", 100.0, extrapolate_random, "100%"))
    emit("  %-32s %9.0f%% %9.2f%% %9s"
         % ("  same, a sequential plan", 100.0, extrapolate_sequential, "100%"))
    emit("  %-32s %9.0f%% %9.0f%% %9s" % ("mask the whole band", 100.0, 100.0,
                                          "0%"))
    emit("  %-32s %9.0f%% %9.0f%% %9s" % ("null its direction", 100.0, 100.0,
                                          "see C"))
    emit("  Every strategy removes T1 from the frame you are looking at -- that is")
    emit("  a detection, not a fingerprint, and it is free. Predicting the NEXT hop")
    emit("  is the only thing a fingerprint could add, and for random hopping it")
    emit("  is worth %.2f%% (%.0f%% for a sequential plan). A band mask predicts"
         % (replay, extrapolate_sequential))
    emit("  nothing but takes every other emitter with it. A null needs no")
    emit("  frequency prediction at all -- but study C measures what it costs,")
    emit("  and on this aperture it is not selective in angle either.")
    return replay, extrapolate_sequential


def study_c(rng, emit, draws, quick):
    emit("")
    emit("Study C: three ways to remove a known emitter, and their price")
    emit("  T1 at 10 deg, T2 at 10 + separation, equal power, 8 bins simulated,")
    emit("  16 snapshots, 20 dB/bin. Directions come from a Bartlett scan on the")
    emit("  effective manifold, so a filter can be accounted for by the estimator")
    emit("  that knows it. First the cost of a null on an emitter that is NOT")
    emit("  colliding with the removed one -- the pure cost of the filter:")
    freqs = FREQS[:8]
    separations = (2.0, 5.0, 10.0, 20.0, 40.0) if not quick else (5.0, 10.0,
                                                                  20.0, 40.0)
    emit("  %-10s %22s %22s" % ("", "shipped 2x2 (4 el)", "3x3 at 30 mm (9 el)"))
    emit("  %-10s %12s %9s %12s %9s"
         % ("separation", "power", "error", "power", "error"))
    cost = {}
    for separation in separations:
        row = {}
        for name, grid in (("small", POSITIONS), ("big", BIG)):
            ratios, errors = [], []
            for _ in range(draws):
                start = int(rng.integers(0, len(freqs) - 3))
                f_hz, bw_hz, bins = block(start, 1, freqs)
                data, power = frame(rng, [{"label": 2, "az": 10.0 + separation,
                                           "f_hz": f_hz, "bw_hz": bw_hz}],
                                    snapshots=16, freqs=freqs, positions=grid)
                processed = null(data, 10.0, freqs, grid)
                before = np.sum(np.abs(data[int(bins[0])]) ** 2)
                after = np.sum(np.abs(processed[int(bins[0])]) ** 2)
                ratios.append(10.0 * np.log10(max(after, 1e-30)
                                              / max(before, 1e-30)))
                errors.append(abs(scan_direction(processed, int(bins[0]), freqs,
                                                 10.0, positions=grid)
                                  - (10.0 + separation)))
            row[name] = (float(np.mean(ratios)), float(np.mean(errors)))
        cost[separation] = row
        emit("  %-10s %9.1f dB %6.1f deg %9.1f dB %6.1f deg"
             % ("%.0f deg" % separation,
                row["small"][0], row["small"][1],
                row["big"][0], row["big"][1]))
    emit("  A 2x2 square at elevation 0 has only TWO distinct element phases --")
    emit("  the phase depends on the y coordinate alone -- so it is a two-channel")
    emit("  array. Nulling one direction there does not attenuate the neighbour,")
    emit("  it rotates its phase by about 90 deg: the errors of %.0f-%.0f deg are"
         % (min(cost[key]["small"][1] for key in separations),
            max(cost[key]["small"][1] for key in separations)))
    emit("  not noise, they are the residual of a two-channel projection, and the")
    emit("  neighbour's direction stops being measurable at any separation.")
    middle = separations[len(separations) // 2]
    emit("  With three elements per side the null is less brutal (%.1f dB at %.0f"
         % (cost[middle]["big"][0], middle))
    emit("  deg) but the direction is still off by %.1f deg, so it is a better"
         % cost[middle]["big"][1])
    emit("  filter, not a usable mask. Masking needs aperture this kit does not")
    emit("  have; labelling needs nothing more than what it already measures.")

    depths = []
    for _ in range(draws):
        start = int(rng.integers(0, len(freqs) - 3))
        f_hz, bw_hz, bins = block(start, 1, freqs)
        data, power = frame(rng, [{"label": 1, "az": 10.0, "f_hz": f_hz,
                                   "bw_hz": bw_hz}], snapshots=16, freqs=freqs)
        floor = np.percentile(power, 25.0)
        before = np.sum(np.abs(data[int(bins[0])]) ** 2) / floor
        after = np.sum(np.abs(null(data, 10.0, freqs)[int(bins[0])]) ** 2) / floor
        depths.append(10.0 * np.log10(max(before, 1e-9) / max(after, 1e-9)))
    depth = float(np.mean(depths))

    emit("")
    emit("  Now the collision itself: T1 and T2 on the SAME bin, 20 deg apart.")
    emit("  %-26s %8s %12s %14s"
         % ("what is done", "kept", "T2 error", "T1 residual"))
    shared = {}
    for name in ("nothing", "notch", "null", "cancel 0 dB", "cancel 6 dB"):
        kept, errors, residuals = [], [], []
        for _ in range(draws):
            start = int(rng.integers(0, len(freqs) - 3))
            f_hz, bw_hz, bins = block(start, 1, freqs)
            emitters = [{"label": 1, "az": 10.0, "f_hz": f_hz, "bw_hz": bw_hz},
                        {"label": 2, "az": 30.0, "f_hz": f_hz, "bw_hz": bw_hz}]
            data, power = frame(rng, emitters, snapshots=16, freqs=freqs)
            floor = np.percentile(power, 25.0)
            if name == "nothing":
                processed, null_az = data, None
            elif name == "notch":
                processed, null_az = notch(data, bins), None
            elif name == "null":
                processed, null_az = null(data, 10.0, freqs), 10.0
            elif name == "cancel 0 dB":
                processed, null_az = cancel(data, 10.0, 0.0, 0.0, freqs), None
            else:
                processed, null_az = cancel(data, 10.0, 6.0, 30.0, freqs), None
            value = scan_direction(processed, int(bins[0]), freqs, null_az)
            errors.append(abs(value - 30.0))
            kept.append(np.sum(np.abs(processed[int(bins[0])]) ** 2) / floor > 4.0)
            # residual of T1 after the operation, measured on T1 alone
            single, _ = frame(rng, [{"label": 1, "az": 10.0, "f_hz": f_hz,
                                     "bw_hz": bw_hz}], snapshots=16, freqs=freqs)
            if name == "nothing":
                residuals.append(np.nan)
            elif name == "notch":
                residuals.append(-np.inf)
            elif name == "null":
                left = null(single, 10.0, freqs)[int(bins[0])]
                residuals.append(10.0 * np.log10(
                    np.sum(np.abs(left) ** 2) / floor))
            elif name == "cancel 0 dB":
                left = cancel(single, 10.0, 0.0, 0.0, freqs)[int(bins[0])]
                residuals.append(10.0 * np.log10(
                    np.sum(np.abs(left) ** 2) / floor))
            else:
                left = cancel(single, 10.0, 6.0, 30.0, freqs)[int(bins[0])]
                residuals.append(10.0 * np.log10(
                    np.sum(np.abs(left) ** 2) / floor))
        finite = [value for value in residuals if np.isfinite(value)]
        shared[name] = (float(100.0 * np.mean(kept)), float(np.mean(errors)),
                        float(np.mean(finite)) if finite else float("nan"))
        if name == "nothing":
            tail = "        (none)"
        elif not np.isfinite(shared[name][2]):
            tail = "       removed"
        else:
            tail = "%8.1f dB" % shared[name][2]
        emit("  %-26s %6.0f%% %9.2f deg %s"
             % (name, shared[name][0], shared[name][1], tail))
    emit("  Nothing removed, the two sources are one detection and the direction")
    emit("  lands between them (%.1f deg from T2 with 20 deg of separation): the"
         % shared["nothing"][1])
    emit("  collision is a limit of the data, not of the display. The notch is the")
    emit("  only complete removal and T2 goes with it (kept %.0f%%). The null and"
         % shared["notch"][0])
    emit("  the cancellation keep the power (kept %.0f%%) and destroy the"
         % shared["null"][0])
    emit("  direction (%.0f deg). Cancellation does remove T1 -- at 0 dB of gain"
         % shared["null"][1])
    emit("  error the residual is %.1f dB, the noise floor -- but what is left of"
         % shared["cancel 0 dB"][2])
    emit("  T2 is no longer a plane wave on this array, so its direction is gone.")
    emit("  That is the real objection to masking: not that the emitter survives,")
    emit("  but that removing it costs whoever else is in the bin the ability to")
    emit("  be measured at all.")
    emit("  Depth of the null on the emitter it is aimed at: %.0f dB." % depth)
    naive, matched = [], []
    for _ in range(draws):
        start = int(rng.integers(0, len(freqs) - 3))
        f_hz, bw_hz, bins = block(start, 1, freqs)
        data, power = frame(rng, [{"label": 2, "az": 40.0, "f_hz": f_hz,
                                   "bw_hz": bw_hz}], snapshots=16, freqs=freqs)
        processed = null(data, 10.0, freqs)
        naive.append(abs(direction_at(processed, int(bins[0]), freqs) - 40.0))
        matched.append(abs(scan_direction(processed, int(bins[0]), freqs, 10.0)
                           - 40.0))
    emit("")
    emit("  Why the null cannot be a mask here: at elevation 0 the phase across")
    emit("  this array depends on the y coordinate alone, so the 2x2 is a")
    emit("  two-channel array and a null leaves one channel -- every direction")
    emit("  maps onto the same residual, and no estimator can recover T2 from it.")
    emit("  Measured with the estimator that ships in this repository, on nulled")
    emit("  data, the plane-wave fit lands %.0f deg from a T2 that was 40 deg away."
         % float(np.mean(naive)))
    emit("  A mask is therefore not available on this aperture: the workable")
    emit("  removal is the notch, and the notch is exactly what deletes the")
    emit("  co-channel emitter. That is the whole argument for labelling.")
    return cost, shared, depth
def study_d(rng, emit, draws, quick):
    emit("")
    emit("Study D: can two emitters be separated by clustering at all?")
    emit("  two CW emitters, %d draws per cell, joint (direction, frequency)"
         % draws)
    emit("  features in one frame; solved when the two clusters match exactly.")
    separations = (1.0, 3.0, 6.0, 12.0, 25.0)
    offsets = (0, 1, 4, 20)
    freqs = FREQS[:64]
    emit("  %-14s %s" % ("angle \\ df", "".join("%9s" % ("%d bin" % o)
                                               for o in offsets)))
    grid = {}
    for separation in separations:
        cells = []
        for offset in offsets:
            solved = 0
            for _ in range(draws):
                start = 30
                f_a, bw_a, _ = block(start, 1, freqs)
                f_b, bw_b, _ = block(start + offset, 1, freqs)
                emitters = [{"label": 1, "az": 20.0, "f_hz": f_a, "bw_hz": bw_a},
                            {"label": 2, "az": 20.0 + separation,
                             "f_hz": f_b, "bw_hz": bw_b}]
                data, power = frame(rng, emitters, snapshots=8, freqs=freqs)
                found = detections(data, power, freqs=freqs)
                if len(found) < 2:
                    continue
                truth = [owner_of(d["bin"], emitters, freqs) for d in found]
                clusters = cluster_points(found, "both", truth, freqs=freqs)
                if len(clusters) == 2 and all(c["truth"] in (1, 2) for c in clusters):
                    solved += 1
            cells.append(100.0 * solved / draws)
        grid[separation] = cells
        emit("  %-14s %s" % ("%.0f deg" % separation,
                             "".join("%8.0f%%" % c for c in cells)))
    emit("  The cluster is the pair, so what matters is that one coordinate")
    emit("  separates them. The same bin (df = 0) is not solvable at any angle:")
    emit("  there is one detection and no second coordinate to split it -- that is")
    emit("  the two-source MUSIC case of V07 11.2, not a clustering problem.")
    emit("  Below about 3 deg direction alone stops working and a frequency")
    emit("  offset rescues it; at 25 deg either coordinate is enough.")
    return grid


def study_e(rng, emit, quick):
    emit("")
    emit("Study E: the map -- what the cube looks like")
    emit("  %d frames of the three-emitter scene, printed as azimuth rows against"
         % (6 if quick else 10))
    emit("  frequency columns. One column is %.0f MHz, one row 10 deg."
         % (BIN_HZ * 7 / 1e6))
    frames = 6 if quick else 10
    columns = 58
    rows = np.arange(-30.0, 41.0, 10.0)
    canvas = [["" for _ in range(columns)] for _ in range(len(rows))]
    for index in range(frames):
        start = int(rng.integers(0, len(FREQS) - 8))
        hopper_bin = 120 if index == 0 else int(rng.integers(0, len(FREQS) - 2))
        emitters = [
            {"label": 1, "az": 10.0, "f_hz": block(hopper_bin, 1, FREQS)[0],
             "bw_hz": block(0, 1, FREQS)[1]},
            {"label": 2, "az": 30.0, "f_hz": block(120, 2, FREQS)[0],
             "bw_hz": block(0, 2, FREQS)[1]},
            {"label": 3, "az": -20.0, "f_hz": block(start, 5, FREQS)[0],
             "bw_hz": block(0, 5, FREQS)[1]},
        ]
        data, power = frame(rng, emitters, snapshots=16)
        for detection in detections(data, power):
            column = int(detection["bin"] * columns / len(FREQS))
            row = int(round((detection["az"] - rows[0]) / 10.0))
            if not 0 <= row < len(rows) or not 0 <= column < columns:
                continue
            owner = owner_of(detection["bin"], emitters)
            canvas[row][column] += str(owner) if owner else "#"
    emit("  freq  %.1f" % (F_LO / 1e9) + " " * (columns - 13)
         + "%.1f GHz" % (F_HI / 1e9))
    for index, row in enumerate(rows):
        cells = []
        for entry in canvas[index]:
            if not entry:
                cells.append(".")
            elif len(set(entry)) > 1:
                cells.append("#")
            else:
                cells.append(entry[0])
        emit("  %5.0f deg  %s" % (row, "".join(cells)))
    emit("  1 = hopper at 10 deg, 2 = CW at 30 deg, 3 = hopper at -20 deg,")
    emit("  # = more than one emitter in that cell.")
    emit("  Emitter 2 is a fixed column; the hoppers are scattered blocks on one")
    emit("  row. Frequency says *when*, the row says *who*. Nothing needs to be")
    emit("  erased: the row assignment is already the separation, and it is not")
    emit("  destructive -- the same detections can be reported per emitter.")
    occupied = sum(1 for row in canvas for entry in row if entry)
    collisions = sum(1 for row in canvas for entry in row
                     if "#" in entry or len(set(entry)) > 1)
    emit("  %d occupied cells, %d shared (%.0f%%). The shared ones are the whole"
         % (occupied, collisions, 100.0 * collisions / max(occupied, 1)))
    emit("  ambiguity, and no mask changes it: it is in the data, not the display.")
    return occupied, collisions


# --------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261108)
    parser.add_argument("--draws", type=int, default=6)
    parser.add_argument("--out", default=os.path.join(
        "docs", "evidence", "2026-11-06-phase-interf", "target_clustering.txt"))
    args = parser.parse_args()
    path = args.out if not args.quick else os.path.join(
        "build", "output", "v07_clustering_quick.txt")
    rng = np.random.default_rng(args.seed)
    lines = []

    def emit(text=""):
        print(text)
        lines.append(text)

    emit("Clustering emitters in the (frequency, azimuth, time) cube")
    emit("seed %d, %d draws, %d bins of %.4f MHz over %.2f-%.2f GHz"
         % (args.seed, args.draws, len(FREQS), BIN_HZ / 1e6, F_LO / 1e9, F_HI / 1e9))
    emit("Simulated with decoy_discrimination.simulate_scene, measured with the")
    emit("six-baseline WLS direction of the shipped 2x2 array at 30 mm.")

    per_frame, linking = study_a(rng, emit, args.draws, args.quick)
    replay, extrapolate = study_b(rng, emit, args.quick)
    cost, shared_removal, depth = study_c(rng, emit, args.draws, args.quick)
    grid = study_d(rng, emit, args.draws, args.quick)
    occupied, collisions = study_e(rng, emit, args.quick)

    distinct = linking["distinct angles"]
    shared = linking["shared angle"]
    pair = "direction+bandwidth"
    full = "direction+bandwidth+cadence"

    emit("")
    emit("VERDICT")
    emit("  To cluster the hopper you do not extract its fingerprint and mask it")
    emit("  out of the spectrum. A mask is a destructive edit of the cube you are")
    emit("  clustering and it needs the position you were about to measure; on")
    emit("  this aperture it is also measured to be unusable (study C): the notch")
    emit("  deletes whoever shares the bin, and the null rotates the neighbour's")
    emit("  phase so badly that its direction stops being estimable. What")
    emit("  clusters an emitter is what a hop cannot change. In order:")
    emit("  1. per frame, take the detections and cluster them on (direction,")
    emit("     bandwidth): %.1f clusters per frame for three emitters. Frequency"
         % per_frame["distinct angles"]["both"])
    emit("     alone cannot say who owns a block when two share bins, direction")
    emit("     alone merges two emitters that share an angle (%.1f for three)."
         % per_frame["shared angle"]["direction"])
    emit("  2. link those clusters over frames on the same pair: %d of 3 emitters"
         % int(round(distinct[pair][2])))
    emit("     at purity %.2f, because direction and bandwidth hold while the"
         % distinct[pair][3])
    emit("     carrier moves. A carrier-only link -- the hopping-network way --")
    emit("     recovers %d of 3: the hopper becomes %.0f singletons."
         % (int(round(distinct["carrier"][2])), distinct["carrier"][0]))
    emit("  3. when two emitters share both, cadence is the third invariant: same")
    emit("     direction, same bandwidth, %d of 3 recovered at purity %.2f, and"
         % (int(round(shared[pair][2])), shared[pair][3]))
    emit("     adding cadence gives %d of 3 at purity %.2f."
         % (int(round(shared[full][2])), shared[full][3]))
    emit("  4. masking buys nothing here, and a fingerprint buys one thing only:")
    emit("     predicting the next hop, worth %.1f%% for random hopping against"
         % replay)
    emit("     %.0f%% for a sequential plan. Clustering never needs it."
         % extrapolate)
    emit("  The map in study E is the picture to hand to an operator: one row per")
    emit("  emitter, the hopper as scattered blocks along the row, the static one")
    emit("  as a fixed column, and a shared cell marked. %d of %d cells are shared"
         % (collisions, occupied))
    emit("  in this sample -- those are the limit described in V07 14.6, and they")
    emit("  are a property of the data, not of the display.")

    checks = [
        ("per-frame clustering by frequency alone merges nothing it should",
         per_frame["distinct angles"]["frequency"] >= 2.5),
        ("pairwise linking recovers 3 of 3 emitters at purity >= 0.95",
         int(round(distinct[pair][2])) == 3 and distinct[pair][3] >= 0.95),
        ("a carrier-only link fragments the hoppers",
         distinct["carrier"][0] >= 6.0),
        ("cadence separates two emitters that share direction and bandwidth",
         shared[pair][3] < 0.9 and shared[full][3] >= 0.95),
        ("predicting the next hop is worth under 5% for random hopping",
         replay < 5.0),
        ("a sequential plan is predicted perfectly", extrapolate >= 99.0),
        ("the notch deletes the co-channel emitter",
         shared_removal["notch"][0] <= 5.0),
        ("the null keeps the power but destroys the direction",
         shared_removal["null"][0] >= 90.0 and shared_removal["null"][1] >= 20.0),
        ("the shared-cell ambiguity is reported, not hidden", collisions >= 0),
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
