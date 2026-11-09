#!/usr/bin/env python3
"""Test bench for step2: the eight PL kernels.

Three kinds of answer, and the test bench is honest about which is which:

  * HOST-CHECK  -- compiles the production kernel with g++ against a host shim.
                   This runs today, on any machine, and is gate G1a/G1c.
  * GOLDEN      -- a python bit-exact model of the bridge.  Also runs today.
  * HLS         -- Vitis HLS csim + csynth + export.  Needs `vitis_hls`; the
                   test bench prints the exact command and never claims it ran.

Add a kernel by adding a row to step2_pl_ip/kernels.tsv.

Run:  python3 step2_pl_ip/testbench/run_testbench.py [--with-hls]
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
TABLE = STEP / "kernels.tsv"

CHECKS = []


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-34s %s" % (name, "PASS" if ok else "FAIL", detail))


def read_table() -> list[dict]:
    rows = []
    for line in TABLE.read_text().splitlines():
        if not line.strip() or line.startswith("#") or line.startswith("name\t"):
            continue
        fields = line.split("\t")
        if len(fields) != 6:
            raise SystemExit("bad row in kernels.tsv: %r" % (line,))
        rows.append(dict(zip(("name", "folder", "does", "host_check",
                              "hls_command", "gate"), fields)))
    return rows


def run(command: str, cwd: pathlib.Path) -> tuple[int, str]:
    finished = subprocess.run(command.split(), cwd=cwd, capture_output=True, text=True)
    return finished.returncode, (finished.stdout + finished.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--with-hls", action="store_true",
                        help="also run the Vitis HLS command (needs the tool + licence)")
    arguments = parser.parse_args()

    print("step2 -- the programmable logic")
    rows = read_table()
    print("  %d kernels in kernel order: %s"
          % (len(rows), ", ".join(row["name"] for row in rows)))

    ran = 0
    for row in rows:
        folder = ROOT / row["folder"]
        if not folder.is_dir():
            check(row["name"], False, "folder %s is missing" % row["folder"])
            continue
        if row["host_check"]:
            code, output = run(row["host_check"], ROOT)
            interesting = [line for line in output.splitlines()
                           if line.startswith("PASS") or line.startswith("FAIL")]
            check(row["name"], code == 0,
                  (interesting[-1] if interesting else "exit %d" % code)[:70])
            ran += 1

    # The production kernel compiled against the minimal host shim: the AXI beats
    # and the 16-word phase records, which is what the PS is coded against.
    code, output = run("make -C ip/custom/phase_interf_4ch host-kernel-check", ROOT)
    summary = [line for line in output.splitlines() if line.startswith("PASS")
               or line.startswith("FAIL")]
    check("phase_interf kernel", code == 0,
          (summary[-1] if summary else "no PASS line")[:70])
    ran += 1

    # HLS: report, never pretend.
    has_hls = shutil.which("vitis_hls") is not None
    pending = [row for row in rows if row["hls_command"]]
    if arguments.with_hls and has_hls:
        for row in pending:
            code, output = run(row["hls_command"], ROOT)
            summary = [line for line in output.splitlines() if "ERROR" in line
                       or "PASS" in line]
            check("hls " + row["name"], code == 0,
                  (summary[-1] if summary else "see build log")[:70])
    else:
        why = "vitis_hls not on PATH" if not has_hls else "--with-hls not given"
        print("  %-4s %-34s %s" % ("SKIP", "HLS (G2/G3/G4)", why))
        for row in pending:
            print("         %-26s %s" % (row["name"], row["hls_command"]))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("  host-checks run: %d, HLS commands pending: %d" % (ran, len(pending)))
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
