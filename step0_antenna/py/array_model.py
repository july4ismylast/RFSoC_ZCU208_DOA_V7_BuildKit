"""The 2x2 array, its geometry, and the one formula every later step uses.

Nothing here needs MATLAB, Vitis or a board: it is the *model* of the antenna,
and it is the input of everything downstream.  Run it directly to see the
array report, or import it:

    from array_model import positions, steering, scene, save
    sc = scene(np.random.default_rng(1), [dict(az=12.0, el=-5.0, ...)])
    save("data/scene_basic.npz", sc)

Geometry (V07 sections 3-4)
--------------------------
Four elements in one plane, element spacing along +y and +z:

    p0 = (0, -dy/2, -dz/2)      p1 = (0, +dy/2, -dz/2)
    p2 = (0, -dy/2, +dz/2)      p3 = (0, +dy/2, +dz/2)

    dy = 25 mm (azimuth baseline pair CH1-CH2)
    dz = 30 mm (elevation baseline pair CH1-CH3)
    lever = 150 mm  -> the array's offset from the platform reference point.
                      It does NOT enter the direction estimate; it only enters
                      the platform transform (matlab_v7/PlatformDynamics3D.m).

The signal model, one emitter at direction u, RF frequency f:

    X_n(k) = exp(-j*2*pi*f_k*(p_n . u)/c) * S(k) + N_n(k)
    R      = X * X' / K                      (4x4, what PL sends to the PS)

so one baseline pair (a, b) carries the phase

    angle(R[b,a]) = -2*pi*f*d_ab.u/c      =>   u_ab = -angle(R[b,a])*c/(2*pi*f*|d_ab|)

Unambiguous frequency
---------------------
A baseline d measures |d.u| without a wrap only while d < lambda/2:

    f_max = c / (2*d)     ->  25 mm: 5.996 GHz     30 mm: 4.997 GHz

Above f_max the phase wraps and two directions give the same number: that is
the ambiguity of G6 (chamber) and the reason `ambiguity / wrap` exists as a
separate block on the R5 in step3.
"""

from __future__ import annotations

import json
import math
import pathlib

import numpy as np

C_LIGHT = 299792458.0
DY_M = 0.025
DZ_M = 0.030
LEVER_X_M = 0.150
FS_HZ = 2.0e9
FC_HZ = 4.0e9
SAMPLES = 4096


# --------------------------------------------------------------------------
# geometry
# --------------------------------------------------------------------------
def positions(dy: float = DY_M, dz: float = DZ_M, lever: float = LEVER_X_M) -> np.ndarray:
    """The four element positions, metres, in the platform frame."""
    return np.array([[lever, -dy / 2.0, -dz / 2.0],
                     [lever, +dy / 2.0, -dz / 2.0],
                     [lever, -dy / 2.0, +dz / 2.0],
                     [lever, +dy / 2.0, +dz / 2.0]])


def unit_vector(az_deg: float, el_deg: float) -> np.ndarray:
    """Azimuth/elevation (degrees, boresight +x) to a unit vector."""
    azimuth = math.radians(az_deg)
    elevation = math.radians(el_deg)
    return np.array([math.cos(elevation) * math.cos(azimuth),
                     math.cos(elevation) * math.sin(azimuth),
                     math.sin(elevation)])


def angles(u: np.ndarray) -> tuple[float, float]:
    """The inverse of `unit_vector`, in degrees."""
    norm = float(np.linalg.norm(u))
    u = np.asarray(u, dtype=float) / (norm if norm > 0 else 1.0)
    elevation = math.degrees(math.asin(max(-1.0, min(1.0, float(u[2])))))
    azimuth = math.degrees(math.atan2(float(u[1]), float(u[0])))
    return azimuth, elevation


def steering(points: np.ndarray, freqs_hz, u: np.ndarray) -> np.ndarray:
    """A[n, k] = exp(-j*2*pi*f_k*(p_n . u)/c).  Shape (4, len(freqs))."""
    projection = np.asarray(points, dtype=float) @ np.asarray(u, dtype=float)
    freqs = np.atleast_1d(np.asarray(freqs_hz, dtype=float))
    return np.exp(-1j * 2.0 * np.pi * np.outer(projection, freqs) / C_LIGHT)


def ambiguity_fmax(spacing_m: float) -> float:
    """Highest RF frequency at which `spacing_m` still measures phase un-wrapped."""
    return C_LIGHT / (2.0 * abs(spacing_m))


def array_report(dy: float = DY_M, dz: float = DZ_M) -> dict:
    """The numbers the antenna section of the documentation quotes."""
    return {
        "dy_mm": dy * 1e3,
        "dz_mm": dz * 1e3,
        "f_max_dy_GHz": ambiguity_fmax(dy) / 1e9,
        "f_max_dz_GHz": ambiguity_fmax(dz) / 1e9,
        "f_max_array_GHz": min(ambiguity_fmax(dy), ambiguity_fmax(dz)) / 1e9,
        "lambda_mm_at_fc": C_LIGHT / FC_HZ * 1e3,
        "dy_over_lambda_at_fc": dy / (C_LIGHT / FC_HZ),
        "dz_over_lambda_at_fc": dz / (C_LIGHT / FC_HZ),
        "beamwidth_az_deg": 0.886 * (C_LIGHT / FC_HZ) / (2.0 * dy) * 180.0 / math.pi,
        "beamwidth_el_deg": 0.886 * (C_LIGHT / FC_HZ) / (2.0 * dz) * 180.0 / math.pi,
    }


# --------------------------------------------------------------------------
# the scene: four channels of complex baseband, plus the truth
# --------------------------------------------------------------------------
def emitter(az: float, el: float, offset_hz: float = 0.0, bandwidth_hz: float = 100e6,
            snr_db: float = 20.0, modulation: str = "QPSK", delay_ns: float = 0.0) -> dict:
    """One emitter, as every later step wants to see it."""
    return {"az_deg": float(az), "el_deg": float(el), "offset_hz": float(offset_hz),
            "bandwidth_hz": float(bandwidth_hz), "snr_db": float(snr_db),
            "modulation": modulation, "delay_ns": float(delay_ns), "decoy": bool(delay_ns)}


def scene(rng, emitters, samples: int = SAMPLES, fs_hz: float = FS_HZ,
          fc_hz: float = FC_HZ, points: np.ndarray | None = None) -> dict:
    """Four channels of complex baseband at fs, one FFT bin per 488 kHz."""
    points = positions() if points is None else points
    bins = np.fft.fftfreq(samples, 1.0 / fs_hz)
    spectra = np.zeros((4, samples), dtype=complex)
    for item in emitters:
        mask = np.abs(bins - item["offset_hz"]) <= item["bandwidth_hz"] / 2.0
        if not mask.any():
            continue
        count = int(mask.sum())
        payload = (rng.standard_normal(count) + 1j * rng.standard_normal(count)) / math.sqrt(2.0)
        gain = 1.0 / math.sqrt(count)          # unit power per channel
        spectra[:, mask] += steering(points, fc_hz + bins[mask], unit_vector(
            item["az_deg"], item["el_deg"])) * payload * gain
    # snr_db is the IN-BAND SNR: the power inside the occupied bins divided by the
    # noise power in those same bins.  That is the number the PS sees per bin, and
    # the number the studies in scripts/ are quoted against.
    occupied = np.zeros(samples, dtype=bool)
    for item in emitters:
        occupied |= np.abs(bins - item["offset_hz"]) <= item["bandwidth_hz"] / 2.0
    in_band = (float(np.mean(np.abs(spectra[:, occupied]) ** 2)) if occupied.any()
               else float(np.mean(np.abs(spectra) ** 2)))
    noise_power = in_band / (10.0 ** (emitters[0]["snr_db"] / 10.0))
    noise = (rng.standard_normal(spectra.shape) + 1j * rng.standard_normal(spectra.shape))
    spectra += noise * math.sqrt(noise_power / 2.0)
    time_domain = np.fft.ifft(spectra, axis=1)
    return {"x": time_domain.astype(np.complex128), "truth": {"emitters": emitters,
            "fs_hz": fs_hz, "fc_hz": fc_hz, "samples": samples}}


def covariance(x: np.ndarray) -> np.ndarray:
    """The 4x4 the PL accumulates: R = X X' / K."""
    data = np.asarray(x, dtype=complex)
    return data @ data.conj().T / data.shape[1]


def save(path, scene_dict: dict) -> pathlib.Path:
    """Write one scene as .npz data + .json truth (the contract of step0)."""
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(target, x=scene_dict["x"])
    target.with_suffix(".json").write_text(json.dumps(scene_dict["truth"], indent=2) + "\n")
    return target


def load(path) -> dict:
    """Read a scene written by `save`."""
    source = pathlib.Path(path)
    with np.load(source) as archive:
        x = archive["x"]
    truth = json.loads(source.with_suffix(".json").read_text())
    return {"x": x, "truth": truth}


def angle_sigma_deg(snr_db: float, snapshots: int = SAMPLES, freq_hz: float = FC_HZ,
                    baseline_m: float = DY_M) -> float:
    """1-sigma angle error of one baseline pair, from its phase error.

    sigma_phi = 1 / sqrt(2*K*SNR)   (independent Gaussian noise, K snapshots)
    sigma_u   = sigma_phi * c/(2*pi*f*d)  =  sigma_phi*lambda/(2*pi*d)
    At boresight a direction-cosine error equals the angle error in radians.
    """
    snr = 10.0 ** (snr_db / 10.0)
    sigma_phase = 1.0 / math.sqrt(2.0 * max(snapshots, 1) * snr)
    return math.degrees(sigma_phase * (C_LIGHT / freq_hz) / (2.0 * math.pi * baseline_m))


def main() -> int:
    report = array_report()
    print("2x2 array, one plane (V07 section 4)")
    print("  dy = %.1f mm   dz = %.1f mm   lever = %.1f mm"
          % (report["dy_mm"], report["dz_mm"], LEVER_X_M * 1e3))
    print("  lambda at %.1f GHz = %.1f mm" % (FC_HZ / 1e9, report["lambda_mm_at_fc"]))
    print("  dy/lambda = %.3f   dz/lambda = %.3f"
          % (report["dy_over_lambda_at_fc"], report["dz_over_lambda_at_fc"]))
    print("  unambiguous up to %.3f GHz (dy) and %.3f GHz (dz)"
          % (report["f_max_dy_GHz"], report["f_max_dz_GHz"]))
    print("  nominal beamwidth %.1f deg (az) x %.1f deg (el)"
          % (report["beamwidth_az_deg"], report["beamwidth_el_deg"]))
    print("  sigma(angle) at 4096 snapshots, 25 mm baseline:")
    for snr in (0.0, 5.0, 10.0, 20.0):
        print("    SNR %4.1f dB -> %8.4f deg   %s"
              % (snr, angle_sigma_deg(snr), "within 0.5 deg" if
                 angle_sigma_deg(snr) <= 0.5 else "above the 0.5 deg budget"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
