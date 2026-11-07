"""Write the scenes that every later step is tested on.

This is the "feed the project as input" file.  No board, no MATLAB: it produces
four files in step0_antenna/data/ and each later step's testbench reads them.

    scene_single.npz    one QPSK emitter, 20 dB,   az +12.50  el -7.25
    scene_two.npz       two emitters 8 deg apart in azimuth, one QPSK one 16QAM
    scene_decoy.npz     one emitter and its delayed copy (40 ns), i.e. a repeater
    series_mover.npz    eight frames of a mover, 1.0 deg/frame in azimuth

Each .npz holds `x` (4 channels x 4096 samples, complex, fs = 2 GS/s, fc = 4 GHz)
and a sibling .json with the truth in degrees, Hz and dB.

Run:  python3 step0_antenna/py/make_scenes.py [--out DIR]
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import array_model as model  # noqa: E402


FRAMES = 8
MOVER_RATE_DEG = 1.0


def build_single(rng) -> dict:
    return model.scene(rng, [model.emitter(az=12.5, el=-7.25, snr_db=20.0,
                                           bandwidth_hz=100e6, modulation="QPSK")])


def build_two(rng) -> dict:
    return model.scene(rng, [
        model.emitter(az=6.0, el=-4.0, snr_db=20.0, bandwidth_hz=100e6,
                      modulation="QPSK"),
        model.emitter(az=14.0, el=-4.0, snr_db=20.0, bandwidth_hz=100e6,
                      modulation="16QAM", offset_hz=200e6),
    ])


def build_decoy(rng) -> dict:
    """One waveform arriving twice, 40 ns apart -- a repeater, not two emitters.

    A second call to model.scene() would draw a *different* payload, and two
    independent waveforms do not interfere: there would be no ripple and the
    cepstral check of step5 would have nothing to find.  So the copy is built
    from the first burst with a phase ramp, which is what a repeater does.
    """
    direct = model.emitter(az=10.0, el=0.0, snr_db=20.0, bandwidth_hz=100e6,
                           modulation="QPSK")
    base = model.scene(rng, [direct])
    delay_s = 40e-9
    bins = np.fft.fftfreq(base["x"].shape[1], 1.0 / model.FS_HZ)
    ramp = np.exp(-1j * 2.0 * np.pi * bins * delay_s) * 10.0 ** (-6.0 / 20.0)
    # the echo is the SAME waveform, delayed: that is what makes the ripple
    echo = np.fft.ifft(np.fft.fft(base["x"], axis=1) * ramp, axis=1)
    truth = {"emitters": [direct,
                          model.emitter(az=10.0, el=0.0, snr_db=14.0,
                                        bandwidth_hz=100e6, modulation="QPSK",
                                        delay_ns=delay_s * 1e9)],
             "fs_hz": model.FS_HZ, "fc_hz": model.FC_HZ,
             "samples": model.SAMPLES,
             "note": "the second entry is a delayed copy of the first, not an independent emitter"}
    return {"x": base["x"] + echo, "truth": truth}


def build_series(rng) -> dict:
    frames = []
    truth = []
    for index in range(FRAMES):
        azimuth = -4.0 + MOVER_RATE_DEG * index
        item = model.emitter(az=azimuth, el=2.0, snr_db=18.0, bandwidth_hz=100e6)
        item["frame"] = index
        frames.append(model.scene(rng, [item])["x"])
        truth.append(item)
    return {"x": np.stack(frames), "truth": {"emitters": truth, "fs_hz": model.FS_HZ,
                                             "fc_hz": model.FC_HZ,
                                             "samples": model.SAMPLES,
                                             "frames": FRAMES}}


def ensure(out: pathlib.Path, quiet: bool = False) -> dict:
    """Write every scene if it is missing; return the paths.  Idempotent."""
    out.mkdir(parents=True, exist_ok=True)
    result = {}
    builders = {"scene_single": (build_single, 1),
                "scene_two": (build_two, 2),
                "scene_decoy": (build_decoy, 3),
                "series_mover": (build_series, 4)}
    for name, (builder, seed) in builders.items():
        target = out / (name + ".npz")
        result[name] = target
        if target.exists():
            continue
        if not quiet:
            print("  writing %s" % target)
        model.save(target, builder(np.random.default_rng(seed)))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parent.parent
                                             / "data"))
    arguments = parser.parse_args()
    paths = ensure(pathlib.Path(arguments.out))
    for name, path in paths.items():
        size = path.stat().st_size / 1024.0
        print("  %-14s %7.1f kB  %s" % (name, size, path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
