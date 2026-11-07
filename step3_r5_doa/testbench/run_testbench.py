#!/usr/bin/env python3
"""Test bench for step3: WPI -> ML -> Gauss-Newton, and the C that would run on R5.

  T3.1  WPI alone recovers the direction of one emitter inside 0.5 deg
  T3.2  ML + Gauss-Newton is never worse than its seed, and lands inside 0.5 deg
  T3.3  the C core (step3_r5_doa/c/doa_core.c, compiled -O2) agrees with the
        numpy reference to 1e-6 deg over 24 random cases -- same algorithm,
        two implementations, no drift
  T3.4  the error against SNR: the table the accuracy budget is built on
  T3.5  the 6-state unit-vector EKF smooths a moving target (step0's series)
  T3.6  two emitters: the estimator fails, on purpose, with a number.  An array
        of four elements cannot represent two directions (V07 section 10).

Needs gcc.  No MATLAB, no Vitis, no board.

Run:  python3 step3_r5_doa/testbench/run_testbench.py
"""

from __future__ import annotations

import ctypes
import json
import math
import pathlib
import subprocess
import sys

import numpy as np

STEP = pathlib.Path(__file__).resolve().parent.parent
ROOT = STEP.parent
sys.path.insert(0, str(STEP / "py"))
sys.path.insert(0, str(ROOT / "step0_antenna" / "py"))
import array_model as model  # noqa: E402
import estimator  # noqa: E402
import make_scenes  # noqa: E402

CHECKS = []
LIBRARY = ROOT / "build" / "step3" / "libdoa_core.so"


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-40s %s" % (name, "PASS" if ok else "FAIL", detail))


def build_library() -> bool:
    finished = subprocess.run(["make", "-C", str(STEP / "c")], capture_output=True, text=True)
    return finished.returncode == 0 and LIBRARY.exists()


def load_library():
    library = ctypes.CDLL(str(LIBRARY))
    pointer = ctypes.POINTER(ctypes.c_double)
    library.doa_estimate.argtypes = [pointer, pointer, ctypes.c_double, ctypes.c_double,
                                     ctypes.c_double, ctypes.c_int, pointer]
    library.doa_estimate.restype = ctypes.c_int
    library.doa_wpi.argtypes = [pointer, pointer, ctypes.c_double, ctypes.c_double,
                                ctypes.c_double, pointer]
    library.doa_wpi.restype = ctypes.c_int
    return library


def c_estimate(library, covariance: np.ndarray, full: bool = True):
    matrix = estimator.prepare(covariance)
    real = np.ascontiguousarray(matrix.real.reshape(-1), dtype=np.float64)
    imaginary = np.ascontiguousarray(matrix.imag.reshape(-1), dtype=np.float64)
    out = (ctypes.c_double * 2)()
    if full:
        code = library.doa_estimate(real.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                                    imaginary.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                                    model.FC_HZ, model.DY_M, model.DZ_M, 2, out)
    else:
        code = library.doa_wpi(real.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                               imaginary.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
                               model.FC_HZ, model.DY_M, model.DZ_M, out)
    if code != 0:
        raise RuntimeError("doa core returned %d" % code)
    return out[0], out[1]


def snapshots_covariance(rng, azimuth: float, elevation: float, snr_db: float,
                         count: int = 4096) -> np.ndarray:
    """One emitter, `count` snapshots, in-band SNR -- covariance only."""
    array = estimator.steering(estimator.positions(model.DY_M, model.DZ_M),
                               2.0 * math.pi * model.FC_HZ / model.C_LIGHT,
                               estimator.direction(azimuth, elevation))
    payload = (rng.standard_normal(count) + 1j * rng.standard_normal(count)) / math.sqrt(2.0)
    data = np.outer(array, payload)
    noise = 1.0 / math.sqrt(10.0 ** (snr_db / 10.0))
    data = data + noise * (rng.standard_normal(data.shape)
                           + 1j * rng.standard_normal(data.shape)) / math.sqrt(2.0)
    return data @ data.conj().T / count


def error_of(estimate, truth) -> float:
    return math.hypot(estimate[0] - truth[0], estimate[1] - truth[1])


def main() -> int:
    print("step3 -- the direction estimator (WPI -> ML -> Gauss-Newton)")
    if not build_library():
        print("  cannot build the C core: install gcc")
        return 1
    library = load_library()
    paths = make_scenes.ensure(STEP.parent / "step0_antenna" / "data", quiet=True)

    # T3.1 / T3.2 on the committed scene
    scene = model.load(paths["scene_single"])
    truth = (scene["truth"]["emitters"][0]["az_deg"], scene["truth"]["emitters"][0]["el_deg"])
    covariance = model.covariance(scene["x"])
    result = estimator.estimate(covariance)
    wpi_error = error_of(result["wpi"], truth)
    gn_error = error_of(result["gn"], truth)
    check("T3.1", wpi_error < 0.5,
          "WPI az %+.3f el %+.3f, truth %+.2f/%+.2f, error %.3f deg"
          % (result["wpi"][0], result["wpi"][1], truth[0], truth[1], wpi_error))
    check("T3.2", gn_error <= wpi_error + 1e-3 and gn_error < 0.5,
          "GN az %+.3f el %+.3f, error %.3f deg (WPI %.3f, grid 36 points)"
          % (result["gn"][0], result["gn"][1], gn_error, wpi_error))

    # T3.3 C vs numpy
    rng = np.random.default_rng(99)
    worst = 0.0
    for _ in range(24):
        azimuth = float(rng.uniform(-40.0, 40.0))
        elevation = float(rng.uniform(-25.0, 25.0))
        snr_db = float(rng.uniform(0.0, 20.0))
        matrix = snapshots_covariance(rng, azimuth, elevation, snr_db, 512)
        from_c = c_estimate(library, matrix)
        from_py = estimator.estimate(matrix)["gn"]
        worst = max(worst, error_of(from_c, from_py))
    check("T3.3", worst < 1e-6,
          "24 random cases, worst |C - numpy| = %.2e deg" % worst)

    # T3.4 SNR table
    rng = np.random.default_rng(4)
    table = []
    for snr_db in (0.0, 10.0, 20.0):
        errors = []
        for _ in range(8):
            azimuth = float(rng.uniform(-30.0, 30.0))
            elevation = float(rng.uniform(-20.0, 20.0))
            matrix = snapshots_covariance(rng, azimuth, elevation, snr_db)
            errors.append(error_of(estimator.estimate(matrix)["gn"], (azimuth, elevation)))
        table.append((snr_db, float(np.mean(errors)), float(np.max(errors))))
        print("         SNR %4.0f dB  mean error %6.3f deg  worst %6.3f deg"
              % table[-1])
    check("T3.4", table[-1][1] < 0.2 and table[0][1] < 1.5,
          "mean error %.3f deg at 20 dB, %.3f deg at 0 dB"
          % (table[-1][1], table[0][1]))

    # T3.5 EKF smoothing on step0's mover
    series = model.load(paths["series_mover"])
    frames = series["x"]
    truth_angles = [(item["az_deg"], item["el_deg"])
                    for item in series["truth"]["emitters"]]
    measured = np.array([estimator.estimate(model.covariance(frame))["gn"]
                         for frame in frames])
    smoothed = estimator.ekf_unit_vector([tuple(pair) for pair in measured], dt=1.0,
                                         process_noise=1e-6, measurement_noise=1e-3)
    raw_error = float(np.mean([error_of(pair[0], pair[1])
                               for pair in zip(measured, truth_angles)]))
    smooth_error = float(np.mean([error_of(pair[0], pair[1])
                                  for pair in zip(smoothed, truth_angles)]))

    def acceleration(series: np.ndarray) -> float:
        """RMS of the second difference: 0 for a constant-rate mover, sqrt(6)*sigma
        of the noise otherwise.  This is the part of the track that is jitter."""
        return float(np.sqrt(np.mean(np.diff(series[:, 0], 2) ** 2)))

    raw_jitter = acceleration(measured)
    smooth_jitter = acceleration(smoothed)
    check("T3.5", smooth_jitter < 0.8 * raw_jitter and smooth_error <= raw_error + 0.02,
          "EKF %d frames: jitter %.3f -> %.3f, error %.3f -> %.3f deg"
          % (len(frames), raw_jitter, smooth_jitter, raw_error, smooth_error))

    # T3.6 two emitters: the documented failure
    two = model.load(paths["scene_two"])
    emitters = two["truth"]["emitters"]
    result_two = estimator.estimate(model.covariance(two["x"]))
    worst_error = min(error_of(result_two["gn"],
                               (item["az_deg"], item["el_deg"])) for item in emitters)
    check("T3.6", worst_error > 2.0,
          "two emitters -> az %+.2f, nearest truth is %.2f deg away (manifold rank)"
          % (result_two["gn"][0], worst_error))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
