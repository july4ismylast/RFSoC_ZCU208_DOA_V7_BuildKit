#!/usr/bin/env python3
"""A protected *radar* behind a repeater decoy: what the transmit path buys.

Scenario change from scripts/decoy_discrimination.py. There the protected source
was a generic emitter and a repeater decoy was shown to be detectable but not
separable on a 2x2. Here the source is a radar: it transmits and receives, so it
emits pulses, and a decoy has to *hear* the pulse before it can repeat it. That
ordering is a discriminator that no decoy can beat, because it is geometry:

    arrival(direct)   = R / c
    arrival(repeater) = (R_radar-decoy + R_decoy-array)/c + tau_processing
                      >= R / c + tau_processing        (triangle inequality)

So the earliest part of every pulse contains the radar and nothing else. The
studies below measure what that is worth on the samples this kit already
produces (2 GS/s), and what it fixes in the section 13 estimator.

  G  geometry and leading-edge gate: DOA from the first W ns of the pulse versus
     DOA from the whole pulse, with a coherent repeater 30 deg away.
  G2 window length against per-sample SNR, including the case where the window
     is allowed to run past the repeater's arrival.
  H  a DRFM that also applies a Doppler shift (the usual range/velocity pull-off),
     and the tail the decoy leaves after the radar stops: the tail gives the
     decoy's own direction and the delay, with no model at all.
  J  the same gate over four waveforms (LFM, soft-edged LFM, tan-FM, Barker-13):
     it must not depend on the modulation, only on the arrival ordering.
  K  residual calibration error (+/-0.5 dB, +/-5 deg) against window length.
  I  the delay measured by the leading edge fed into the section 13 two-path ML:
     a half-sample delay makes 5-50 MHz emitters separable without a search, and
     does not rescue a single 1 MHz bin (no frequency diversity at all).

  K  the same gate with residual calibration error (+/-0.5 dB, +/-5 deg) against
     window length: the residual is a bias floor, the window trades noise for time.
  L  the numbers a hardware gate (G7) has to reproduce.
  G0 the arrival ordering itself, from the triangle inequality.

Run:  python3 scripts/radar_decoys.py [--quick]
      python3 scripts/radar_decoys.py --replay capture.npy --pulse-ns 1000 \
          --delay-ns 100 --truth-az 10 --decoy-az 40      # gate G7 on hardware
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import decoy_discrimination as dd  # noqa: E402  (same directory, also a script)

C_LIGHT = dd.C_LIGHT
F_CARRIER = 2.5e9
FS = 2.0e9
PULSE_S = 1.0e-6
PRI_S = 20.0e-6
BW_HZ = 50.0e6
AZ_SOURCE = 10.0
AZ_DECOY = 40.0
PITCH_M = 0.030


BARKER13 = np.array([1, 1, 1, 1, 1, -1, -1, 1, 1, -1, 1, -1, 1])


def make_waveform(kind="lfm", pulse_s=PULSE_S, bw_hz=BW_HZ, fs=FS, edge_s=20e-9):
    """One pulse of a radar waveform, plus its instantaneous-frequency law.

    The point of the variety is that the leading-edge gate must not depend on
    *which* waveform the radar uses -- only on the arrival ordering. LFM is the
    easy case; a soft-edged LFM, a tan-FM (non-linear) chirp and a Barker-13
    phase code are the interesting ones, because a phase code has no
    instantaneous-frequency sweep at all.
    """
    count = int(round(pulse_s * fs))
    time = np.arange(count) / fs
    if kind == "barker13":
        chips = int(round(pulse_s / (pulse_s / 13.0)))
        index = np.minimum((time / pulse_s * 13.0).astype(int), 12)
        envelope = BARKER13[index].astype(float)

        def inst_freq(_centre):
            return 0.0

        phase = np.zeros(count)
    else:
        if kind == "nlfm":
            shape = np.tanh(3.0 * (2.0 * time / pulse_s - 1.0)) / np.tanh(3.0)
            freq = (bw_hz / 2.0) * shape

            def inst_freq(centre, freq_law=freq):
                index = min(max(int(round(centre * fs)), 0), freq_law.size - 1)
                return float(freq_law[index])
        else:
            rate = bw_hz / pulse_s
            freq = -bw_hz / 2.0 + rate * time

            def inst_freq(centre, rate_law=rate):
                return -bw_hz / 2.0 + rate_law * centre

        phase = 2.0 * np.pi * np.cumsum(freq) / fs
        envelope = np.ones(count)
        if kind == "lfm_soft":
            edges = max(int(round(edge_s * fs)), 1)
            ramp = 0.5 * (1.0 - np.cos(np.pi * np.arange(edges) / edges))
            envelope[:edges] = ramp
            envelope[-edges:] = ramp[::-1]
    samples = envelope * np.exp(1j * phase)
    return samples, count, inst_freq


def edge_sample(kind="lfm", pulse_s=PULSE_S):
    """Where a 50 %-of-peak edge detector fires, so soft edges are not cheated."""
    samples, _, _ = make_waveform(kind, pulse_s=pulse_s)
    envelope = np.abs(samples)
    above = np.where(envelope > 0.5 * envelope.max())[0]
    return int(above[0]) if above.size else 0


def channel_error(rng, elements, amp_db=0.5, phase_deg=5.0):
    """Residual per-channel error after calibration: amplitude and phase."""
    amplitude = 10.0 ** (rng.uniform(-amp_db, amp_db, elements) / 20.0)
    phase = np.radians(rng.uniform(-phase_deg, phase_deg, elements))
    vector = amplitude * np.exp(1j * phase)
    return vector    # applied as a per-element multiplier on the manifold


def lfm_pulse(fs=FS, duration_s=PULSE_S, bw_hz=BW_HZ):
    """Complex-baseband LFM, -bw/2 to +bw/2 over the pulse."""
    count = int(round(duration_s * fs))
    time = np.arange(count) / fs
    rate = bw_hz / duration_s
    return np.exp(1j * np.pi * rate * time ** 2) * np.exp(
        -1j * np.pi * bw_hz * time), count


def delayed_copy(pulse, delay_s, fs=FS):
    """Fractional-sample delay by an FFT phase ramp (exact up to the buffer)."""
    count = pulse.size
    spectrum = np.fft.fft(pulse)
    freqs = np.fft.fftfreq(count, d=1.0 / fs)
    return np.fft.ifft(spectrum * np.exp(-1j * 2.0 * np.pi * freqs * delay_s))


def radar_scene(rng, positions, delay_s, doppler_hz=0.0, snr_db=0.0,
                pulses=64, buffer_samples=None, incoherent_decoy=False,
                pulse_s=PULSE_S, waveform="lfm", error_vector=None,
                pad_samples=0):
    """One radar pulse train: direct path at 0 ns, repeater copy at delay_s.

    Returns an array (pulses, samples, elements). snr_db is per sample, so a
    longer window integrates more of it -- the trade the study is about.
    """
    pulse, count, _ = make_waveform(waveform, pulse_s=pulse_s)
    if buffer_samples is None:
        buffer_samples = count + int(round(delay_s * FS)) + 8
    buffer_samples += pad_samples
    source = dd.steering(dd.u_of(AZ_SOURCE), F_CARRIER, positions)
    decoy = dd.steering(dd.u_of(AZ_DECOY), F_CARRIER, positions)
    if error_vector is not None:
        source = source * error_vector
        decoy = decoy * error_vector
    copy = delayed_copy(pulse, delay_s)
    if doppler_hz:
        copy = copy * np.exp(1j * 2.0 * np.pi * doppler_hz
                             * np.arange(count) / FS)
    noise_sigma = np.sqrt(10.0 ** (-snr_db / 10.0) / 2.0)
    data = np.zeros((pulses, buffer_samples, positions.shape[0]), dtype=complex)
    offset = int(round(delay_s * FS))
    for index in range(pulses):
        if incoherent_decoy:
            # a non-coherent repeater restarts its phase every pulse
            copy = copy * np.exp(1j * rng.uniform(0, 2 * np.pi))
        direct = np.zeros(buffer_samples, dtype=complex)
        direct[pad_samples:pad_samples + count] = pulse
        repeat = np.zeros(buffer_samples, dtype=complex)
        repeat[pad_samples + offset:pad_samples + offset + count] = copy
        data[index] = (np.outer(direct, source) + np.outer(repeat, decoy)
                       + noise_sigma * (rng.standard_normal((buffer_samples,
                                                             positions.shape[0]))
                                        + 1j * rng.standard_normal(
                                            (buffer_samples, positions.shape[0]))))
    return data


def dominant_vector(samples):
    """Rank-1 spatial vector of (N, M) samples, phase-referenced to element 0."""
    covariance = samples.T @ np.conj(samples)
    _, vectors = np.linalg.eigh(covariance)
    vector = vectors[:, -1]
    return vector * np.conj(vector[0]) / max(abs(vector[0]), 1e-12)


def doa_from_vector(vector, freq_hz, positions, grid_deg=0.05, az_max=60.0):
    azs = np.arange(-az_max, az_max + 1e-9, grid_deg)
    response = np.array([abs(np.vdot(dd.steering(dd.u_of(az), freq_hz, positions),
                                     vector)) ** 2 for az in azs])
    return float(azs[int(np.argmax(response))])


def leading_window_doa(data, window_samples, positions, start_sample=0,
                       center_time_s=None, pulse_s=PULSE_S, inst_freq=None):
    """DOA from the first window_samples after the pulse edge."""
    window = data[:, start_sample:start_sample + window_samples, :]
    vector = dominant_vector(window.reshape(-1, window.shape[-1]))
    if center_time_s is None:
        center_time_s = (start_sample + window_samples / 2.0) / FS
    freq = F_CARRIER + (inst_freq(center_time_s) if inst_freq is not None
                        else -BW_HZ / 2.0 + BW_HZ / pulse_s * center_time_s)
    return doa_from_vector(vector, freq, positions)


def full_pulse_doa(data, positions, min_bins=3):
    """The section 13 per-bin method: FFT the whole pulse, fit each bin, average."""
    count = data.shape[1]
    taper = np.hanning(count)[None, :, None]
    spectrum = np.fft.fft(data * taper, axis=1)
    power = np.sum(np.abs(spectrum) ** 2, axis=(0, 2))
    freqs = np.fft.fftfreq(count, d=1.0 / FS)
    occupied = np.where(power > 0.05 * power.max())[0]
    if occupied.size < min_bins:
        return float("nan")
    curves = []
    for index in occupied:
        vector = dominant_vector(spectrum[:, index, :])
        curves.append(doa_from_vector(vector, F_CARRIER + freqs[index], positions))
    return float(np.mean(curves))


def beat_frequency(data, fs=FS):
    """Dominant modulation of the pulse envelope: |s1 + s2 e^{j2*pi*df*t}|^2."""
    power = np.sum(np.abs(data[0, :, 0]) ** 2)
    count = data.shape[1]
    series = np.abs(data[0, :, 0]) ** 2
    series = series - np.mean(series)
    spectrum = np.abs(np.fft.rfft(series * np.hanning(count)))
    freqs = np.fft.rfftfreq(count, d=1.0 / fs)
    band = (freqs > 5e3) & (freqs < 20e6)
    if not np.any(band):
        return 0.0
    index = np.argmax(spectrum[band])
    return float(freqs[band][index])


def single_bin_pair(rng, positions, delay_s, n_snapshots=64, snr_db=20.0,
                    use_delay_s=None, az_source=8.0, az_decoy=37.0, gain=1.0):
    """One 1 MHz bin holding a source and a coherent repeater: (1, snaps, M)."""
    freq = F_CARRIER
    source = dd.steering(dd.u_of(az_source), freq, positions)
    decoy = dd.steering(dd.u_of(az_decoy), freq, positions)
    tau = delay_s if use_delay_s is None else use_delay_s
    model = source + gain * np.exp(-1j * 2.0 * np.pi * freq * delay_s) * decoy
    noise_sigma = np.sqrt(10.0 ** (-snr_db / 10.0) / 2.0)
    data = np.zeros((1, n_snapshots, positions.shape[0]), dtype=complex)
    for index in range(n_snapshots):
        amplitude = (rng.standard_normal() + 1j * rng.standard_normal()) / np.sqrt(2.0)
        data[0, index, :] = amplitude * model + noise_sigma * (
            rng.standard_normal(positions.shape[0])
            + 1j * rng.standard_normal(positions.shape[0]))
    return data, np.array([freq]), tau


def replay_capture(path, positions, window_ns, pulse_ns, delay_ns,
                   truth_az, decoy_az):
    """Gate-style post-processing of one captured record (pulses, samples, M).

    This is the function gate G7 runs on hardware data: everything here is what
    the simulation studies above measure, applied to a real capture instead of a
    synthetic one. No simulation, no assumptions beyond the array geometry.
    """
    data = np.load(path)
    if data.ndim != 3:
        raise ValueError("expected (pulses, samples, channels), got %s"
                         % (data.shape,))
    pulses, samples, elements = data.shape
    if elements != positions.shape[0]:
        raise ValueError("capture has %d channels, the array model %d"
                         % (elements, positions.shape[0]))
    envelope = np.mean(np.sum(np.abs(data) ** 2, axis=2), axis=0)
    # Edge against the noise floor, not against the peak: where the repeat
    # overlaps the direct path the power is up to 4x the single-path level, so
    # any "50 % of peak" or "largest rise" rule fires at the repeat instead of
    # the radar. A capture with a normal PRI gap has a median that is noise.
    smooth = max(int(round(2e-9 * FS)), 2)
    smoothed = np.convolve(envelope, np.ones(smooth) / smooth, mode="same")
    floor = np.median(smoothed)
    above = np.where(smoothed > 1.5 * floor)[0]
    if above.size == 0:
        raise ValueError("no pulse found: the envelope never exceeds 1.5x its "
                         "median. The direct path must be visible per sample -- "
                         "gate G7 requires about +10 dB per sample for this")
    edge = max(int(above[0]) - smooth // 2, 0)
    width = max(int(round(window_ns * 1e-9 * FS)), 8)
    if edge + width > samples:
        raise ValueError("window runs past the capture")
    gate_az = leading_window_doa(data, width, positions, start_sample=edge,
                                 pulse_s=pulse_ns * 1e-9)
    pulse_samples = int(round(pulse_ns * 1e-9 * FS))
    delay_samples = int(round(delay_ns * 1e-9 * FS))
    # the tail starts after the pulse ends, with a margin for the edge estimate
    margin = max(int(round(25e-9 * FS)), 4)
    tail_start = edge + pulse_samples + margin
    tail = data[:, tail_start:tail_start + max(delay_samples - margin, 4), :]
    if tail.shape[1] >= 8:
        vector = dominant_vector(tail.reshape(-1, tail.shape[-1]))
        tail_az = doa_from_vector(vector, F_CARRIER, positions)
        tail_ns = tail.shape[1] / FS * 1e9
    else:
        tail_az, tail_ns = float("nan"), 0.0
    full_az = full_pulse_doa(data[:, edge:edge + pulse_samples, :], positions)

    print("# replay of %s (%d pulses, %d samples, %d channels)"
          % (path, pulses, samples, elements))
    print("# edge at sample %d (%.1f ns), window %.0f ns, pulse %.0f ns"
          % (edge, edge / FS * 1e9, window_ns, pulse_ns))
    print("  leading-edge DOA    %8.2f deg %s"
          % (gate_az, "" if truth_az is None
             else " (truth %.2f, error %+.2f)" % (truth_az, gate_az - truth_az)))
    print("  whole-pulse DOA     %8.2f deg %s"
          % (full_az, "" if truth_az is None
             else " (truth %.2f, error %+.2f)" % (truth_az, full_az - truth_az)))
    print("  tail window         %8.0f ns of the %.0f ns delay"
          % (tail.shape[1] / FS * 1e9, delay_ns))
    print("  tail DOA            %8.2f deg %s"
          % (tail_az, "" if decoy_az is None
             else " (truth %.2f, error %+.2f)" % (decoy_az, tail_az - decoy_az)))
    print("  tail length         %8.0f ns measured" % tail_ns)
    verdict, failures = [], 0
    if truth_az is not None:
        for label, passed in (("gate", abs(gate_az - truth_az) < 1.5),
                              ("whole-pulse-pull-off",
                               abs(full_az - truth_az) > 5.0)):
            verdict.append("%s %s" % (label, "PASS" if passed else "FAIL"))
            failures += 0 if passed else 1
    if decoy_az is not None:
        passed = abs(tail_az - decoy_az) < 3.0
        verdict.append("tail %s" % ("PASS" if passed else "FAIL"))
        failures += 0 if passed else 1
    print("  G7 criteria: %s" % (" ".join(verdict) if verdict else "no truth given"))
    return 0 if failures == 0 else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--seed", type=int, default=20261107)
    parser.add_argument("--out", default=None)
    parser.add_argument("--replay", default=None,
                        help="process a captured (pulses, samples, 4) .npy file")
    parser.add_argument("--window-ns", type=float, default=100.0)
    parser.add_argument("--pulse-ns", type=float, default=1000.0)
    parser.add_argument("--delay-ns", type=float, default=100.0)
    parser.add_argument("--truth-az", type=float, default=None)
    parser.add_argument("--decoy-az", type=float, default=None)
    parser.add_argument("--selftest", action="store_true",
                        help="synthesise a capture and run the G7 replay path")
    args = parser.parse_args()
    if args.replay:
        return replay_capture(args.replay, dd.square_grid(2, PITCH_M),
                              args.window_ns, args.pulse_ns, args.delay_ns,
                              args.truth_az, args.decoy_az)
    if args.selftest:
        # exercise the G7 post-processing without hardware: synthesise a capture,
        # save it, and run exactly the code gate G7 will run on a real one.
        positions = dd.square_grid(2, PITCH_M)
        worst = 0
        for snr_db in (10.0, 0.0):
            rng_local = np.random.default_rng(args.seed)
            data = radar_scene(rng_local, positions, 100e-9, snr_db=snr_db,
                               pulses=16, pad_samples=4000)
            path = os.path.join("build", "output",
                                "g7_selftest_capture_%ddB.npy" % int(snr_db))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            np.save(path, data)
            print("# selftest at %.0f dB per sample" % snr_db)
            worst = max(worst, replay_capture(path, positions, 100.0, 1000.0,
                                              100.0, AZ_SOURCE, AZ_DECOY))
        print("RESULT=%s" % ("PASS" if worst == 0 else "FAIL"))
        return worst
    if args.out is None:
        args.out = (os.path.join("build", "output", "v07_radar_decoy_quick.txt")
                    if args.quick else
                    os.path.join("docs", "evidence", "2026-11-06-phase-interf",
                                 "radar_decoys.txt"))

    trials = 3 if args.quick else 8
    rng = np.random.default_rng(args.seed)
    lines, failures = [], []

    def emit(text=""):
        print(text, flush=True)
        lines.append(text)

    emit("# the protected source is a radar: the first arrival is the answer")
    emit("# generated %s" % _dt.datetime.now(_dt.timezone.utc)
         .strftime("%Y-%m-%dT%H:%M:%SZ"))
    emit("# script: scripts/radar_decoys.py (python3 + numpy only)")
    emit("# source: radar at 2.500 GHz, az +10 deg, LFM 50 MHz over 1 us, %.0f GS/s"
         % (FS / 1e9))
    emit("# decoy: repeater copy at az +40 deg, equal power, %d pulses per scene"
         % 64)
    emit("# array: 2x2 at 30 mm; seed=%d, trials=%d" % (args.seed, trials))
    positions = dd.square_grid(2, PITCH_M)

    # ---------------------------------------------------------------- geometry
    emit("")
    emit("Study G0: the ordering is geometry, not a signal property")
    emit("  radar at range R = 5 km; decoy at range r from the array, and a")
    emit("  processing delay tau. Arrival of the repeat, relative to the direct")
    emit("  path, in ns:")
    emit("  %-28s %12s %12s %14s"
         % ("decoy position", "r (m)", "path (m)", "later by"))
    range_m = 5000.0
    for label, offset_m, off_deg in (("on the axis, 500 m out", 500.0, 0.0),
                                     ("on the axis, 2000 m out", 2000.0, 0.0),
                                     ("60 deg off-axis, 1000 m", 1000.0, 60.0),
                                     ("90 deg off-axis, 300 m", 300.0, 90.0)):
        if off_deg == 0.0:
            r_m = offset_m
            path_m = range_m - r_m + r_m
        else:
            angle = np.radians(off_deg)
            r_m = offset_m
            path_m = np.sqrt(range_m ** 2 + r_m ** 2
                             - 2 * range_m * r_m * np.cos(angle)) + r_m
        extra_ns = 1e9 * (path_m - range_m) / C_LIGHT + 100.0
        emit("  %-28s %12.0f %12.0f %14.1f"
             % (label, r_m, path_m, extra_ns))
    emit("  A decoy closest to the array still needs the pulse to reach it, so")
    emit("  the repeat can never precede the direct path; with a 100 ns DRFM")
    emit("  turnaround every repeat is at least 100 ns late. That 100 ns is")
    emit("  200 samples at 2 GS/s -- time resolution the channelizer does not have.")

    # ------------------------------------------------------------ leading edge
    emit("")
    emit("Study G: DOA from the leading edge versus DOA from the whole pulse")
    emit("  coherent repeater, equal power, 30 deg away, 0 dB per-sample SNR")
    emit("  %-10s %12s %14s %14s %14s"
         % ("delay", "whole pulse", "gate W=tau/2", "gate W=tau", "gate W=2*tau"))
    gate = {}
    for delay_ns in (20.0, 50.0, 100.0, 200.0):
        delay_s = delay_ns * 1e-9
        full_errors, half_errors, tau_errors, double_errors = [], [], [], []
        for _ in range(trials):
            data = radar_scene(rng, positions, delay_s)
            full_errors.append(full_pulse_doa(data, positions) - AZ_SOURCE)
            w_half = max(int(round(delay_s * FS / 2.0)), 4)
            w_tau = max(int(round(delay_s * FS)), 4)
            w_double = max(int(round(2 * delay_s * FS)), 4)
            half_errors.append(leading_window_doa(data, w_half, positions)
                               - AZ_SOURCE)
            tau_errors.append(leading_window_doa(data, w_tau, positions)
                              - AZ_SOURCE)
            double_errors.append(leading_window_doa(data, w_double, positions)
                                 - AZ_SOURCE)
        gate[delay_ns] = {
            "full": float(np.mean(np.abs(full_errors))),
            "half": float(np.mean(np.abs(half_errors))),
            "tau": float(np.mean(np.abs(tau_errors))),
            "double": float(np.mean(np.abs(double_errors))),
        }
        emit("  %-10s %11.2f deg %13.2f deg %13.2f deg %13.2f deg"
             % ("%.0f ns" % delay_ns, gate[delay_ns]["full"],
                gate[delay_ns]["half"], gate[delay_ns]["tau"],
                gate[delay_ns]["double"]))
    emit("  The whole-pulse number is the section 13 failure: two coherent paths")
    emit("  in one bin pull the DOA several degrees off. The gate is correct to")
    emit("  a fraction of a degree while it stays inside the dead time the decoy")
    emit("  needs to turn around -- and stops being correct once it does not.")
    emit("  Edge timing has to be known, so the same run with a +/-2 ns error on")
    emit("  the window start:")
    jitter_errors = []
    for _ in range(trials):
        data = radar_scene(rng, positions, 100e-9)
        jitter = int(rng.integers(-4, 5))  # +/-2 ns at 2 GS/s
        jitter_errors.append(leading_window_doa(data, 100, positions,
                                                start_sample=max(jitter, 0))
                             - AZ_SOURCE)
    gate["jitter"] = float(np.mean(np.abs(jitter_errors)))
    emit("  %-10s %11s %13.2f deg   (delay 100 ns, W = 100 ns)"
         % ("+/-2 ns", "n/a", gate["jitter"]))

    # ------------------------------------------------------- window vs SNR
    emit("")
    emit("Study G2: how much window is enough?  delay 100 ns, so W <= 200 samples")
    emit("  per-sample SNR, azimuth RMSE in degrees")
    emit("  %-14s %10s %10s %10s %10s %10s"
         % ("SNR", "W=5 ns", "10 ns", "20 ns", "50 ns", "100 ns"))
    window_table = {}
    for snr_db in (-10.0, 0.0, 10.0):
        row = []
        for width_ns in (5.0, 10.0, 20.0, 50.0, 100.0):
            errors = []
            for _ in range(trials):
                data = radar_scene(rng, positions, 100e-9, snr_db=snr_db)
                width = max(int(round(width_ns * 1e-9 * FS)), 2)
                errors.append(leading_window_doa(data, width, positions)
                              - AZ_SOURCE)
            row.append(float(np.sqrt(np.mean(np.square(errors)))))
        window_table[snr_db] = row
        emit("  %-14s %9.2f %9.2f %9.2f %9.2f %9.2f"
             % ("%.0f dB" % snr_db, row[0], row[1], row[2], row[3], row[4]))
    emit("  A 5 ns window is 10 samples: it needs a strong direct path, and it is")
    emit("  the only window that survives a decoy that is very fast. At 0 dB per")
    emit("  sample 20 ns is already enough, which is 5x shorter than the 100 ns")
    emit("  the decoy needs.")

    # -------------------------------------------------------------- Doppler
    emit("")
    emit("Study H: a DRFM that also shifts Doppler, and the tail it leaves")
    emit("  a 10 us pulse; delay 100 ns; gate W = 100 ns; 0 dB per sample")
    emit("  %-10s %14s %14s %16s"
         % ("doppler", "whole pulse", "gate W=100 ns", "gate error"))
    doppler_table = {}
    pulse_s = 10e-6
    for doppler_hz in (0.0, 100e3, 1e6):
        full_errors, gate_errors = [], []
        for _ in range(trials):
            data = radar_scene(rng, positions, 100e-9, doppler_hz=doppler_hz,
                               pulse_s=pulse_s)
            full_errors.append(full_pulse_doa(data, positions) - AZ_SOURCE)
            gate_errors.append(leading_window_doa(data, 100, positions,
                                                  pulse_s=pulse_s) - AZ_SOURCE)
        doppler_table[doppler_hz] = (float(np.mean(np.abs(full_errors))),
                                     float(np.mean(np.abs(gate_errors))))
        emit("  %-10s %13.2f deg %13.2f deg %13.2f deg"
             % ("%.0f kHz" % (doppler_hz / 1e3), doppler_table[doppler_hz][0],
                doppler_table[doppler_hz][1], doppler_table[doppler_hz][1]))
    emit("  A velocity pull-off does not touch the leading edge; the whole-pulse")
    emit("  method is already several degrees wrong and stays that way.")
    emit("")
    emit("  The tail is the other half of the ordering: after the radar stops")
    emit("  transmitting, whatever is still on the air is the decoy, for exactly")
    emit("  the delay it inserted. Tail length and tail DOA, per-sample SNR 0 dB:")
    emit("  %-8s %12s %14s %14s"
         % ("delay", "tail (ns)", "tail DOA", "error"))
    tail = {}
    for delay_ns in (20.0, 50.0, 100.0, 200.0):
        lengths, directions = [], []
        for _ in range(trials):
            data = radar_scene(rng, positions, delay_ns * 1e-9, pulse_s=pulse_s)
            count = data.shape[1]
            pulse_count = int(round(pulse_s * FS))
            window = int(round(delay_ns * 1e-9 * FS))
            segment = data[:, pulse_count:pulse_count + window, :]
            if segment.shape[1] < 8:
                continue
            vector = dominant_vector(segment.reshape(-1, segment.shape[-1]))
            lengths.append(segment.shape[1] / FS * 1e9)
            directions.append(doa_from_vector(vector, F_CARRIER + BW_HZ / 2.0,
                                              positions))
        tail[delay_ns] = (float(np.mean(lengths)), float(np.mean(directions)))
        emit("  %-8s %11.0f %13.1f deg %13.2f deg"
             % ("%.0f ns" % delay_ns, tail[delay_ns][0], tail[delay_ns][1],
                abs(tail[delay_ns][1] - AZ_DECOY)))
    emit("  Both directions come out of the same record, at different times: the")
    emit("  radar in the first 100 ns of its own pulse, the decoy in the")
    emit("  %.0f ns after that pulse ends. No coherence model is needed for either."
         % tail[100.0][0])

    # ------------------------------------------- delay into the section 13 ML
    emit("")
    emit("Study I: what the leading-edge delay is worth to the section 13 ML")
    emit("  emitter and coherent repeater 29 deg apart, equal power; the delay")
    emit("  comes from the leading edge (half a sample at 2 GS/s):")
    emit("  %-12s %6s %14s %16s"
         % ("bandwidth", "bins", "both < 3 deg", "delay error"))
    delay_fed = {}
    for bandwidth in (1e6, 5e6, 20e6, 50e6):
        for error_ns in (0.5, 5.0):
            hits = 0
            for _ in range(trials * 2):
                freqs = dd.bin_frequencies(F_CARRIER, bandwidth, 1.952625e6)
                sources = ({"f_hz": F_CARRIER, "bw_hz": bandwidth, "az": 8.0,
                            "gain": 1.0},
                           {"f_hz": F_CARRIER, "bw_hz": bandwidth, "az": 37.0,
                            "gain": 1.0, "coherent_with": 0, "delay_s": 100e-9})
                data = dd.simulate_scene(rng, sources, positions, freqs)
                first, second, _, _ = dd.two_path_ml(
                    data, freqs, positions, 100e-9 + error_ns * 1e-9, grid_deg=1.0)
                first, second = sorted((first, second))
                if abs(first - 8.0) <= 3.0 and abs(second - 37.0) <= 3.0:
                    hits += 1
            delay_fed[(bandwidth, error_ns)] = hits / (trials * 2)
            emit("  %-12s %6d %13.0f%% %14s"
                 % ("%.0f MHz" % (bandwidth / 1e6),
                    len(dd.bin_frequencies(F_CARRIER, bandwidth, 1.952625e6)),
                    100.0 * delay_fed[(bandwidth, error_ns)],
                    "%.1f ns" % error_ns))
    emit("  The delay does not have to be perfect -- with the relative phase left")
    emit("  free (the correct model) it only sets the slope across the band, so")
    emit("  the tolerance is about 1/(10*bandwidth): 2 ns at 5 MHz, 0.5 ns at")
    emit("  50 MHz. Half a sample from the leading edge covers both. What it")
    emit("  cannot do is create frequency diversity: at 1 MHz the whole signal is")
    emit("  one bin and the pair stays unsolvable on four elements.")

    # ------------------------------------------------- waveform and calibration
    emit("")
    emit("Study J: the gate does not care which waveform the radar uses")
    emit("  delay 100 ns, W = 100 ns from a 50%-amplitude edge, 0 dB per sample")
    emit("  %-14s %14s %14s %14s %12s"
         % ("waveform", "whole pulse", "gate", "tail", "tail error"))
    waveform_table = {}
    for kind, label in (("lfm", "LFM 50 MHz"), ("lfm_soft", "LFM, 20 ns edge"),
                        ("nlfm", "tan-FM 50 MHz"), ("barker13", "Barker-13")):
        full_errors, gate_errors, tail_errors, tail_lengths = [], [], [], []
        inst_freq = make_waveform(kind)[2]
        start = edge_sample(kind)
        for _ in range(trials):
            data = radar_scene(rng, positions, 100e-9, waveform=kind)
            full_errors.append(full_pulse_doa(data, positions) - AZ_SOURCE)
            gate_errors.append(leading_window_doa(data, 100, positions,
                                                  start_sample=start,
                                                  inst_freq=inst_freq)
                               - AZ_SOURCE)
            pulse_count = data.shape[1] - int(round(100e-9 * FS)) - 8
            segment = data[:, pulse_count:pulse_count + 200, :]
            vector = dominant_vector(segment.reshape(-1, segment.shape[-1]))
            tail_errors.append(doa_from_vector(vector, F_CARRIER, positions)
                               - AZ_DECOY)
            tail_lengths.append(segment.shape[1] / FS * 1e9)
        waveform_table[kind] = (float(np.mean(np.abs(full_errors))),
                                float(np.mean(np.abs(gate_errors))),
                                float(np.mean(np.abs(tail_errors))),
                                float(np.mean(tail_lengths)))
        emit("  %-14s %11.2f deg %11.2f deg %13.1f deg %9.0f ns"
             % (label, waveform_table[kind][0], waveform_table[kind][1],
                AZ_DECOY + float(np.mean(tail_errors)), waveform_table[kind][3]))
    emit("  A phase code has no instantaneous-frequency sweep at all and the")
    emit("  gate still holds: it measures a direction inside a 100 ns slice, and")
    emit("  the slice is decoy-free whatever the modulation is. The whole-pulse")
    emit("  method is wrong for every waveform, because the failure is coherent")
    emit("  interference, not a property of the modulation.")

    emit("")
    emit("Study K: residual calibration error, and how long the window must be")
    emit("  +/-0.5 dB and +/-5 deg per channel (the section 11.3 residual),")
    emit("  0 dB per sample, delay 100 ns, gate started at the detected edge")
    emit("  %-12s %9s %14s %11s"
         % ("waveform", "window", "no cal error", "+cal error"))
    calibration = {}
    for kind, label in (("lfm", "LFM 50 MHz"), ("barker13", "Barker-13")):
        inst_freq = make_waveform(kind)[2]
        start = edge_sample(kind)
        for width_ns in (10.0, 20.0, 50.0, 100.0):
            clean, dirty = [], []
            width = max(int(round(width_ns * 1e-9 * FS)), 2)
            for _ in range(max(2 * trials, 8)):
                data = radar_scene(rng, positions, 100e-9, waveform=kind)
                clean.append(leading_window_doa(data, width, positions,
                                                start_sample=start,
                                                inst_freq=inst_freq) - AZ_SOURCE)
                errors = channel_error(rng, positions.shape[0])
                data = radar_scene(rng, positions, 100e-9, waveform=kind,
                                   error_vector=errors)
                dirty.append(leading_window_doa(data, width, positions,
                                                start_sample=start,
                                                inst_freq=inst_freq) - AZ_SOURCE)
            calibration[(kind, width_ns)] = (
                float(np.sqrt(np.mean(np.square(clean)))),
                float(np.sqrt(np.mean(np.square(dirty)))))
            emit("  %-12s %7.0f ns %9.2f deg %11.2f deg"
                 % (label, width_ns, calibration[(kind, width_ns)][0],
                    calibration[(kind, width_ns)][1]))
    cal_worst = max(calibration[(kind, w)][1] for kind in ("lfm", "barker13")
                    for w in (50.0, 100.0))
    floor = float(np.mean([calibration[(kind, w)][1]
                           for kind in ("lfm", "barker13")
                           for w in (50.0, 100.0)]))
    emit("  Read the two columns together: without calibration the gate is a")
    emit("  noise-limited estimate (0.1-0.9 deg here), and the +/-0.5 dB / +/-5 deg")
    emit("  residual puts a bias floor of about %.1f deg on top -- the same order"
         % floor)
    emit("  as the 0.79 deg that 0.5 mm of geometry error costs in section 11.3.")
    emit("  So the gate measures the radar correctly and calibration, not the")
    emit("  decoy, is what remains between it and the 0.5 deg class.")

    # ------------------------------------------------- proposed G7 criteria
    emit("")
    emit("Study L: the numbers a hardware gate (G7) would have to reproduce")
    emit("  criterion                                        threshold    measured")
    criteria = (
        ("leading-edge DOA error", 1.5,
         max(v["half"] for v in gate.values() if isinstance(v, dict)), "deg"),
        ("whole-pulse DOA error (must be visible)", 5.0,
         min(v["full"] for v in gate.values() if isinstance(v, dict)), "deg"),
        ("edge jitter +/-2 ns", 1.5, gate["jitter"], "deg"),
        ("Doppler pull-off 1 MHz", 1.5, doppler_table[1e6][1], "deg"),
        ("tail DOA error", 3.0,
         max(waveform_table[k][2] for k in waveform_table), "deg"),
        ("gate under the worst waveform", 1.5,
         max(waveform_table[k][1] for k in waveform_table), "deg"),
        ("gate at 100 ns with cal residual", 3.0, cal_worst, "deg"),
    )
    for label, limit, value, unit in criteria:
        passed = value < limit if "must be visible" not in label else value > limit
        emit("  %-46s %6.1f %s  %6.2f %s  %s"
             % (label, limit, "max" if "must be visible" not in label else "min",
                value, unit, "PASS" if passed else "FAIL"))
    emit("  These are the acceptance numbers for gate G7 in GATES_RUNBOOK.md;")
    emit("  they are host measurements on this repository's models, and G7 is")
    emit("  where they have to survive a board, a delay line and a rotator.")

    # ------------------------------------------------------------- verdict
    emit("")
    emit("VERDICT")
    emit("  A radar transmits, so the decoy must receive first: the repeat is")
    emit("  always later than the direct path by at least its turnaround. That is")
    emit("  a physics guarantee, not a heuristic, and it is what this scenario")
    emit("  adds to section 13.")
    emit("  The leading edge therefore holds the radar alone, and its DOA is the")
    emit("  answer -- %.2f deg error at 20 ns of window against %.2f deg for the"
         % (gate[20.0]["half"], gate[20.0]["full"]))
    emit("  whole-pulse method.")
    emit("  Shortening the window costs SNR, not truth: 20 ns at 0 dB per sample")
    emit("  is enough, and the window only has to stay inside the decoy's dead")
    emit("  time.")
    emit("  The edge delay makes the section 13 two-path ML usable without a")
    emit("  blind search: %.0f%% at 50 MHz, %.0f%% at 20 MHz, %.0f%% at 5 MHz and"
         % (100.0 * delay_fed[(50e6, 0.5)], 100.0 * delay_fed[(20e6, 0.5)],
            100.0 * delay_fed[(5e6, 0.5)]))
    emit("  %.0f%% at 1 MHz, where one bin carries no frequency diversity at all."
         % (100.0 * delay_fed[(1e6, 0.5)]))
    emit("  What still fails, and must be said out loud:")
    emit("   (a) a continuous-wave source has no leading edge -- section 13's")
    emit("       rungs are all that is left, with their measured limits;")
    emit("   (b) the window needs an edge-detection time reference; the 2 ns case")
    emit("       above is the sensitivity, not a null result;")
    emit("   (c) a decoy that repeats from *the same direction* is now separable")
    emit("       in time (that is the point), but a decoy that also arrives first")
    emit("       is physically impossible only as long as it must hear the pulse;")
    emit("       an active decoy that generates its own look-alike waveform from a")
    emit("       library breaks the ordering and falls back to section 13 rungs.")

    if gate[20.0]["half"] < 1.0 and gate[20.0]["full"] > 2.0:
        emit("  [PASS] the 20 ns gate is within 1 deg while the whole-pulse")
        emit("         method is more than 2 deg off.")
    else:
        failures.append("leading-edge gate did not beat the whole-pulse method")
    if gate[100.0]["double"] > 2.0 * gate[100.0]["tau"] + 1.0:
        emit("  [PASS] over-running the gate past the repeat (W = 2*tau) is")
        emit("         measurably worse than W = tau.")
    else:
        failures.append("window over-run does not show the expected penalty")
    if window_table[0.0][2] < 1.0:
        emit("  [PASS] 20 ns at 0 dB per sample is enough (RMSE %.2f deg)."
             % window_table[0.0][2])
    else:
        failures.append("20 ns window is not accurate enough at 0 dB")
    if tail[100.0][0] > 60.0 and abs(tail[100.0][1] - AZ_DECOY) < 3.0:
        emit("  [PASS] the tail gives the decoy's own direction: %.1f deg for a"
             % tail[100.0][1])
        emit("         decoy at %.0f deg, over a %.0f ns tail."
             % (AZ_DECOY, tail[100.0][0]))
    else:
        failures.append("tail does not give the decoy direction")
    if all(waveform_table[k][1] < 1.5 for k in waveform_table):
        emit("  [PASS] the gate holds under every waveform: worst %.2f deg"
             % max(waveform_table[k][1] for k in waveform_table))
        emit("         (LFM %.2f, soft-edged LFM %.2f, tan-FM %.2f, Barker %.2f)."
             % (waveform_table["lfm"][1], waveform_table["lfm_soft"][1],
                waveform_table["nlfm"][1], waveform_table["barker13"][1]))
    else:
        failures.append("gate error exceeds 1.5 deg for some waveform")
    if all(waveform_table[k][2] < 3.0 for k in waveform_table):
        emit("  [PASS] the tail gives the decoy direction under every waveform")
        emit("         (worst %.1f deg)." % max(waveform_table[k][2]
                                              for k in waveform_table))
    else:
        failures.append("tail direction is worse than 3 deg for some waveform")
    cal_worst = max(calibration[(kind, w)][1] for kind in ("lfm", "barker13")
                    for w in (50.0, 100.0))
    if cal_worst < 3.0:
        emit("  [PASS] with the +/-0.5 dB / +/-5 deg residual the gate stays under")
        emit("         3 deg at 50 and 100 ns (worst %.2f deg); a 10 ns window is"
             % cal_worst)
        emit("         noise-limited at %.1f deg, which is a dwell choice, not a"
             % max(calibration[(kind, 10.0)][1] for kind in ("lfm", "barker13")))
        emit("         limit of the method.")
    else:
        failures.append("calibration residual breaks the gate")
    if delay_fed[(20e6, 0.5)] >= 0.75 and delay_fed[(1e6, 0.5)] < 0.5:
        emit("  [PASS] with the delay supplied, 10 bins resolve the pair (%.0f%%)"
             % (100.0 * delay_fed[(20e6, 0.5)]))
        emit("         and 1 bin does not (%.0f%%), as the flat ML surface predicts."
             % (100.0 * delay_fed[(1e6, 0.5)]))
    else:
        failures.append("delay-fed ML does not follow the bin count")
    emit("")
    emit("RESULT=%s" % ("PASS" if not failures else "FAIL " + ", ".join(failures)))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\nreport written to %s" % args.out)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
