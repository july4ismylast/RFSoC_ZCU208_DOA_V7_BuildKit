"""The direction estimator, in numpy, exactly as step3_r5_doa/c/doa_core.c has it.

Three stages, and the middle one is the one the question is about.

1. WPI -- weighted phase interferometry (V07 section 6)
-------------------------------------------------------
Six baselines, one phase each, and a weighted least squares for (u_y, u_z):

    phi_ab = angle(R[b,a])
    gamma  = |R[b,a]|^2 / (R[a,a] R[b,b])          coherence, 0..1
    w      = gamma/(1-gamma), clipped to [0.05, 100]
    u_yz   = -(B' W B)^-1 B' W phi / k ,           k = 2*pi*f/c

It is exact for one emitter and cheap (6 atan2 + a 2x2 solve).  It is also
unbiased but noisy: its variance is the CRLB at high SNR, so it is a good seed
and a poor finisher.

2. ML -- the maximum-likelihood direction of a *single* emitter
---------------------------------------------------------------
For one emitter the covariance is R = sigma_s^2 a(u) a(u)' + sigma_n^2 I, and
the generalised likelihood ratio reduces to the Bartlett (conventional) form

    P(u) = a(u)' R a(u) ,      a(u)_n = exp(-j k p_n . u)

so the ML direction is the maximiser of P.  There is no closed form for a 2x2
array, and a full 2-D search over +-55 deg x +-45 deg at 0.005 deg is 4e8
evaluations.  So: a local grid, then Newton.

3. Gauss-Newton -- the finisher (V07 section 6, `GNIterations = 2`)
-------------------------------------------------------------------
Newton needs the gradient and the Hessian of P.  Written against the *signal
subspace* instead of R, the same cost is

    J(theta) = || (I - v v') a(theta) ||^2 ,   v = dominant eigenvector of R

which is minimised by the same direction and whose derivatives are cheap:

    d   = d a / d theta = -j k (p . du/dtheta) .* a
    g   = 2 Re( d' (I - v v') a )                  (2x1)
    H   = 2 Re( d' (I - v v') d ) + 1e-7 I         (2x2)
    dth = H^-1 g ,  clipped to GNMaxStep_deg = 0.05 deg

Two iterations, because the cost is nearly quadratic near the peak: the first
step removes the grid residual, the second confirms it is flat.  The clip is
what keeps a bad seed from leaving the main lobe.

v is obtained by four power iterations of R -- no eigen-decomposition, which is
why this runs on an R5F without a DSP library.

Run:  python3 step3_r5_doa/py/estimator.py
"""

from __future__ import annotations

import math

import numpy as np

C_LIGHT = 299792458.0
PAIRS = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
AZ_RANGE = (-55.0, 55.0)
EL_RANGE = (-45.0, 45.0)
ML_SCHEDULE_DEG = (0.5, 0.1, 0.02, 0.005)
GN_ITERATIONS = 2
GN_MAX_STEP_DEG = 0.05


def positions(dy_m: float = 0.025, dz_m: float = 0.030) -> np.ndarray:
    """(4, 2) array of (y, z) positions -- x plays no part in the angle."""
    return np.array([[-dy_m / 2.0, -dz_m / 2.0],
                     [+dy_m / 2.0, -dz_m / 2.0],
                     [-dy_m / 2.0, +dz_m / 2.0],
                     [+dy_m / 2.0, +dz_m / 2.0]])


def direction(az_deg: float, el_deg: float) -> np.ndarray:
    az, el = math.radians(az_deg), math.radians(el_deg)
    return np.array([math.cos(el) * math.cos(az), math.cos(el) * math.sin(az),
                     math.sin(el)])


def angles(u: np.ndarray) -> tuple[float, float]:
    u = np.asarray(u, dtype=float)
    ux, uy, uz = (float(u[0]), float(u[1]), float(u[2]))
    ux2 = max(1.0 - uy * uy - uz * uz, 0.0)
    ux = math.sqrt(ux2) if ux > 0 else ux
    return math.degrees(math.atan2(uy, ux)), math.degrees(math.asin(max(-1.0, min(1.0, uz))))


def steering(points: np.ndarray, wave_number: float, u: np.ndarray) -> np.ndarray:
    """a_n = exp(-j k (p_n . u)), with points = (y, z)."""
    return np.exp(-1j * wave_number * (points @ np.asarray(u)[1:3]))


def prepare(covariance: np.ndarray, forward_backward: bool = True) -> np.ndarray:
    """What the PS does first: symmetrise, then optional forward-backward average.

    R_fb = (R + J R* J)/2 with J the exchange matrix.  It halves the variance of
    the estimate for a uniform linear/planar array at no cost, which is why V07
    sets ForwardBackwardAvg = true.
    """
    matrix = np.asarray(covariance, dtype=complex)
    matrix = 0.5 * (matrix + matrix.conj().T)
    if forward_backward:
        exchange = np.fliplr(np.eye(matrix.shape[0]))
        matrix = 0.5 * (matrix + exchange @ matrix.conj() @ exchange)
    return matrix


# --------------------------------------------------------------------------
# 1. WPI
# --------------------------------------------------------------------------
def wpi(covariance: np.ndarray, fc_hz: float = 4.0e9, dy_m: float = 0.025,
        dz_m: float = 0.030) -> tuple[float, float]:
    """Weighted least squares over the six baseline phases."""
    points = positions(dy_m, dz_m)
    baselines = np.zeros((6, 2))
    phases = np.zeros(6)
    weights = np.zeros(6)
    for index, (first, second) in enumerate(PAIRS):
        baselines[index] = points[second] - points[first]
        cross = covariance[second, first]
        phases[index] = np.angle(cross)
        power = float(np.real(covariance[first, first])
                      * np.real(covariance[second, second]))
        coherence = min(0.999, max(0.001, abs(cross) ** 2 / max(power, 1e-30)))
        weights[index] = min(100.0, max(0.05, coherence / (1.0 - coherence)))
    wave_number = 2.0 * math.pi * fc_hz / C_LIGHT
    solve = baselines.T @ (weights[:, None] * baselines) + 1e-12 * np.eye(2)
    local = -(baselines.T @ (weights * phases)) / wave_number
    u_y, u_z = np.linalg.solve(solve, local)
    norm = math.hypot(u_y, u_z)
    if norm > 0.999999:
        u_y *= 0.999999 / norm
        u_z *= 0.999999 / norm
    u_x = math.sqrt(max(1.0 - u_y ** 2 - u_z ** 2, 0.0))
    return angles(np.array([u_x, u_y, u_z]))


# --------------------------------------------------------------------------
# 2. ML: the Bartlett score and the 36-point local grid
# --------------------------------------------------------------------------
def bartlett(covariance: np.ndarray, fc_hz: float, az_deg: float, el_deg: float,
             dy_m: float = 0.025, dz_m: float = 0.030) -> float:
    """P(u) = a' R a -- the single-emitter ML cost."""
    array = steering(positions(dy_m, dz_m), 2.0 * math.pi * fc_hz / C_LIGHT,
                     direction(az_deg, el_deg))
    return float(np.real(array.conj() @ covariance @ array))


def ml_grid(covariance: np.ndarray, fc_hz: float, start: tuple[float, float],
            schedule=ML_SCHEDULE_DEG, dy_m: float = 0.025,
            dz_m: float = 0.030) -> tuple[float, float]:
    """4 stages x 3x3 = 36 evaluations, clipped to the scan ranges."""
    az_deg, el_deg = start
    for step in schedule:
        best = (-np.inf, az_deg, el_deg)
        for offset_az in (-1, 0, 1):
            for offset_el in (-1, 0, 1):
                candidate_az = min(max(az_deg + offset_az * step, AZ_RANGE[0]), AZ_RANGE[1])
                candidate_el = min(max(el_deg + offset_el * step, EL_RANGE[0]), EL_RANGE[1])
                score = bartlett(covariance, fc_hz, candidate_az, candidate_el, dy_m, dz_m)
                if score > best[0]:
                    best = (score, candidate_az, candidate_el)
        _, az_deg, el_deg = best
    return az_deg, el_deg


# --------------------------------------------------------------------------
# 3. Gauss-Newton
# --------------------------------------------------------------------------
def dominant_vector(covariance: np.ndarray, start: np.ndarray,
                    iterations: int = 4) -> np.ndarray:
    """Four power iterations -- no eigen-decomposition."""
    vector = np.asarray(start, dtype=complex)
    for _ in range(iterations):
        vector = covariance @ vector
        norm = np.linalg.norm(vector)
        vector = vector / (norm if norm > 0 else 1.0)
    return vector


def gauss_newton(covariance: np.ndarray, fc_hz: float, az_deg: float, el_deg: float,
                 iterations: int = GN_ITERATIONS, max_step_deg: float = GN_MAX_STEP_DEG,
                 dy_m: float = 0.025, dz_m: float = 0.030) -> tuple[float, float]:
    """The finisher: 2 Newton steps on J = ||(I - vv')a||^2."""
    points = positions(dy_m, dz_m)
    wave_number = 2.0 * math.pi * fc_hz / C_LIGHT
    vector = dominant_vector(covariance, steering(points, wave_number,
                                                 direction(az_deg, el_deg)))
    projector = np.eye(4) - np.outer(vector, vector.conj())
    for _ in range(iterations):
        az, el = math.radians(az_deg), math.radians(el_deg)
        unit = direction(az_deg, el_deg)
        array = steering(points, wave_number, unit)
        d_az = np.array([-math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), 0.0])
        d_el = np.array([-math.sin(el) * math.cos(az), -math.sin(el) * math.sin(az),
                         math.cos(el)])
        derivative = np.column_stack([
            -1j * wave_number * (points @ d_az[1:3]) * array,
            -1j * wave_number * (points @ d_el[1:3]) * array])
        gradient = 2.0 * np.real(derivative.conj().T @ (projector @ array))
        hessian = 2.0 * np.real(derivative.conj().T @ projector @ derivative) + 1e-7 * np.eye(2)
        delta = np.degrees(np.linalg.solve(hessian, gradient))
        norm = float(np.linalg.norm(delta))
        if norm > max_step_deg:
            delta *= max_step_deg / norm
        az_deg = min(max(az_deg - float(delta[0]), AZ_RANGE[0]), AZ_RANGE[1])
        el_deg = min(max(el_deg - float(delta[1]), EL_RANGE[0]), EL_RANGE[1])
    return az_deg, el_deg


# --------------------------------------------------------------------------
# the chain, and the tracker that consumes it
# --------------------------------------------------------------------------
def estimate(covariance: np.ndarray, fc_hz: float = 4.0e9, dy_m: float = 0.025,
             dz_m: float = 0.030, forward_backward: bool = True) -> dict:
    """WPI seed -> ML grid -> Gauss-Newton.  Returns every stage, for the bench."""
    prepared = prepare(covariance, forward_backward)
    seed = wpi(prepared, fc_hz, dy_m, dz_m)
    gridded = ml_grid(prepared, fc_hz, seed, dy_m=dy_m, dz_m=dz_m)
    refined = gauss_newton(prepared, fc_hz, gridded[0], gridded[1], dy_m=dy_m, dz_m=dz_m)
    return {"wpi": seed, "ml": gridded, "gn": refined,
            "final": refined, "bartlett_at_gn": bartlett(prepared, fc_hz, refined[0],
                                                         refined[1], dy_m, dz_m)}


def ekf_unit_vector(measurements, dt: float = 1.0, process_noise: float = 1e-4,
                    measurement_noise: float = 1e-2) -> np.ndarray:
    """6-state unit-vector EKF: state (u, du), one update per frame.

    measurements: sequence of (az_deg, el_deg).  Returns the filtered (az, el),
    which is what the RPU hands to step5 as `detections`.
    """
    state = np.zeros(6)
    state[:3] = direction(*measurements[0])
    covariance = np.eye(6) * 1e-3
    transition = np.eye(6)
    transition[:3, 3:] = np.eye(3) * dt
    process = np.eye(6) * process_noise
    measured = np.zeros((3, 6))
    measured[:, :3] = np.eye(3)
    noise = np.eye(3) * measurement_noise
    filtered = []
    for index, (az_deg, el_deg) in enumerate(measurements):
        observed = direction(az_deg, el_deg)
        if index > 0:
            state = transition @ state
            covariance = transition @ covariance @ transition.T + process
            norm = np.linalg.norm(state[:3])
            state[:3] /= norm if norm > 0 else 1.0
        innovation = observed - measured @ state
        gain = covariance @ measured.T @ np.linalg.inv(measured @ covariance @ measured.T + noise)
        state = state + gain @ innovation
        covariance = (np.eye(6) - gain @ measured) @ covariance
        norm = np.linalg.norm(state[:3])
        state[:3] /= norm if norm > 0 else 1.0
        filtered.append(angles(state[:3]))
    return np.array(filtered)


def main() -> int:
    rng = np.random.default_rng(11)
    points = positions()
    for snr_db in (0.0, 10.0, 20.0):
        covariance = np.zeros((4, 4), dtype=complex)
        azimuth, elevation = 9.0, -4.0
        unit = direction(azimuth, elevation)
        array = steering(points, 2.0 * math.pi * 4.0e9 / C_LIGHT, unit)
        payload = (rng.standard_normal(4096) + 1j * rng.standard_normal(4096))
        payload /= math.sqrt(2.0)
        snapshots = np.outer(array, payload)
        snapshots += (rng.standard_normal(snapshots.shape)
                      + 1j * rng.standard_normal(snapshots.shape)) / math.sqrt(2.0) \
            / math.sqrt(10.0 ** (snr_db / 10.0))
        covariance = snapshots @ snapshots.conj().T / snapshots.shape[1]
        result = estimate(covariance)
        print("SNR %4.1f dB  wpi %+7.3f/%+7.3f  gn %+7.3f/%+7.3f  truth %+.2f/%+.2f"
              % (snr_db, result["wpi"][0], result["wpi"][1],
                 result["gn"][0], result["gn"][1], azimuth, elevation))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
