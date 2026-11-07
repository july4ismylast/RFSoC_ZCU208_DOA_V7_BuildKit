"""The capture record: what the PL writes and the PS reads, and the three
things that happen between the antenna and that record.

Nothing here needs a board.  It is the *format contract* of step1 and the
simulation of the three error sources that live in this step:

  1. quantisation to 12 bits                (the RF-ADC)
  2. per-channel time skew                   (the MTS clock, G5)
  3. the DAC->ADC loopback delay             (G5)

Record layout (little endian, 32-byte header, then the payload)
--------------------------------------------------------------
   0   char[8]   "ZC208C01"
   8   uint32    fs_hz
  12   uint32    fc_hz
  16   uint16    channels
  18   uint16    bits
  20   uint32    samples
  24   float32   scale        LSB = 1/scale, so x = raw/scale
  28   uint32    flags
  32   int16[...] payload, sample-major then channel then I/Q:
                  index = ((n * channels) + ch) * 2 + (0 for I, 1 for Q)

  4096 samples x 4 channels x 2 x 2 bytes = 64 kB per burst (V04 section 7).

Run:  python3 step1_rfadc_mts/py/capture_format.py
"""

from __future__ import annotations

import math
import pathlib
import struct

import numpy as np

MAGIC = b"ZC208C01"
HEADER = struct.Struct("<8sIIHHIfI")
HEADER_BYTES = 32
FLAG_SIGNED_Q15 = 0x1
FLAG_MTS_SKEW_COMPENSATED = 0x2


def header_dict(fs_hz: float, fc_hz: float, channels: int, samples: int,
                bits: int = 12, scale: float | None = None, flags: int = 0) -> dict:
    """The 32 header bytes, as a dictionary a reader can print."""
    if scale is None:
        scale = float(2 ** (bits - 1))
    return {"magic": MAGIC, "fs_hz": int(round(fs_hz)), "fc_hz": int(round(fc_hz)),
            "channels": int(channels), "bits": int(bits), "samples": int(samples),
            "scale": float(scale), "flags": int(flags)}


def pack_header(header: dict) -> bytes:
    """Header dictionary -> the 32 bytes on the wire."""
    return HEADER.pack(header["magic"], header["fs_hz"], header["fc_hz"],
                       header["channels"], header["bits"], header["samples"],
                       header["scale"], header["flags"])


def unpack_header(blob: bytes) -> dict:
    """The 32 bytes on the wire -> header dictionary (raises on a bad magic)."""
    fields = HEADER.unpack(blob[:HEADER_BYTES])
    header = {"magic": fields[0], "fs_hz": fields[1], "fc_hz": fields[2],
              "channels": fields[3], "bits": fields[4], "samples": fields[5],
              "scale": fields[6], "flags": fields[7]}
    if header["magic"] != MAGIC:
        raise ValueError("not a ZC208C01 capture: magic %r" % (header["magic"],))
    return header


def quantise(x: np.ndarray, bits: int, headroom_db: float = 0.0) -> tuple[np.ndarray, np.ndarray, float]:
    """Complex samples -> the integer records, plus the clipped fraction.

    The scale is chosen so full scale is `2**(bits-1)-1` on the larger of I/Q,
    with `headroom_db` of back-off.  Returns (raw int16 array shaped like x,
    the clipped mask, the scale actually used).
    """
    peak = float(np.max(np.abs(np.concatenate([x.real.ravel(), x.imag.ravel()]))))
    if peak <= 0.0:
        return np.zeros(x.shape, dtype=np.int16), np.zeros(x.shape, dtype=bool), 1.0
    full_scale = (2 ** (bits - 1) - 1) * (10.0 ** (-headroom_db / 20.0))
    scale = full_scale / peak
    real = np.round(x.real * scale)
    imaginary = np.round(x.imag * scale)
    limit = float(2 ** (bits - 1) - 1)
    clipped = (np.abs(real) > limit) | (np.abs(imaginary) > limit)
    raw = np.empty(x.shape + (2,), dtype=np.int16)
    raw[..., 0] = np.clip(real, -limit - 1, limit).astype(np.int16)
    raw[..., 1] = np.clip(imaginary, -limit - 1, limit).astype(np.int16)
    return raw, clipped, scale


def write_capture(path, x: np.ndarray, fs_hz: float, fc_hz: float, bits: int = 12,
                  headroom_db: float = 0.0, flags: int = 0) -> dict:
    """Quantise and write one burst; returns the header plus the clipped fraction."""
    channels, samples = x.shape
    raw, clipped, scale = quantise(x, bits, headroom_db)
    header = header_dict(fs_hz, fc_hz, channels, samples, bits, scale, flags)
    payload = np.ascontiguousarray(np.transpose(raw, (1, 0, 2))).tobytes()
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(pack_header(header) + payload)
    header["clipped_fraction"] = float(np.mean(clipped))
    header["bytes"] = target.stat().st_size
    return header


def read_capture(path) -> tuple[np.ndarray, dict]:
    """Read one burst back as complex64 (channels x samples) and its header."""
    blob = pathlib.Path(path).read_bytes()
    header = unpack_header(blob[:HEADER_BYTES])
    body = np.frombuffer(blob[HEADER_BYTES:], dtype="<i2")
    expected = header["samples"] * header["channels"] * 2
    if body.size != expected:
        raise ValueError("payload is %d int16, header says %d" % (body.size, expected))
    pairs = body.reshape(header["samples"], header["channels"], 2).astype(np.float64)
    complex_samples = (pairs[..., 0] + 1j * pairs[..., 1]) / header["scale"]
    return np.ascontiguousarray(complex_samples.T), header


# --------------------------------------------------------------------------
# the three error sources of this step
# --------------------------------------------------------------------------
def quantisation_report(x: np.ndarray, bits: int = 12, headroom_db: float = 0.0) -> dict:
    """Measured SQNR, and the textbook value corrected for the peak-to-RMS ratio.

    6.02*b + 1.76 dB is the value for a signal that touches full scale (a
    sinusoid, crest factor 1.41 for uniform rounding to a sine).  The scenes of
    step0 are Gaussian, whose crest factor is ~2.5 in amplitude, so the honest
    expectation is

        SQNR = 6.02*b + 1.76 - 20*log10(peak/rms)

    and that is what the test bench compares against.
    """
    raw, clipped, scale = quantise(x, bits, headroom_db)
    reconstructed = (raw[..., 0] + 1j * raw[..., 1]) / scale
    error = reconstructed - x
    rms = float(np.sqrt(np.mean(np.abs(x) ** 2)))
    peak = float(np.max(np.abs(np.concatenate([x.real.ravel(), x.imag.ravel()]))))
    crest_db = 20.0 * math.log10(max(peak, 1e-30) / max(rms, 1e-30))
    signal = rms ** 2
    noise = float(np.mean(np.abs(error) ** 2))
    return {"sqnr_db": 10.0 * math.log10(signal / max(noise, 1e-30)),
            "ideal_db": 6.02 * bits + 1.76 - headroom_db - crest_db,
            "textbook_db": 6.02 * bits + 1.76 - headroom_db,
            "crest_db": crest_db,
            "clipped_fraction": float(np.mean(clipped)),
            "scale": scale}


def apply_skew(x: np.ndarray, skew_s, fs_hz: float, fc_hz: float = 4.0e9) -> np.ndarray:
    """Delay channel n by skew_s[n] seconds -- the MTS imperfection of G5.

    Two parts, and the first one is why anybody cares:

      carrier   exp(-j*2*pi*fc*dt)       <- at 4 GHz, 1 ps is 0.0251 rad = 0.687 deg
      baseband  exp(-j*2*pi*f_bb*dt)     <- at 200 MHz of bandwidth, 1.3e-3 rad

    A skew that is common to all channels cancels in the angle: only the
    channel-to-channel *difference* matters, which is what the test bench
    injects on CH2 and CH4.
    """
    channels, samples = x.shape
    skew = np.atleast_1d(np.asarray(skew_s, dtype=float))
    if skew.size != channels:
        raise ValueError("need one skew per channel")
    freqs = np.fft.fftfreq(samples, 1.0 / fs_hz)
    spectra = np.fft.fft(x, axis=1)
    carrier = np.exp(-1j * 2.0 * np.pi * fc_hz * skew)
    baseband = np.exp(-1j * 2.0 * np.pi * skew[:, None] * freqs[None, :])
    return np.fft.ifft(spectra * carrier[:, None] * baseband, axis=1)


def skew_angle_error_deg(skew_s: float, freq_hz: float = 4.0e9,
                         baseline_m: float = 0.025) -> float:
    """The physical size of one skew: dtheta = 2*pi*f*dt * lambda/(2*pi*d)."""
    wavelength = 299792458.0 / freq_hz
    return math.degrees(2.0 * math.pi * freq_hz * skew_s * wavelength
                        / (2.0 * math.pi * baseline_m))


def skew_budget_s(budget_deg: float = 0.5, freq_hz: float = 4.0e9,
                  baseline_m: float = 0.025) -> float:
    """The largest per-channel skew that still fits an angle budget."""
    wavelength = 299792458.0 / freq_hz
    phase = math.radians(budget_deg) * 2.0 * math.pi * baseline_m / wavelength
    return phase / (2.0 * math.pi * freq_hz)


def loopback_delay(x: np.ndarray, fs_hz: float, reference: int = 0) -> dict:
    """G5 in simulation: the bulk delay between two channels of one capture."""
    correlation = np.fft.ifft(np.fft.fft(x[reference])
                              * np.conj(np.fft.fft(x[(reference + 1) % len(x)])))
    lag = int(np.argmax(np.abs(correlation)))
    samples = x.shape[1]
    if lag > samples // 2:
        lag -= samples
    return {"lag_samples": lag, "delay_s": lag / fs_hz,
            "delay_ns": lag / fs_hz * 1e9,
            "resolution_ns": 1e9 / fs_hz,
            "resolution_cm": 299792458.0 / fs_hz * 100.0}


def main() -> int:
    rng = np.random.default_rng(1)
    samples, fs = 4096, 2.0e9
    probe = ((rng.standard_normal((4, samples))
              + 1j * rng.standard_normal((4, samples))) / math.sqrt(2.0))
    print("capture record: %d header bytes + %d payload bytes for 4 x %d"
          % (HEADER_BYTES, samples * 4 * 4, samples))
    report = quantisation_report(probe, 12)
    print("  12-bit SQNR %.2f dB (ideal %.2f dB), clipped %.3f %%"
          % (report["sqnr_db"], report["ideal_db"], 100.0 * report["clipped_fraction"]))
    print("  MTS skew: 1.00 ps -> %.3f deg of angle error at 4 GHz (25 mm)"
          % skew_angle_error_deg(1e-12))
    print("  MTS skew budget for 0.5 deg: %.3f ps" % (skew_budget_s() * 1e12))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
