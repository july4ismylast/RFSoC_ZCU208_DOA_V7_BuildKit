#!/usr/bin/env python3
"""Draw the twenty build stages as one flow: what runs, with which tool, leaving what.

    docs/diagrams/build_stages.png/.svg

The three inputs no stage produces (the MTS base, the pinned upstream checkout, the IP
catalog lock proof's own inputs) are drawn at the top with an arrow into the first stage
that needs them, because forgetting one of them is what makes a fresh run fail at
step00 rather than at step07.

Run: python3 scripts/draw_stages.py [--out DIR]
"""
from __future__ import annotations

import argparse
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as patches  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "docs", "diagrams")

TOOL_COLOURS = {
    "shell": "#6b7280",
    "git": "#0f766e",
    "vitis_hls": "#b45309",
    "matlab": "#1d4ed8",
    "vivado": "#166534",
    "python": "#7c3aed",
}

STAGES = [
    ("step00_preflight", "shell", "scripts/preflight.sh + ip catalog proof",
     "build/output/ip_catalog_lock.txt"),
    ("step01_fetch_references", "git", "scripts/fetch_upstream.sh $FETCH_SET",
     "upstream/RFSoC-MTS at the pinned SHA"),
    ("step02_hls_covariance", "vitis_hls", "ip/custom/doa_covariance_4ch_v4",
     "doa_covariance_4ch_v4:7.1"),
    ("step03_hls_spectrum", "vitis_hls", "ip/custom/spectrum_power4",
     "spectrum_power4:2.0"),
    ("step04_hls_candidate", "vitis_hls", "ip/custom/candidate_peak4",
     "candidate_peak4:1.0"),
    ("step04_hls_beam", "vitis_hls", "ip/custom/beam_weight_4ch",
     "beam_weight_4ch:2.1"),
    ("step05_hls_repack", "vitis_hls", "ip/custom/rfdc_repack4",
     "rfdc_repack4:1.0"),
    ("step05_channelizer", "matlab", "scripts/build_channelizer.sh $CHANNELIZER_FLOW",
     "matlab_channelizer:7.0"),
    ("step05_subband_bridge", "vivado", "ip/custom/doa_subband_bridge_4ch (RTL, packaged)",
     "doa_subband_bridge_4ch:1.0"),
    ("step05_hls_phase_interf", "vitis_hls", "ip/custom/phase_interf_4ch",
     "phase_interf_4ch:1.0 (not attached)"),
    ("step06_collect_ip", "python", "scripts/collect_ip.sh",
     "build/ip_repo + ip_manifest.tsv, every VLNV checked"),
    ("step07_vivado_project", "vivado", "common/vivado/07_create_project_from_base.tcl",
     "build/vivado/doa_v7_zcu208/doa_v7_zcu208.xpr"),
    ("step08_vivado_integrate", "vivado", "08_integrate_doa_v7.tcl + zcu208_bd_map.tcl",
     "BD mts + hierarchy /doa_v7, wired and addressed"),
    ("step09_vivado_validate", "vivado", "09_validate.tcl",
     "BD validation and DRC clean"),
    ("step10_synth", "vivado", "10_synth.tcl",
     "post_synth_utilization.rpt, post_synth_timing.rpt"),
    ("step11_impl", "vivado", "11_impl.tcl",
     "post_route_utilization.rpt, post_route_timing.rpt, routed DCP"),
    ("step12_bitstream", "vivado", "12_bitstream.tcl",
     "build/output/doa_v7_zcu208.bit"),
    ("step13_export_xsa", "vivado", "13_export_xsa.tcl",
     "build/output/doa_v7_zcu208.xsa"),
    ("step14_hil_vectors", "matlab", "scripts/generate_hil.sh (R2024a)",
     "build/hil_vectors/ stimulus + expected"),
    ("step15_package", "shell", "scripts/package_release.sh",
     "build/release/*.tar.gz + .sha256"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    rows = len(STAGES)
    row_h = 0.46
    top = rows * row_h + 3.4
    fig, ax = plt.subplots(figsize=(13.6, top * 0.62))
    ax.set_xlim(0, 17.0)
    ax.set_ylim(0, top)
    ax.axis("off")

    ax.text(0.15, top - 0.20,
            "the twenty build stages: what runs, with which tool, leaving what",
            fontsize=10.4, fontweight="bold", va="top")
    ax.text(0.15, top - 0.58,
            "make pipeline runs them in this order and stops at the first failure; "
            "make status shows which stamps exist",
            fontsize=6.6, color="#555555", va="top")

    # the three inputs no stage produces
    pre = [
        ("stage V03: make mts-base", "build/mts_base_src_2023p2/.../mts/mts.xpr",
         "step00 checks it, step07 opens it"),
        ("upstream/RFSoC-MTS", "pinned SHA in config/upstream_repositories.tsv",
         "step01 fetches, V03 builds on it"),
        ("config/ip_versions.tcl", "the VLNV lock",
         "every stage compares against it"),
    ]
    for index, (name, detail, why) in enumerate(pre):
        y = top - 1.20 - index * 0.50
        ax.add_patch(patches.FancyBboxPatch(
            (0.35, y - 0.17), 5.9, 0.36, boxstyle="round,pad=0.02,rounding_size=0.06",
            linewidth=1.1, edgecolor="#a03c3c", facecolor="#fdf2f2", zorder=3))
        ax.text(0.45, y, name, fontsize=6.4, fontweight="bold", color="#a03c3c",
                va="center", family="monospace", zorder=4)
        ax.text(6.4, y, "%s - %s" % (detail, why), fontsize=5.8, color="#7a3b3b",
                va="center", family="monospace", zorder=4)

    # the stages
    y = rows * row_h + 0.30
    positions = []
    for index, (name, tool, command, artifact) in enumerate(STAGES):
        colour = TOOL_COLOURS[tool]
        ax.add_patch(patches.FancyBboxPatch(
            (0.35, y - 0.17), 16.3, 0.36, boxstyle="round,pad=0.01,rounding_size=0.05",
            linewidth=1.0, edgecolor=colour, facecolor="white", zorder=3))
        ax.add_patch(patches.Rectangle((0.35, y - 0.17), 0.10, 0.36, facecolor=colour,
                                       edgecolor="none", zorder=4))
        ax.text(0.55, y, "%2d  %s" % (index + 1, name), fontsize=6.8, fontweight="bold",
                color=colour, va="center", family="monospace", zorder=4)
        ax.text(6.05, y, command, fontsize=6.0, color="#333333", va="center",
                family="monospace", zorder=4)
        ax.text(11.35, y, artifact, fontsize=5.8, color="#555555", va="center",
                family="monospace", zorder=4)
        positions.append((0.35, y))
        y -= row_h

    for index in range(len(positions) - 1):
        x, y0 = positions[index]
        ax.annotate("", xy=(x + 0.18, positions[index + 1][1] + 0.19),
                    xytext=(x + 0.18, y0 - 0.19),
                    arrowprops=dict(arrowstyle="-|>", color="#999999", lw=1.0,
                                    mutation_scale=8))

    handles = [Line2D([0], [0], color=c, lw=4, label=t) for t, c in TOOL_COLOURS.items()]
    ax.legend(handles=handles, loc="upper right", fontsize=6.2, frameon=False,
              ncol=3, title="tool", title_fontsize=6.2,
              bbox_to_anchor=(0.995, 0.985))

    ax.text(0.35, 0.06,
            "sources: the $(STAMP_DIR)/step*.done recipes in Makefile (line numbers in "
            "docs/STAGE_FLOW.md) and scripts/run_stage.sh",
            fontsize=5.8, color="#555555", va="bottom")

    png = os.path.join(args.out, "build_stages.png")
    svg = os.path.join(args.out, "build_stages.svg")
    fig.savefig(png, dpi=190, bbox_inches="tight", facecolor="white")
    fig.savefig(svg, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("wrote %s" % os.path.relpath(png, ROOT))
    print("wrote %s" % os.path.relpath(svg, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
