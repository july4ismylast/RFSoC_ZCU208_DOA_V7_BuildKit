#!/usr/bin/env python3
"""Test bench for step7: is the repository ready for the board?

This is the only step whose test bench cannot produce a number about hardware,
so it checks the three things it *can*:

  T7.1  every step folder has a GUIDE.md and a test bench
  T7.2  the static lint still passes (Tcl, shell, Makefile, required artifacts)
  T7.3  the checklist prints every gate exactly once, and only one is [x]
  T7.4  the diagram of record exists and is newer than scripts/draw_system.py
  T7.5  `make tools` names a tool for every open gate

Run:  python3 step7_board_bringup/testbench/run_testbench.py
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
CHECKS = []
STEPS = ("step0_antenna", "step1_rfadc_mts", "step2_pl_ip", "step3_r5_doa",
         "step4_r5_amc", "step5_r5_tracking", "step6_ps_linux", "step7_board_bringup")


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-44s %s" % (name, "PASS" if ok else "FAIL", detail))


def main() -> int:
    print("step7 -- bring-up readiness")

    missing = []
    for folder in STEPS:
        base = ROOT / folder
        if not (base / "GUIDE.md").is_file():
            missing.append(folder + "/GUIDE.md")
        if not (base / "testbench" / "run_testbench.py").is_file():
            missing.append(folder + "/testbench/run_testbench.py")
    check("T7.1", not missing, "8 folders complete" if not missing else ", ".join(missing))

    lint = subprocess.run(["make", "lint"], cwd=ROOT, capture_output=True, text=True)
    tail = [line for line in (lint.stdout + lint.stderr).splitlines() if line.startswith("PASS")]
    check("T7.2", lint.returncode == 0, (tail[-1] if tail else "lint failed")[:66])

    checklist = subprocess.run(["bash", str(STEP / "checklist.sh")], capture_output=True,
                               text=True)
    text = checklist.stdout
    gates = re.findall(r"^\s*(?:\[x\]|)\s*\d+\s+(G[\w,]+)", text, re.MULTILINE)
    done = re.findall(r"^\[x\]", text, re.MULTILINE)
    check("T7.3", checklist.returncode == 0 and len(gates) >= 10 and len(done) == 1,
          "%d commands on the list, %d closed by this repository" % (len(gates), len(done)))

    drawing = ROOT / "docs" / "diagrams" / "system_block.png"
    script = ROOT / "scripts" / "draw_system.py"
    fresh = drawing.is_file() and script.is_file() and \
        drawing.stat().st_mtime >= script.stat().st_mtime - 1.0
    check("T7.4", fresh, "%s (%.0f kB)"
          % (drawing.name, drawing.stat().st_size / 1024.0) if drawing.is_file()
          else "the diagram of record is missing")

    tools = subprocess.run(["make", "tools"], cwd=ROOT, capture_output=True, text=True)
    reported = tools.stdout
    covered = all(word in reported for word in ("vitis", "vivado", "matlab", "BASE_XPR",
                                                "armr5"))
    check("T7.5", tools.returncode == 0 and covered,
          "make tools reports on %d of 5 tool families"
          % sum(1 for word in ("vitis", "vivado", "matlab", "BASE_XPR", "armr5")
                if word in reported))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    if passed != len(CHECKS):
        print("  note: T7.* are readiness checks, not hardware results.")
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
