#!/usr/bin/env python3
"""Test bench for step1: the capture record, the ADC and the MTS clock.

  T1.1  write -> read returns the same numbers, bit for bit
  T1.2  the 12-bit quantiser sits where the text book says (6.02B+1.76)
  T1.3  one picosecond of MTS skew is worth the angle error predicted by the
        closed form -- and the budget for 0.5 deg comes out at 0.73 ps
  T1.4  the loopback delay is recovered exactly in simulation, and the reader
        sees why one sample is 0.5 ns (15 cm), i.e. G5 measures bulk delay
  T1.5  the capture file round-trips through step0's covariance without change
        of meaning: the direction from R(file) equals the direction from R(x)

Run:  python3 step1_rfadc_mts/testbench/run_testbench.py
"""

from __future__ import annotations

import math
import pathlib
import sys

import numpy as np

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
sys.path.insert(0, str(STEP / "py"))
sys.path.insert(0, str(ROOT / "step0_antenna" / "py"))
import capture_format as capture  # noqa: E402
import array_model as model  # noqa: E402

CHECKS = []
PAIRS = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-52s %s" % (name, "PASS" if ok else "FAIL", detail))


def direction_from_covariance(covariance: np.ndarray, freq_hz: float,
                              points: np.ndarray) -> tuple[float, float]:
    """The six-baseline weighted least squares of V07 section 6."""
    baselines = np.zeros((6, 2))
    phases = np.zeros(6)
    weights = np.zeros(6)
    for index, (first, second) in enumerate(PAIRS):
        baselines[index] = (points[second] - points[first])[1:3]
        cross = covariance[second, first]
        phases[index] = np.angle(cross)
        denominator = float(np.real(covariance[first, first])
                            * np.real(covariance[second, second]))
        coherence = min(0.999, max(0.001, abs(cross) ** 2 / max(denominator, 1e-30)))
        weights[index] = min(100.0, max(0.05, coherence / (1.0 - coherence)))
    wave_number = 2.0 * math.pi * freq_hz / model.C_LIGHT
    solve = baselines.T @ (weights[:, None] * baselines) + 1e-12 * np.eye(2)
    local = -(baselines.T @ (weights * phases)) / wave_number
    u_y, u_z = np.linalg.solve(solve, local)
    return model.angles(np.array([math.sqrt(max(1.0 - u_y ** 2 - u_z ** 2, 0.0)),
                                  u_y, u_z]))


def main() -> int:
    print("step1 -- RF-ADC, MTS clock and the capture record")
    rng = np.random.default_rng(20261107)
    points = model.positions()
    source = model.scene(rng, [model.emitter(az=-6.0, el=3.5, snr_db=25.0,
                                            bandwidth_hz=200e6)])
    x = source["x"]
    out = STEP / "data" / "capture_burst.bin"

    # T1.1 round trip
    written = capture.write_capture(out, x, model.FS_HZ, model.FC_HZ, bits=12)
    back, header = capture.read_capture(out)
    deltas = np.abs(back - np.ascontiguousarray(
        (np.round(x.real * written["scale"]) + 1j * np.round(x.imag * written["scale"]))
        / written["scale"]))
    check("T1.1", float(np.max(deltas)) < 1e-9 and header["samples"] == x.shape[1],
          "%d bytes, %d ch x %d samples, max round-trip error %.1e"
          % (written["bytes"], header["channels"], header["samples"], float(np.max(deltas))))

    # T1.2 quantiser against the textbook
    report = capture.quantisation_report(x, 12)
    check("T1.2", abs(report["sqnr_db"] - report["ideal_db"]) < 2.0,
          "SQNR %.2f dB, crest-corrected ideal %.2f dB (textbook %.1f, crest %.1f dB)"
          % (report["sqnr_db"], report["ideal_db"], report["textbook_db"],
             report["crest_db"]))

    # T1.3 MTS skew: measured against the closed form
    skew = 1e-12
    predicated = capture.skew_angle_error_deg(skew)
    clean = direction_from_covariance(model.covariance(x), model.FC_HZ, points)
    skewed_x = capture.apply_skew(x, np.array([0.0, skew, 0.0, skew]),
                                  model.FS_HZ, model.FC_HZ)
    shifted = direction_from_covariance(model.covariance(skewed_x), model.FC_HZ, points)
    measured = math.hypot(shifted[0] - clean[0], shifted[1] - clean[1])
    budget_ps = capture.skew_budget_s(0.5) * 1e12
    check("T1.3", abs(measured - predicated) / predicated < 0.1 and 0.6 < budget_ps < 0.9,
          "1.00 ps -> %.3f deg (formula %.3f deg); 0.5 deg budget = %.2f ps"
          % (measured, predicated, budget_ps))

    # T1.4 loopback: a delay we injected, recovered
    truth_samples = 37
    tx = ((rng.standard_normal(4096) + 1j * rng.standard_normal(4096)) / math.sqrt(2.0))
    rx = np.roll(tx, truth_samples)
    pair = np.stack([tx, rx])
    found = capture.loopback_delay(pair, model.FS_HZ)
    check("T1.4", abs(found["lag_samples"]) == truth_samples,
          "injected %d samples -> found %d (%.2f ns, resolution %.2f ns = %.1f cm)"
          % (truth_samples, found["lag_samples"], found["delay_ns"],
             found["resolution_ns"], found["resolution_cm"]))

    # T1.5 the file still means the same thing downstream
    from_file = direction_from_covariance(model.covariance(back), model.FC_HZ, points)
    from_x = direction_from_covariance(model.covariance(x), model.FC_HZ, points)
    drift = math.hypot(from_file[0] - from_x[0], from_file[1] - from_x[1])
    check("T1.5", drift < 0.05 and abs(from_x[0] + 6.0) < 0.5,
          "az from file %+.3f, from x %+.3f (truth -6.00), drift %.4f deg"
          % (from_file[0], from_x[0], drift))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
