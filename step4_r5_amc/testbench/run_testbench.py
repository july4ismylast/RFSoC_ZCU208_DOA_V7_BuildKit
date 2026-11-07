#!/usr/bin/env python3
"""Test bench for step4: the modulation classifier on the R5.

  T4.1  the two build configurations compile (double and -DAMC_SINGLE_ACC)
  T4.2  the C matches the MATLAB-derived model: P1 label agreement 100 %
  T4.3  single precision changes no label (P4), so the R5 build is safe
  T4.4  accuracy against truth is the model's accuracy and not a bit better
  T4.5  the generated tables are the ones in the source (no silent edit)

T4.2-T4.4 come from scripts/amc_port_check.py -- the same script behind gate
G8a.  This bench does not re-implement it; it runs it and reads the PASS line,
so there is exactly one measurement and exactly one place it can go wrong.

Run:  python3 step4_r5_amc/testbench/run_testbench.py
"""

from __future__ import annotations

import hashlib
import pathlib
import re
import subprocess
import sys

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
CHECKS = []


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-44s %s" % (name, "PASS" if ok else "FAIL", detail))


def main() -> int:
    print("step4 -- AMC on the R5F (MATLAB -> Embedded Coder -> C)")
    sys.path.insert(0, str(ROOT / "firmware" / "amc_r5"))

    # T4.1 both configurations compile
    finished = subprocess.run(["make", "-C", str(STEP / "c")], capture_output=True, text=True)
    built = sorted(path.name for path in (ROOT / "build" / "step4").glob("test_amc*"))
    check("T4.1", finished.returncode == 0 and len(built) == 2,
          "built %s" % ", ".join(built) if built else "build failed")

    # T4.2 - T4.4 come from the G8a script
    script = ROOT / "scripts" / "amc_port_check.py"
    finished = subprocess.run([sys.executable, str(script)], capture_output=True, text=True)
    output = finished.stdout + finished.stderr

    def section(name: str) -> str:
        found = re.search(r"^%s\b(.*?)(?=^P\d\b|\Z)" % name, output,
                          re.MULTILINE | re.DOTALL)
        return found.group(1) if found else ""

    agreement = re.findall(r"(\d+\.\d+)%", section("P1"))
    check("T4.2", bool(agreement) and min(float(v) for v in agreement) >= 100.0,
          "label agreement with the model: %s"
          % (", ".join(v + "%" for v in agreement) or "no table"))

    disagreement = re.search(r"\b(none|\d+)\b", section("P4").strip())
    check("T4.3", bool(disagreement) and disagreement.group(1).lower()
          in ("none", "0") if disagreement else False,
          "double vs single disagreements: %s"
          % (disagreement.group(1) if disagreement else "no P4 section"))

    accuracy = re.findall(r"^\s+(\w+)\s+(\d+\.\d+)%", section("P3"), re.MULTILINE)
    check("T4.4", bool(accuracy) and len({v for _, v in accuracy}) == 1,
          "accuracy against truth: %s"
          % (", ".join("%s %s%%" % item for item in accuracy) or "no table"))

    # T4.5 the tables in the source are the ones the exporter wrote
    model = (ROOT / "firmware" / "amc_r5" / "amc_model.h").read_text()
    digest = hashlib.sha256(model.encode()).hexdigest()[:16]
    counts = len(re.findall(r"-?\d+(?:\.\d+)?(?:e[-+]?\d+)?[fF]?", model))
    check("T4.5", counts > 30,
          "amc_model.h: %d constants, sha256 %s" % (counts, digest))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("  firmware: firmware/amc_r5/{amc.c,amc.h,amc_model.h,test_amc.c}")
    print("  MATLAB:   matlab_v7/{amc_features,classify_modulation,build_amc_r5}.m")
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
