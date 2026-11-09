#!/usr/bin/env python3
"""Test bench for step6: the A53 supervisor, against the python ladder.

The fixture (fixture_cells.jsonl) is 15 cells over 7 frames and holds three
things on purpose:

  * a QPSK mover at 10.0 -> 10.6 deg with one dropped frame at frame 3
  * a 16QAM emitter at the *same direction*, different bandwidth
  * a ghost at 25 deg that is present for two frames and then gone

  T6.1  the supervisor builds with g++ -Wall -Wextra -pedantic -Werror-free
  T6.2  it creates the same number of tracks as step5's python ladder (3)
  T6.3  the modulation rung is what separates the 16QAM track (2 vs 1 policy)
  T6.4  the ghost is retired, and telemetry says so
  T6.5  --quiet writes nothing on stdout, and the exit code is 0

Run:  python3 step6_ps_linux/testbench/run_testbench.py
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
sys.path.insert(0, str(ROOT / "step5_r5_tracking" / "py"))
import ladder  # noqa: E402

FIXTURE = STEP / "testbench" / "fixture_cells.jsonl"
BINARY = ROOT / "build" / "step6" / "supervisor"
CHECKS = []


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-44s %s" % (name, "PASS" if ok else "FAIL", detail))


def read_cells() -> list:
    return [json.loads(line) for line in FIXTURE.read_text().splitlines() if line.strip()]


def run_supervisor(*arguments) -> tuple:
    finished = subprocess.run([str(BINARY), *arguments], stdin=FIXTURE.open(),
                              capture_output=True, text=True)
    return finished.returncode, finished.stdout, finished.stderr


def python_tracks(cells: list, rungs=ladder.RUNGS) -> int:
    store = ladder.Store(rungs=rungs)
    born = 0
    by_frame = {}
    for item in cells:
        by_frame.setdefault(item["frame"], []).append(item)
    for frame in sorted(by_frame):
        while store.frame < frame - 1:
            store.update([], frame=store.frame + 1)
        report = store.update([ladder.cell(item["az"], item["el"], item["bw_hz"],
                                           item["mod"], frame=item["frame"])
                               for item in by_frame[frame]], frame=frame)
        born += len(report["born"])
    return born


def main() -> int:
    print("step6 -- the A53 supervisor")
    cells = read_cells()
    print("  fixture: %d cells, frames %d..%d"
          % (len(cells), min(item["frame"] for item in cells),
             max(item["frame"] for item in cells)))

    build = subprocess.run(["make", "-C", str(STEP / "c")], capture_output=True, text=True)
    check("T6.1", build.returncode == 0 and BINARY.exists(),
          "built %s (%.0f kB)" % (BINARY.name, BINARY.stat().st_size / 1024.0)
          if BINARY.exists() else "build failed")

    code, output, summary = run_supervisor()
    events = [json.loads(line) for line in output.splitlines() if line.strip()]
    born_c = len([event for event in events if event["state"] == "born"])
    born_py = python_tracks(cells)
    check("T6.2", code == 0 and born_c == born_py == 3,
          "born: supervisor %d, python ladder %d, expected 3" % (born_c, born_py))

    code_q, output_q, _ = run_supervisor("--quiet")
    code_dir, output_dir, summary_dir = run_supervisor("--policy", "direction-only")
    born_dir = len([json.loads(line) for line in output_dir.splitlines()
                    if line.strip() and json.loads(line)["state"] == "born"])
    check("T6.3", born_dir < born_c,
          "full policy %d track(s), direction-only %d track(s)" % (born_c, born_dir))

    retired = [event for event in events if event["state"] == "retired"]
    ghosts = int(re.search(r"ghosts=(\d+)", summary).group(1)) if "ghosts=" in summary else -1
    check("T6.4", len(retired) >= 1 and ghosts >= 1,
          "%d retired, %d of them ghosts (the 25 deg emitter)" % (len(retired), ghosts))

    check("T6.5", code_q == 0 and output_q.strip() == "" and "malformed=0" in summary,
          "--quiet silent, exit %d, %s"
          % (code_q, summary.strip().split("malformed=")[-1]))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("  summary line: %s" % summary.strip())
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
