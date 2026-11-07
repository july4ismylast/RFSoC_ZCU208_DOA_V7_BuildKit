#!/usr/bin/env python3
"""Test bench for step5: the ladder, the store, and the decoy check.

  T5.1  the order of the rungs is the point: with the modulation rung, a 16QAM
        cell at the same direction as a QPSK track is a NEW track; with the
        direction rung only, it is absorbed into the QPSK track
  T5.2  the decoy check: step0's repeater scene must give 40 ns, and the single
        emitter must give no flag (a false alarm costs a track)
  T5.3  the cost is monotone in every rung, and a modulation mismatch is
        expensive enough to be a rejection rather than a preference
  T5.4  the store survives a one-frame dropout and retires a ghost
  T5.5  the three committed studies still say PASS: moving_targets,
        feature_models and cluster_policy (quick mode, 18 s in total)

Run:  python3 step5_r5_tracking/testbench/run_testbench.py
"""

from __future__ import annotations

import pathlib
import subprocess
import sys

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
sys.path.insert(0, str(STEP / "py"))
sys.path.insert(0, str(ROOT / "step0_antenna" / "py"))
import array_model as model  # noqa: E402
import ladder  # noqa: E402
import make_scenes  # noqa: E402

CHECKS = []


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-46s %s" % (name, "PASS" if ok else "FAIL", detail))


def main() -> int:
    print("step5 -- association ladder, track store, decoy verification")
    paths = make_scenes.ensure(ROOT / "step0_antenna" / "data", quiet=True)

    # T5.1 rung order
    full = ladder.Store()
    full.update([ladder.cell(10.0, 0.0, 100e6, "QPSK", frame=0)])
    full.update([ladder.cell(10.05, 0.0, 100e6, "16QAM", frame=1)])
    partial = ladder.Store(rungs=("direction", "bandwidth", "cadence"))
    partial.update([ladder.cell(10.0, 0.0, 100e6, "QPSK", frame=0)])
    partial.update([ladder.cell(10.05, 0.0, 100e6, "16QAM", frame=1)])
    check("T5.1", len(full.tracks) == 2 and len(partial.tracks) == 1,
          "full ladder %d track(s), direction-only %d track(s) for the same 16QAM cell"
          % (len(full.tracks), len(partial.tracks)))

    # T5.2 the decoy check on real step0 data
    decoy = model.load(paths["scene_decoy"])
    single = model.load(paths["scene_single"])
    found = ladder.two_arrivals(decoy["x"][0])
    clean = ladder.two_arrivals(single["x"][0])
    check("T5.2", found["two_arrivals"] and abs(found["delay_ns"] - 40.0) < 2.0
          and not clean["two_arrivals"],
          "repeater: %.1f ns (correlation %.2f, flagged) | single: %.1f ns (%.2f, clear)"
          % (found["delay_ns"], found["correlation"], clean["delay_ns"],
             clean["correlation"]))

    # T5.3 the cost function
    track = {"az": 10.0, "el": 0.0, "bw_hz": 100e6, "mod": "QPSK", "last_frame": 0}
    near = ladder.cost(ladder.cell(10.1, 0.0, 100e6, "QPSK", frame=1), track)
    far = ladder.cost(ladder.cell(11.0, 0.0, 100e6, "QPSK", frame=1), track)
    wrong_mod = ladder.cost(ladder.cell(10.0, 0.0, 100e6, "16QAM", frame=1), track)
    wide = ladder.cost(ladder.cell(10.0, 0.0, 300e6, "QPSK", frame=1), track)
    monotone = near < far and near < wide and wrong_mod > 50.0
    check("T5.3", monotone,
          "cost near %.2f < far %.2f, wide %.2f; modulation mismatch %.0f"
          % (near, far, wide, wrong_mod))

    # T5.4 the store survives a dropout, retires a ghost
    store = ladder.Store()
    store.update([ladder.cell(5.0, 0.0, 50e6, "BPSK", frame=0)])
    store.update([])                                     # one empty frame
    store.update([ladder.cell(5.05, 0.0, 50e6, "BPSK", frame=2)])
    survived = len(store.tracks) == 1 and len(store.tracks[0]["cells"]) == 2
    retired_at = None
    for frame in range(3, 9):
        store.update([])
        if not store.tracks and retired_at is None:
            retired_at = frame
    check("T5.4", survived and retired_at is not None and retired_at <= 7,
          "survived one empty frame, ghost retired at frame %s" % retired_at)

    # T5.5 the committed studies
    for name in ("moving_targets", "feature_models", "cluster_policy"):
        finished = subprocess.run([sys.executable, str(ROOT / "scripts" / (name + ".py")),
                                   "--quick"], capture_output=True, text=True)
        output = finished.stdout + finished.stderr
        passed = "RESULT=PASS" in output
        check("T5.5 " + name, passed,
              "RESULT=PASS" if passed else (output.strip().splitlines() or ["no output"])[-1][:60])

    total = sum(1 for _, ok, _ in CHECKS if ok)
    print("RESULT=%s (%d/%d)" % ("PASS" if total == len(CHECKS) else "FAIL",
                                 total, len(CHECKS)))
    return 0 if total == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
