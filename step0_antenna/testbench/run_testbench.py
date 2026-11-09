#!/usr/bin/env python3
"""Test bench for step0: the antenna model.

Five checks, each one a number a reader can re-derive by hand:

  T0.1  az/el -> unit vector -> az/el round trip            (exact, 1e-9 deg)
  T0.2  noiseless coherent scene: R is rank 1 and the baseline phase equals
        the analytic -2*pi*f*d.u/c                          (1e-9 rad)
  T0.3  the generator's measured SNR equals the requested one (+-1.0 dB)
  T0.4  the all-important one: does the *router* formula recover the direction
        from R alone?  (6-baseline weighted least squares, V07 section 6)
        The answer must be inside 0.5 deg at 20 dB.
  T0.5  ambiguity: 25 mm is un-wrapped below 5.996 GHz, 30 mm below 4.997 GHz,
        and both are below lambda/2 at 4 GHz.

Writes nothing except step0_antenna/data/ (the scenes for the later steps).

Run:  python3 step0_antenna/testbench/run_testbench.py
"""

from __future__ import annotations

import math
import pathlib
import sys

import numpy as np

STEP = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(STEP / "py"))
import array_model as model  # noqa: E402
import make_scenes  # noqa: E402

CHECKS = []
PAIRS = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]


def check(name: str, ok: bool, detail: str) -> None:
    CHECKS.append((name, bool(ok), detail))
    print("  %-4s %-46s %s" % (name, "PASS" if ok else "FAIL", detail))


def wpi_from_covariance(covariance: np.ndarray, freq_hz: float,
                        points: np.ndarray) -> tuple[float, float]:
    """V07 section 6: weighted least squares over the six baseline phases.

    u_yz = -(B' W B)^-1 B' W phi / k ,  k = 2*pi*f/c
    weight = coherence/(1-coherence), clipped to [0.05, 100]
    """
    baselines = np.zeros((6, 2))
    phases = np.zeros(6)
    weights = np.zeros(6)
    for index, (first, second) in enumerate(PAIRS):
        delta = points[second] - points[first]
        baselines[index] = delta[1:3]
        cross = covariance[second, first]
        phases[index] = np.angle(cross)
        denominator = float(np.real(covariance[first, first])
                            * np.real(covariance[second, second]))
        coherence = abs(cross) ** 2 / max(denominator, 1e-30)
        coherence = min(0.999, max(0.001, coherence))
        weights[index] = min(100.0, max(0.05, coherence / (1.0 - coherence)))
    wave_number = 2.0 * math.pi * freq_hz / model.C_LIGHT
    solve = baselines.T @ (weights[:, None] * baselines) + 1e-12 * np.eye(2)
    local = -(baselines.T @ (weights * phases)) / wave_number
    u_y, u_z = np.linalg.solve(solve, local)
    return model.angles(np.array([math.sqrt(max(1.0 - u_y ** 2 - u_z ** 2, 0.0)),
                                  u_y, u_z]))


def main() -> int:
    print("step0 -- antenna and array model")
    points = model.positions()
    report = model.array_report()

    # T0.1 round trip
    worst = 0.0
    for azimuth in (-55.0, -20.0, 0.0, 12.5, 55.0):
        for elevation in (-45.0, -7.25, 0.0, 30.0, 45.0):
            back = model.angles(model.unit_vector(azimuth, elevation))
            worst = max(worst, abs(back[0] - azimuth), abs(back[1] - elevation))
    check("T0.1", worst < 1e-9, "worst round-trip error %.2e deg" % worst)

    # T0.2 rank 1 and analytic phase, noiseless
    one = model.emitter(az=18.0, el=9.0, bandwidth_hz=100e6, snr_db=200.0)
    noiseless = model.scene(np.random.default_rng(7), [one], samples=8192)
    covariance = model.covariance(noiseless["x"])
    eigenvalues = np.linalg.eigvalsh(covariance)
    analytic = -2.0 * math.pi * model.FC_HZ * (
        (points[1] - points[0]) @ model.unit_vector(18.0, 9.0)) / model.C_LIGHT
    phase_error = abs(math.remainder(np.angle(covariance[1, 0]) - analytic, 2.0 * math.pi))
    ratio = eigenvalues[-1] / max(eigenvalues[0], 1e-300)
    check("T0.2", ratio > 1e4 and phase_error < 1e-3,
          "rank-1 eigenvalue ratio %.1e, phase error %.2e rad" % (ratio, phase_error))

    # T0.3 measured in-band SNR: occupied bins minus the out-of-band noise floor.
    # Measured from the noisy scene alone -- nothing from the generator's insides.
    rng = np.random.default_rng(11)
    for requested in (0.0, 10.0, 20.0):
        item = model.emitter(az=5.0, el=0.0, bandwidth_hz=100e6, snr_db=requested)
        noisy = model.scene(rng, [item])
        bins = np.fft.fftfreq(noisy["x"].shape[1], 1.0 / model.FS_HZ)
        mask = np.abs(bins - item["offset_hz"]) <= item["bandwidth_hz"] / 2.0
        spectra = np.fft.fft(noisy["x"], axis=1)
        floor = float(np.mean(np.abs(spectra[:, ~mask]) ** 2))
        in_band = float(np.mean(np.abs(spectra[:, mask]) ** 2)) - floor
        measured = 10.0 * math.log10(max(in_band, 1e-30) / max(floor, 1e-30))
        check("T0.3", abs(measured - requested) < 1.0,
              "requested %4.0f dB, measured %6.2f dB in band" % (requested, measured))

    # T0.4 does the estimator formula get the direction back?
    single = model.scene(np.random.default_rng(3), [
        model.emitter(az=12.5, el=-7.25, snr_db=20.0, bandwidth_hz=100e6)])
    estimate = wpi_from_covariance(model.covariance(single["x"]), model.FC_HZ, points)
    error = math.hypot(estimate[0] - 12.5, estimate[1] + 7.25)
    check("T0.4", error < 0.5,
          "az %+.2f el %+.2f deg (truth +12.50 / -7.25), error %.3f deg"
          % (estimate[0], estimate[1], error))

    # T0.5 ambiguity
    inside = (report["f_max_array_GHz"] > model.FC_HZ / 1e9
              and report["dy_over_lambda_at_fc"] < 0.5
              and report["dz_over_lambda_at_fc"] < 0.5)
    check("T0.5", inside,
          "unambiguous to %.2f GHz, dy/lambda %.2f dz/lambda %.2f at %.1f GHz"
          % (report["f_max_array_GHz"], report["dy_over_lambda_at_fc"],
             report["dz_over_lambda_at_fc"], model.FC_HZ / 1e9))

    paths = make_scenes.ensure(STEP / "data", quiet=True)
    sizes = sum(path.stat().st_size for path in paths.values()) / 1024.0
    print("  scenes: %d files, %.0f kB in step0_antenna/data/" % (len(paths), sizes))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    print("RESULT=%s (%d/%d)" % ("PASS" if passed == len(CHECKS) else "FAIL",
                                 passed, len(CHECKS)))
    return 0 if passed == len(CHECKS) else 1


if __name__ == "__main__":
    raise SystemExit(main())
