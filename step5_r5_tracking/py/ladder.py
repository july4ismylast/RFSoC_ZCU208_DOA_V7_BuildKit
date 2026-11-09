"""The association ladder, the track store, and the decoy check -- in numpy.

This is step5: what turns per-frame *cells* (a direction, a bandwidth, a
modulation label) into *tracks*, and what decides whether a cell is one emitter
or two.  V07 sections 15-19 are the derivation; this file is the code.

A cell, as the PS receives it from step3 + step4:

    cell = {"az": 12.5, "el": -7.2, "bw_hz": 100e6, "mod": "QPSK",
            "power_db": 18.0, "snr_db": 20.0}

A track is a list of cells over frames plus a label vote and a verification flag.

The ladder (V07 section 19)
---------------------------
The four rungs are applied **in order**, and the order is the point:

    1  modulation   a different label is a different emitter (cheap, decisive)
    2  direction    az/el inside the gate; the strongest geometric statement
    3  bandwidth    log-ratio inside the gate; separates same-direction emitters
    4  cadence      the cell arrived when this track expects one (hoppers)

A cell is associated with the first track that passes every rung, and among
those, with the minimum cost

    C = sum_r  w_r * (d_r / sigma_r)^2          over the rungs that can be measured

so a rung whose measurement is bad (direction error at low SNR) contributes less
by itself: its weight is fixed, but the *distance* is what moves.

The decoy check (V07 section 13, the `verification index`)
----------------------------------------------------------
A repeater is one waveform arriving twice: the power spectrum carries a ripple
with period 1/delay, so the cepstrum of the spectrum has a peak at the delay.

    rippled(f) = |1 + a exp(-j 2 pi f tau)|^2 * |S(f)|^2
    cepstrum   = |FFT( log|X(f)|^2 )|          peak at quefrency tau

`verification_index` looks for that peak between 2 ns and 300 ns of quefrency and
returns the delay and how strong the ripple is.  A cell whose ripple is strong
holds **two arrivals**, and V07 sections 13.7 and 19.1 say what to do then: do
not split the cell, verify it.

Run:  python3 step5_r5_tracking/py/ladder.py
"""

from __future__ import annotations

import math

import numpy as np

RUNGS = ("modulation", "direction", "bandwidth", "cadence")
SIGMA = {"direction": 0.5, "bandwidth": 0.35, "cadence": 1.5}
WEIGHT = {"modulation": 1.0, "direction": 1.0, "bandwidth": 1.0, "cadence": 0.5}
GATE = {"modulation": 0.5, "direction": 1.5, "bandwidth": 1.0, "cadence": 1.2}
RETIRE_FRAMES = 3


def cell(az: float, el: float, bandwidth_hz: float, modulation: str,
         power_db: float = 15.0, snr_db: float = 20.0, frame: int = 0) -> dict:
    """One detection, in the units the PS works in."""
    return {"az": float(az), "el": float(el), "bw_hz": float(bandwidth_hz),
            "mod": modulation, "power_db": float(power_db), "snr_db": float(snr_db),
            "frame": int(frame)}


# --------------------------------------------------------------------------
# the rungs
# --------------------------------------------------------------------------
def rung_residuals(item: dict, track: dict) -> dict:
    """Per-rung standardised distance between a cell and a track.

    A missing measurement (no label yet, one frame only) returns None and the
    rung is skipped -- that is how a new track can still be adopted.
    """
    residuals = {}
    residuals["modulation"] = 0.0 if item["mod"] == track.get("mod") else 9.0
    if track.get("el") is None:
        residuals["direction"] = None
    else:
        residuals["direction"] = math.hypot(item["az"] - track["az"],
                                            item["el"] - track["el"]) / SIGMA["direction"]
    if not track.get("bw_hz"):
        residuals["bandwidth"] = None
    else:
        ratio = math.log(max(item["bw_hz"], 1e6) / max(track["bw_hz"], 1e6))
        residuals["bandwidth"] = abs(ratio) / SIGMA["bandwidth"]
    if track.get("last_frame") is None:
        residuals["cadence"] = None
    else:
        gap = item["frame"] - track["last_frame"]
        residuals["cadence"] = max(0, gap - 1) / SIGMA["cadence"]
    return residuals


def cost(item: dict, track: dict, rungs=RUNGS) -> float:
    """C = sum of w_r * d_r^2 over the rungs that were measured."""
    total = 0.0
    for rung in rungs:
        value = rung_residuals(item, track)[rung]
        if value is None:
            continue
        total += WEIGHT[rung] * value * value
    return total


def passes(item: dict, track: dict, rungs=RUNGS) -> bool:
    """Every measurable rung must be inside its gate."""
    for rung in rungs:
        value = rung_residuals(item, track)[rung]
        if value is not None and value > GATE[rung]:
            return False
    return True


def associate(cells: list, tracks: list, rungs=RUNGS) -> tuple:
    """Greedy association by ladder order then cost.

    Returns (assignments, unassigned) where assignments is a list of
    (cell_index, track_index).  Greedy is what fits in a frame budget; the
    studies in scripts/cluster_policy.py measure what greedy costs.
    """
    candidates = []
    for cell_index, item in enumerate(cells):
        for track_index, track in enumerate(tracks):
            if not passes(item, track, rungs):
                continue
            order = sum(1 for rung in rungs if rung_residuals(item, track)[rung] is not None)
            candidates.append((cost(item, track, rungs), -order, cell_index, track_index))
    candidates.sort()
    used_cells, used_tracks, assignments = set(), set(), []
    for _, _, cell_index, track_index in candidates:
        if cell_index in used_cells or track_index in used_tracks:
            continue
        assignments.append((cell_index, track_index))
        used_cells.add(cell_index)
        used_tracks.add(track_index)
    unassigned = [index for index in range(len(cells)) if index not in used_cells]
    return assignments, unassigned


# --------------------------------------------------------------------------
# the store
# --------------------------------------------------------------------------
class Store:
    """Tracks over frames: birth, update, label vote, verification, retire."""

    def __init__(self, rungs=RUNGS, retire_after: int = RETIRE_FRAMES):
        self.rungs = rungs
        self.retire_after = retire_after
        self.tracks = []
        self.next_id = 1
        self.frame = 0

    def update(self, cells: list, frame: int | None = None) -> dict:
        """One frame: associate, then birth/update/retire.

        An empty `cells` list is a *legal* frame -- a frame in which nothing was
        detected -- and it still advances the clock, which is what makes a ghost
        expire.  Pass `frame` explicitly if the cells do not carry it.
        """
        if frame is None:
            frame = cells[0]["frame"] if cells else self.frame + 1
        self.frame = max(self.frame, int(frame))
        assignments, unassigned = associate(cells, self.tracks, self.rungs)
        for cell_index, track_index in assignments:
            self._absorb(self.tracks[track_index], cells[cell_index])
        born = []
        for cell_index in unassigned:
            track = {"id": self.next_id, "cells": [], "votes": {}, "verified": False,
                     "arrivals": 1}
            self.next_id += 1
            self._absorb(track, cells[cell_index])
            self.tracks.append(track)
            born.append(track["id"])
        retired = [track["id"] for track in self.tracks
                   if self.frame - track["last_frame"] > self.retire_after]
        self.tracks = [track for track in self.tracks
                       if track["id"] not in retired]
        return {"born": born, "retired": retired,
                "alive": [track["id"] for track in self.tracks]}

    def _absorb(self, track: dict, item: dict) -> None:
        track["cells"].append(item)
        track["last_frame"] = item["frame"]
        count = len(track["cells"])
        track["az"] = (track.get("az", 0.0) * (count - 1) + item["az"]) / count
        track["el"] = (track.get("el", 0.0) * (count - 1) + item["el"]) / count
        track["bw_hz"] = (track.get("bw_hz", 0.0) * (count - 1) + item["bw_hz"]) / count
        track["votes"][item["mod"]] = track["votes"].get(item["mod"], 0) + 1
        track["mod"] = max(track["votes"], key=track["votes"].get)
        track["verified"] = bool(item.get("verified", track.get("verified", False)))
        track["arrivals"] = int(item.get("arrivals", track.get("arrivals", 1)))


# --------------------------------------------------------------------------
# the verification index: one waveform or two?
# --------------------------------------------------------------------------
def two_arrivals(x: np.ndarray, fs_hz: float = 2.0e9, min_lag_ns: float = 10.0,
                 max_lag_ns: float = 300.0, threshold: float = 0.25) -> dict:
    """Is this burst one waveform or two?  Autocorrelation of the burst itself.

    A repeater is the same waveform arriving twice:

        x(t) = s(t) + a s(t - tau)

    so the *complex* autocorrelation of the burst has a peak at lag tau with
    value a/(1+a^2) -- 0.40 for the -6 dB echo of step0's scene_decoy, 0 for
    noise.  Resolution is one sample (0.5 ns at 2 GS/s), far better than the
    cepstral form used in scripts/radar_decoys.py on the PL's 410-bin power
    spectrum (16 ns there), because here the PS has the raw burst.

    Two things to keep out of the search: lags below ~10 ns (a PSK signal at
    4 samples/symbol is correlated at multiples of 2 ns) and the zero lag.

    Returns the delay, the correlation, and the verdict the ladder consumes.
    """
    samples = np.asarray(x, dtype=complex).ravel()
    samples = samples - samples.mean()
    count = samples.size
    spectrum = np.fft.fft(samples, 2 * count)
    autocorrelation = np.fft.ifft(spectrum * np.conj(spectrum))[:count]
    magnitude = np.abs(autocorrelation)
    if magnitude[0] <= 0.0:
        return {"delay_ns": 0.0, "correlation": 0.0, "two_arrivals": False}
    magnitude = magnitude / magnitude[0]
    lags_ns = np.arange(count) / fs_hz * 1e9
    window = (lags_ns >= min_lag_ns) & (lags_ns <= max_lag_ns)
    if not window.any():
        return {"delay_ns": 0.0, "correlation": 0.0, "two_arrivals": False}
    inside = magnitude[window]
    peak = int(np.argmax(inside))
    return {"delay_ns": float(lags_ns[window][peak]),
            "correlation": float(inside[peak]),
            "two_arrivals": bool(inside[peak] > threshold)}


# the old name, kept because the store and the GUIDE both speak of the index
verification_index = two_arrivals


def main() -> int:
    store = Store()
    for frame in range(4):
        cells = [cell(10.0 + 0.2 * frame, 0.0, 100e6, "QPSK", frame=frame)]
        report = store.update(cells)
        print("frame %d: alive %s born %s retired %s"
              % (frame, report["alive"], report["born"], report["retired"]))
    print("track 1: %d cells, label %s" % (len(store.tracks[0]["cells"]),
                                           store.tracks[0]["mod"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
