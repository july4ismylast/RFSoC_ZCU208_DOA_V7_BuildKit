#!/usr/bin/env python3
"""Draw the whole system -- every block, every gate -- as one figure.

The raster/vector pair it writes is the diagram of record:
    docs/diagrams/system_block.png   (for reading and for slide decks)
    docs/diagrams/system_block.svg   (for editing and for the repository view)

Every box is a block that exists in this repository (an IP directory, a
software module, or a MATLAB reference) or a gate. Nothing is decorative: if a
name is on this figure, there is a file with that name and a Makefile target or
a gate that exercises it.

Run:  python3 scripts/draw_system.py [--out DIR]
"""

from __future__ import annotations

import argparse
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as patches  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "docs", "diagrams")

W, H = 100.0, 166.0

ZONES = {
    "rf": (1.0, 138.0, 98.0, 18.0, "1  RF FRONT END  (board)   —   step0_antenna · step1_rfadc_mts",
           "#fff4e6", "#e8a33d"),
    "pl": (1.0, 100.0, 98.0, 35.0, "2  PROGRAMMABLE LOGIC  (XCZU48DR, 4.0 ns clock)   —   step2_pl_ip",
           "#eaf2fb", "#3d7ec0"),
    "r5": (1.0, 51.0, 98.0, 46.0, "3  PS / RPU  Cortex-R5F, bare metal   —   step3_r5_doa · step4_r5_amc · step5_r5_tracking",
           "#eaf7ee", "#3f9a5b"),
    "a53": (1.0, 24.0, 98.0, 24.0, "4  PS / APU  Cortex-A53, Linux   —   step6_ps_linux",
            "#f3edfa", "#7c5cb0"),
    "host": (1.0, 4.0, 98.0, 16.0, "5  HOST  (no licence)   —   every green result in this repository   ·   step7_board_bringup = the open gates",
             "#f2f2f2", "#666666"),
}

GREEN = "#2e7d32"
AMBER = "#b26a00"
GREY = "#7a7a7a"


def zone(ax, key):
    x, y, w, h, label, face, edge = ZONES[key]
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.3,rounding_size=1.2",
        linewidth=1.2, edgecolor=edge, facecolor=face, zorder=1))
    ax.text(x + 0.7, y + h - 1.0, label, fontsize=8.6, fontweight="bold",
            color=edge, ha="left", va="center", zorder=5)


def box(ax, x, y, w, h, title, sub="", face="#ffffff", edge="#333333",
        title_size=7.4, sub_size=6.2, dashed=False, weight="bold"):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.18,rounding_size=0.7",
        linewidth=1.0, edgecolor=edge, facecolor=face, zorder=3,
        linestyle=(0, (3, 2)) if dashed else "solid"))
    if sub:
        ax.text(x + w / 2, y + h * 0.62, title, fontsize=title_size,
                fontweight=weight, ha="center", va="center", zorder=4)
        ax.text(x + w / 2, y + h * 0.3, sub, fontsize=sub_size, color="#333333",
                ha="center", va="center", zorder=4, linespacing=1.15)
    else:
        ax.text(x + w / 2, y + h / 2, title, fontsize=title_size,
                fontweight=weight, ha="center", va="center", zorder=4)


def gate(ax, x, y, name, state, w=7.6, h=2.2):
    face, ink = ("#dff0d8", GREEN) if state == "PASS" else ("#fde7c7", AMBER)
    ax.add_patch(patches.FancyBboxPatch(
        (x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0.1,rounding_size=1.1",
        linewidth=1.1, edgecolor=ink, facecolor=face, zorder=6))
    ax.text(x, y, "%s %s" % (name, "PASS" if state == "PASS" else "open"),
            fontsize=5.5, fontweight="bold", color=ink, ha="center",
            va="center", zorder=7)


def route(ax, points, label="", colour="#444444", dashed=False, size=6.0,
          offset=(0.0, 0.0), label_size=5.8):
    """A polyline with one arrowhead at the far end."""
    for start, end in zip(points[:-2], points[1:-1]):
        ax.add_line(Line2D([start[0], end[0]], [start[1], end[1]],
                           color=colour, linewidth=0.9, zorder=2,
                           linestyle=(0, (3, 2)) if dashed else "solid"))
    arrow(ax, points[-2][0], points[-2][1], points[-1][0], points[-1][1],
          label="", colour=colour, dashed=dashed, size=size)
    if label:
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        ax.text(sum(xs) / len(xs) + offset[0], sum(ys) / len(ys) + offset[1],
                label, fontsize=label_size, color=colour, ha="center",
                va="center", zorder=5,
                bbox=dict(boxstyle="round,pad=0.15", facecolor="white",
                          edgecolor="none", alpha=0.85))


def arrow(ax, x1, y1, x2, y2, label="", dashed=False, colour="#444444",
          size=6.0, offset=(0.0, 0.0), label_size=5.8, style="-|>"):
    ax.add_patch(patches.FancyArrowPatch(
        (x1, y1), (x2, y2), arrowstyle=style, mutation_scale=9,
        linewidth=0.9, color=colour, zorder=2, shrinkA=1.5, shrinkB=1.5,
        linestyle=(0, (3, 2)) if dashed else "solid"))
    if label:
        ax.text((x1 + x2) / 2 + offset[0], (y1 + y2) / 2 + offset[1], label,
                fontsize=label_size, color=colour, ha="center", va="center",
                zorder=5,
                bbox=dict(boxstyle="round,pad=0.15", facecolor="white",
                          edgecolor="none", alpha=0.85))


def build(ax):
    ax.set_xlim(0, W)
    ax.set_ylim(0, H)
    ax.axis("off")

    ax.text(W / 2, 162.5,
            "ZCU208 DOA V7 — the whole system, block by block, gate by gate",
            fontsize=16, fontweight="bold", ha="center", va="center")
    ax.text(W / 2, 159.2,
            "green = closed in this repository by a script   ·   amber = written, "
            "never run (no tool or no board)   ·   dashed = optional / not built",
            fontsize=8.4, ha="center", va="center", color="#555555")

    for key in ZONES:
        zone(ax, key)

    # ------------------------------------------------------------------ 1 RF
    box(ax, 3, 143.0, 18, 9.5, "2x2 array (4 elements)",
        "one plane, axes 25 / 30 / 150 mm\nV07 4 and 12")
    box(ax, 23, 143.0, 14, 9.5, "RF cables", "phase-matched,\nbaluns, 4 channels")
    box(ax, 39, 143.0, 18, 9.5, "RF-ADC", "4 x 2 GS/s\nRFSoC tile 228 (V03)")
    box(ax, 59, 143.0, 17, 9.5, "MTS clock", "LMK + PLL\none reference for all 4")
    box(ax, 78, 143.0, 18, 9.5, "DAC -> ADC loopback", "known delay,\nG5 only", dashed=True,
        face="#f7f7f7")

    arrow(ax, 21, 147.7, 23, 147.7)
    arrow(ax, 37, 147.7, 39, 147.7, "2 GS/s", offset=(0.2, 2.6))
    arrow(ax, 59, 147.7, 57.2, 147.7, colour=GREY)
    arrow(ax, 78, 147.7, 57.2, 147.7, "", dashed=True, colour=GREY)

    gate(ax, 12, 140.6, "G6", "NOT RUN")
    gate(ax, 48, 140.6, "G5", "NOT RUN")

    # ------------------------------------------------------------------ 2 PL
    box(ax, 3, 116.0, 14, 10.5, "rfdc_repack4",
        "SSR-8 gearbox, 250 MHz\nAXI-Stream (V05)")
    box(ax, 19, 116.0, 15, 10.5, "doa_subband_bridge_4ch",
        "4-stream bridge\nhost-tested")
    box(ax, 36, 116.0, 16, 10.5, "spectrum_power4",
        "410 carriers\nper-bin power")
    box(ax, 54, 116.0, 13, 10.5, "candidate_peak4", "peak + noise gate\nnot full CA-CFAR")
    box(ax, 69, 116.0, 13, 10.5, "trigger + capture", "4096 x 4 complex\none burst per bin")
    box(ax, 84, 116.0, 13, 10.5, "AXI-Lite + DMA", "regs + interrupt\n128 B per burst")

    box(ax, 3, 102.5, 19, 10.5, "doa_covariance_4ch_v4", "4x4 covariance, int64\n128 B, one burst")
    box(ax, 24, 102.5, 21, 10.5, "phase_interf_4ch",
        "per-bin cross-spectrum\n+ CORDIC phase (V07 5-7)")
    box(ax, 47, 102.5, 16, 10.5, "beam_weight_4ch", "vector monitor\noptional", dashed=True,
        face="#f7f7f7")

    arrow(ax, 17, 121.2, 19, 121.2)
    arrow(ax, 34, 121.2, 36, 121.2, "4 streams", offset=(0, 2.1))
    arrow(ax, 52, 121.2, 54, 121.2, "candidates", offset=(0, 2.1))
    arrow(ax, 67, 121.2, 69, 121.2, "trigger", offset=(0, 2.1))
    arrow(ax, 82, 121.2, 84, 121.2, "control", offset=(0, 2.1))
    arrow(ax, 75.5, 116.0, 75.5, 115.0)
    arrow(ax, 75.5, 115.0, 34.0, 115.0, "snapshots", offset=(0, 1.4))
    arrow(ax, 34.0, 115.0, 34.0, 113.0)
    arrow(ax, 65.0, 115.0, 12.0, 115.0, "", colour=GREY)
    arrow(ax, 12.0, 115.0, 12.0, 113.0, "", colour=GREY)
    arrow(ax, 36, 116.0, 36, 113.0, "", colour=GREY)
    arrow(ax, 63, 107.7, 47, 107.7)

    gate(ax, 9.5, 99.2, "G2", "NOT RUN")
    gate(ax, 37.0, 99.2, "G1a/b/c", "PASS")
    gate(ax, 62.0, 99.2, "G3", "NOT RUN")
    gate(ax, 80.0, 99.2, "G4", "NOT RUN")

    # ------------------------------------------------------------------ 3 RPU
    box(ax, 3, 84.0, 14, 10.0, "WPI solve", "2x2 weighted LS\n(V07 6, 10)")
    box(ax, 19, 84.0, 14, 10.0, "ambiguity / wrap", "consistency check\non 6 baselines")
    box(ax, 35, 84.0, 15, 10.0, "ML + Gauss-Newton", "36-point local search\n2 GN steps")
    box(ax, 52, 84.0, 14, 10.0, "unit-vector EKF", "6-state, one update\nper frame")
    box(ax, 68, 84.0, 28, 10.0, "clustering  (V07 15)", "label, do not mask: (f, az, t) -> tracks")

    box(ax, 3, 68.0, 14, 10.0, "motion model (16)", "rate + open\nthe first gate")
    box(ax, 19, 68.0, 16, 10.0, "feature models (17)", "rate / mode /\npattern / drop")
    box(ax, 39, 68.0, 25, 10.0, "association ladder (19)",
        "mod > direction > bandwidth > cadence > [cepstrum]")
    box(ax, 67, 68.0, 30, 10.0, "AMC  (18, 20)",
        "6 features, one 1024-pt FFT, nearest class mean, label + margin",
        face="#dff0d8")

    box(ax, 39, 54.0, 25, 10.0, "track store", "tracks, confidence,\ndecoy flags, labels")
    box(ax, 67, 54.0, 30, 10.0, "verification index (13)",
        "cepstrum of the cell: one arrival or two? 16 ns resolution")

    box(ax, 3, 54.0, 32, 10.0, "cost the ladder minimises",
        "(dir / gate)^2 + (bw / gate)^2 + [label != track label] x 1.0\n"
        "+ ((cadence - track cadence) / 0.4)^2      V07 15-19",
        face="#f6faf6", title_size=6.8, sub_size=6.0, dashed=True)

    arrow(ax, 17, 89, 19, 89)
    arrow(ax, 33, 89, 35, 89)
    arrow(ax, 50, 89, 52, 89)
    arrow(ax, 66, 89, 68, 89)
    arrow(ax, 80, 84.0, 80, 78.0, "detections", offset=(5.4, 0))
    arrow(ax, 70, 84.0, 62, 78.0, "")
    arrow(ax, 67, 73.0, 64, 73.0)
    arrow(ax, 51.5, 68.0, 51.5, 64.0, "cells", offset=(4.6, 0))
    route(ax, [(68.5, 64.0), (68.5, 66.5), (64.5, 66.5), (64.5, 68.0)])
    arrow(ax, 16, 73.0, 19, 73.0)
    arrow(ax, 35, 73.0, 39, 73.0, "params", offset=(0, 1.6), colour=GREY, dashed=True)

    gate(ax, 96.0, 66.3, "G8a", "PASS")
    gate(ax, 87.6, 66.3, "G8b", "NOT RUN")
    gate(ax, 79.2, 66.3, "G8c", "NOT RUN")
    gate(ax, 96.0, 52.0, "G7a", "PASS")
    gate(ax, 87.6, 52.0, "G7b", "NOT RUN")

    # ------------------------------------------------------------------ 4 A53
    box(ax, 3, 33.0, 18, 9.5, "calibration manager", "phase/gain vs frequency,\nMTS, temperature")
    box(ax, 23, 33.0, 16, 9.5, "policy configuration", "which rungs, which\norder, which gates")
    box(ax, 41, 33.0, 16, 9.5, "telemetry / network", "tracks, flags, health")
    box(ax, 59, 33.0, 14, 9.5, "logging (HDF5)", "captures,\nevidence files")
    box(ax, 75, 33.0, 21, 9.5, "operator display", "map, tracks,\ndecoy flags")
    box(ax, 3, 26.0, 18, 4.5, "health / watchdog", "", dashed=True, face="#f7f7f7",
        title_size=6.8)

    arrow(ax, 12, 33.0, 12, 30.5, "", colour=GREY)
    arrow(ax, 57, 37.7, 75, 37.7, "telemetry", offset=(0, 1.6))
    route(ax, [(9, 42.5), (2.3, 44.5), (2.3, 87.0), (3.0, 87.0)],
          "phase/gain", colour=GREY, offset=(3.4, 0))
    route(ax, [(37.0, 42.5), (37.0, 65.5), (39.0, 65.5), (39.0, 68.0)])
    route(ax, [(51.5, 54.0), (51.5, 47.5), (49.0, 47.5), (49.0, 42.5)],
          "10 Hz tracks", colour=GREY, offset=(0, 1.5))

    # ---------------------------------------------------------------- 5 host
    box(ax, 3, 8.5, 19, 8.5, "python3 scripts/*.py", "9 studies, all PASS\nG0")
    box(ax, 24, 8.5, 18, 8.5, "g++ core + kernel", "bit-exact fixed point\nG1a / G1b")
    box(ax, 44, 8.5, 16, 8.5, "gcc AMC port", "firmware == model,\n100 %  G8a")
    box(ax, 62, 8.5, 14, 8.5, "mh_lint", "8 MATLAB files\nparse clean")
    box(ax, 78, 8.5, 18, 8.5, "MATLAB references", "estimator, calibration,\nEmbedded Coder source",
        dashed=True, face="#f7f7f7")

    arrow(ax, 12.5, 17.0, 12.5, 20.0, "", dashed=True, colour=GREY)
    arrow(ax, 52.0, 17.0, 52.0, 20.0, "", dashed=True, colour=GREY)
    arrow(ax, 87.0, 17.0, 87.0, 20.0, "", dashed=True, colour=GREY)
    arrow(ax, 87.0, 54.0, 87.0, 47.0, "", dashed=True, colour=GREY)

    gate(ax, 12.5, 6.0, "G0", "PASS")
    gate(ax, 33.0, 6.0, "G1a/b", "PASS")
    gate(ax, 52.0, 6.0, "G8a", "PASS")
    gate(ax, 69.0, 6.0, "G8b", "NOT RUN")

    # ---------------------------------------------------------------- legend
    handles = [
        Line2D([0], [0], marker="s", color="none", markerfacecolor="#ffffff",
               markeredgecolor="#333333", markersize=11,
               label="block implemented in this repository"),
        Line2D([0], [0], marker="s", color="none", markerfacecolor="#dff0d8",
               markeredgecolor=GREEN, markersize=11,
               label="measured here, host, PASS"),
        Line2D([0], [0], marker="s", color="none", markerfacecolor="#f7f7f7",
               markeredgecolor=GREY, markersize=11, label="written, never run"),
        Line2D([0], [0], marker="s", color="none", markerfacecolor="#dff0d8",
               markeredgecolor=GREEN, markersize=11, label="gate closed"),
        Line2D([0], [0], marker="s", color="none", markerfacecolor="#fde7c7",
               markeredgecolor=AMBER, markersize=11, label="gate open"),
    ]
    ax.legend(handles=handles, loc="lower left", fontsize=6.6, ncol=5,
              frameon=False, bbox_to_anchor=(0.012, 0.003),
              handletextpad=0.4, columnspacing=1.4)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()

    figure, ax = plt.subplots(figsize=(19.6, 32.5))
    build(ax)
    os.makedirs(args.out, exist_ok=True)
    png = os.path.join(args.out, "system_block.png")
    svg = os.path.join(args.out, "system_block.svg")
    figure.savefig(png, dpi=150, bbox_inches="tight", facecolor="white")
    figure.savefig(svg, bbox_inches="tight", facecolor="white")
    plt.close(figure)
    print("wrote %s" % os.path.relpath(png, ROOT))
    print("wrote %s" % os.path.relpath(svg, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
