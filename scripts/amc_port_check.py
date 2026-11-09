#!/usr/bin/env python3
"""Does the R5 firmware reproduce the §18 model? Compiled and measured on the host.

This is the gate that stands in for the board: the same C that the RPU will run is
compiled with gcc, fed the bursts the Python model was measured on, and compared
feature by feature and label by label. It also compiles the all-single version
(`-DAMC_SINGLE_ACC`) because the Cortex-R5F FPU has no double-precision unit, and
reports what single precision costs.

What this does NOT prove: that Embedded Coder produces the same code, that the
library links on the RPU, or that it meets the frame deadline there. Those are
G8b/G8c in docs/GATES_G1_G7.md.

Run:  python3 scripts/amc_port_check.py [--seed N] [--per-class N] [--out PATH]
"""

from __future__ import annotations

import argparse
import os
import struct
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import modulation_clustering as mc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIRMWARE = os.path.join(ROOT, "firmware", "amc_r5")
BUILD = os.path.join(ROOT, "build", "amc")
VECTORS = os.path.join(BUILD, "amc_vectors.bin")
MAGIC = 0x414D4331


def compile_and_run(tag, define=None, flags=("-O2",)):
    binary = os.path.join(BUILD, "test_amc_%s" % tag)
    command = ["gcc", *flags, "-I", FIRMWARE, "-o", binary,
               os.path.join(FIRMWARE, "test_amc.c"),
               os.path.join(FIRMWARE, "amc.c"), "-lm"]
    if define:
        command.insert(1, "-D%s" % define)
    built = subprocess.run(command, capture_output=True, text=True)
    if built.returncode != 0:
        return None, built.stderr.strip()
    run = subprocess.run([binary, VECTORS], capture_output=True, text=True)
    if run.returncode != 0:
        return None, run.stderr.strip()
    rows = []
    for line in run.stdout.strip().splitlines():
        parts = line.split()
        if len(parts) < 4 + len(mc.FEATURES):
            continue
        rows.append({"index": int(parts[0]), "truth": int(parts[1]),
                     "label": int(parts[2]), "margin": float(parts[3]),
                     "features": np.array([float(v) for v in parts[4:4 + len(mc.FEATURES)]])})
    return rows, ""


def read_vectors(path=VECTORS):
    with open(path, "rb") as handle:
        magic, count, n, nf = struct.unpack("<4i", handle.read(16))
        if magic != MAGIC:
            raise SystemExit("bad vector file")
        samples = np.frombuffer(handle.read(count * n * 2 * 4), dtype=np.float32)
        samples = samples.reshape(count, n, 2)
        reference = np.frombuffer(handle.read(count * nf * 4),
                                  dtype=np.float32).reshape(count, nf)
        truth = np.frombuffer(handle.read(count * 4), dtype=np.int32)
    return samples, reference, truth


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=20261111)
    parser.add_argument("--per-class", type=int, default=24)
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    export = subprocess.run([sys.executable,
                             os.path.join(ROOT, "scripts", "amc_export.py"),
                             "--seed", str(args.seed),
                             "--per-class", str(args.per_class)],
                            capture_output=True, text=True)
    if export.returncode != 0:
        print(export.stdout)
        print(export.stderr)
        return 1

    samples, reference, truth = read_vectors()
    count, n = samples.shape[0], samples.shape[1]

    lines = []

    def emit(text=""):
        lines.append(text)
        print(text)

    emit("V07 section 20 -- the R5 firmware against the model it must reproduce")
    emit("=" * 72)
    emit("scripts/amc_port_check.py  seed %d  %d bursts x %d samples"
         % (args.seed, count, n))
    emit("model: %s" % os.path.relpath(os.path.join(FIRMWARE, "amc_model.h"), ROOT))
    emit("firmware: %s + %s"
         % (os.path.relpath(os.path.join(FIRMWARE, "amc.c"), ROOT),
            os.path.relpath(os.path.join(FIRMWARE, "amc.h"), ROOT)))
    emit()

    results = {}
    for tag, define in (("double", None), ("single", "AMC_SINGLE_ACC")):
        rows, error = compile_and_run(tag, define)
        if rows is None:
            emit("  %s build FAILED: %s" % (tag, error.splitlines()[0] if error else "?"))
            return 1
        results[tag] = rows

    emit("P1  does the firmware return the same LABEL as the model?")
    emit("    (the model is re-derived from the features in the vector file)")
    rng = np.random.default_rng(args.seed)
    model = mc.fit(rng)
    python_labels = [mc.MODS.index(mc.classify_from_features(model, reference[i])[0])
                     for i in range(count)]
    emit("    %-8s %10s %10s" % ("build", "agree", "of"))
    for tag in ("double", "single"):
        agree = sum(1 for i, row in enumerate(results[tag])
                    if row["label"] == python_labels[i])
        emit("    %-8s %9.1f%% %9d" % (tag, 100.0 * agree / count, count))
    emit()

    emit("P2  does the firmware compute the same FEATURES?  (max |error|, per feature)")
    emit("    feature     %12s %12s   (double / single accumulator)" % ("double", "single"))
    for f, name in enumerate(mc.FEATURES):
        worst = {}
        for tag in ("double", "single"):
            worst[tag] = max(abs(row["features"][f] - reference[i][f])
                             for i, row in enumerate(results[tag]))
        emit("    %-10s %12.2e %12.2e" % (name, worst["double"], worst["single"]))
    emit()

    emit("P3  accuracy against the true class, through the firmware")
    emit("    build      accuracy")
    for tag in ("double", "single"):
        hits = sum(1 for row in results[tag] if row["label"] == row["truth"])
        emit("    %-8s %8.1f%%" % (tag, 100.0 * hits / count))
    model_hits = sum(1 for i in range(count) if python_labels[i] == truth[i])
    emit("    %-8s %8.1f%%" % ("model", 100.0 * model_hits / count))
    emit()

    emit("P4  where the single-precision build disagrees with the double one")
    flips = []
    for index in range(count):
        a = results["double"][index]["label"]
        b = results["single"][index]["label"]
        if a != b:
            flips.append((index, mc.MODS[truth[index]], mc.MODS[a], mc.MODS[b]))
    if flips:
        for index, mod, double_label, single_label in flips[:10]:
            emit("    burst %3d %-6s double %-6s single %-6s"
                 % (index, mod, double_label, single_label))
    else:
        emit("    none")
    emit()

    emit("P5  the cost side, counted rather than measured on target")
    emit("    work per burst: %d samples, one %d-point complex FFT, %d atan2,"
         % (n, n, n))
    emit("    %d sqrt, no allocation. Static buffers: 4 x %d floats = %.1f kB,"
         % (4, n, 4 * n * 4 / 1024.0))
    emit("    plus a %d-entry twiddle table (%.1f kB)." % (n // 2, n / 2 * 8 / 1024.0))
    emit("    Cycles on the R5F are NOT measured here: that is G8c.")
    emit()

    ok_double = sum(1 for i, row in enumerate(results["double"])
                    if row["label"] == python_labels[i]) == count
    worst_double = max(max(abs(row["features"][f] - reference[i][f])
                           for f in range(len(mc.FEATURES)))
                       for i, row in enumerate(results["double"]))
    single_agree = sum(1 for i, row in enumerate(results["single"])
                       if row["label"] == python_labels[i])
    checks = [
        ("the double build agrees with the model on every burst", ok_double),
        ("every feature agrees to better than 1e-3", worst_double < 1e-3),
        ("the single build agrees on at least 90 % of bursts",
         single_agree / count >= 0.9),
        ("the firmware reaches the model's own accuracy",
         abs(sum(1 for row in results["double"] if row["label"] == row["truth"])
             - model_hits) <= 0),
    ]
    for name, passed in checks:
        emit("  [%s] %s" % ("PASS" if passed else "FAIL", name))
    emit()
    result = all(passed for _, passed in checks)
    emit("RESULT=%s" % ("PASS" if result else "FAIL"))
    emit()
    emit("What this does not prove: that Embedded Coder emits this code, that the")
    emit("library links and fits the RPU memory, that a frame meets its deadline on")
    emit("the R5F, or anything about the PL. G8b and G8c are those gates.")

    path = args.out or os.path.join(ROOT, "docs", "evidence", "2026-11-06-phase-interf",
                                    "amc_port.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print()
    print("report written to %s" % os.path.relpath(path, ROOT))
    return 0 if result else 1


if __name__ == "__main__":
    raise SystemExit(main())
