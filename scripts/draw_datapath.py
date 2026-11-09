#!/usr/bin/env python3
"""Three port-level figures for the ZCU208 DOA V7 design.

    docs/diagrams/datapath_rf.png      250 MHz RF domain: RFDC -> repack -> 4 channelizers -> bridge
    docs/diagrams/datapath_doa.png     125 MHz /doa_v7: the three consumers and the PS FIFOs
    docs/diagrams/control_map.png      AXI4-Lite side, and what is deliberately not attached

Each figure is a separate picture on purpose: one picture with all twenty blocks was
unreadable, and an unreadable diagram is worse than three clear ones.

Widths are the TDATA widths the IP declares (`ap_axiu<N,...>` in ip/custom/*/src/*.hpp,
416 bit for the channelizer output, 192 bit for the candidate record).  Connections are
the ones the block design makes: config/zcu208_bd_map.tcl and
common/vivado/create_doa_v7_hier.tcl.

Run: python3 scripts/draw_datapath.py [--out DIR]
"""
from __future__ import annotations

import argparse
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as patches  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "docs", "diagrams")

RF = "#b8720d"
DOA = "#2f6ba8"
PS = "#2f7d47"
CTRL = "#6b4fa0"
GREY = "#4a4a4a"


def box(ax, x, y, w, h, title, sub="", edge=GREY, face="white", left=(), right=(),
        ts=7.4, ps=6.2, sub_size=5.4):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.08",
        linewidth=1.5, edgecolor=edge, facecolor=face, zorder=3))
    ax.text(x + w / 2, y + h - 0.16, title, ha="center", va="top", fontsize=ts,
            fontweight="bold", color=edge, zorder=4)
    if sub:
        ax.text(x + w / 2, y + h - 0.24 - 0.11 * ts / 7.4, sub, ha="center", va="top",
                fontsize=sub_size, color="#555555", style="italic", zorder=4)
    rows = max(len(left), len(right), 1)
    if h < 0.95 and rows == 1:
        # compact box: one port per side, name and width on the same baseline
        py = y + h / 2.0 - (0.10 if h < 0.70 else 0.0)
        for name, bits in left:
            ax.text(x + 0.07, py, name + (" " + str(bits) if bits else ""), ha="left",
                    va="center", fontsize=ps, family="monospace", zorder=4)
        for name, bits in right:
            ax.text(x + w - 0.07, py, name + (" " + str(bits) if bits else ""),
                    ha="right", va="center", fontsize=ps, family="monospace", zorder=4)
        return (x, y, w, h)
    shift = 0.30 if sub else 0.0        # keep the subtitle clear of the first port row
    step = (h - 0.52 - shift) / rows
    for index, (name, bits) in enumerate(left):
        py = y + h - 0.50 - shift - index * step
        ax.text(x + 0.06, py, name, ha="left", va="center", fontsize=ps,
                family="monospace", zorder=4)
        if bits:
            ax.text(x + 0.06, py - 0.115, "%d bit" % bits, ha="left", va="center",
                    fontsize=5.0, color="#666666", family="monospace", zorder=4)
    for index, (name, bits) in enumerate(right):
        py = y + h - 0.50 - shift - index * step
        ax.text(x + w - 0.06, py, name, ha="right", va="center", fontsize=ps,
                family="monospace", zorder=4)
        if bits:
            ax.text(x + w - 0.06, py - 0.115, "%d bit" % bits, ha="right", va="center",
                    fontsize=5.0, color="#666666", family="monospace", zorder=4)
    return (x, y, w, h)


def port(b, index, count, side, shift=0.30):
    x, y, w, h = b
    if h < 0.95 and max(count, 1) == 1:
        py = y + h / 2.0 - (0.10 if h < 0.70 else 0.0)
        return (x + w, py) if side == "r" else (x, py)
    py = y + h - 0.50 - shift - index * (h - 0.52 - shift) / max(count, 1)
    return (x + w, py) if side == "r" else (x, py)


def arrow(ax, p0, p1, label="", colour=GREY, dashed=False, rad=0.0, size=6.0,
          label_at=0.5, label_dy=0.07):
    style = dict(color=colour, linewidth=1.6, zorder=2, arrowstyle="-|>",
                 mutation_scale=10, linestyle="--" if dashed else "-")
    ax.add_patch(patches.FancyArrowPatch(p0, p1, connectionstyle="arc3,rad=%s" % rad, **style))
    if label:
        lx = p0[0] + (p1[0] - p0[0]) * label_at
        ly = p0[1] + (p1[1] - p0[1]) * label_at
        ax.text(lx, ly + label_dy, label, ha="center", va="bottom", fontsize=size,
                color=colour, family="monospace", zorder=6,
                bbox=dict(boxstyle="round,pad=0.12", fc="white", ec="none", alpha=0.95))


def frame(ax, x, y, w, h, label, edge, face):
    ax.add_patch(patches.FancyBboxPatch(
        (x, y), w, h, boxstyle="round,pad=0.04,rounding_size=0.12",
        linewidth=1.1, edgecolor=edge, facecolor=face, zorder=1))
    ax.text(x + 0.10, y + h - 0.08, label, ha="left", va="top", fontsize=7.4,
            fontweight="bold", color=edge, zorder=5)


def title(ax, text, subtitle=""):
    ax.text(0.10, 1.0, text, transform=ax.transAxes, fontsize=10.0,
            fontweight="bold", va="top")
    if subtitle:
        ax.text(0.10, 0.955, subtitle, transform=ax.transAxes, fontsize=6.6,
                va="top", color="#555555")


def note(ax, text):
    ax.text(0.10, 0.012, text, transform=ax.transAxes, fontsize=6.0, color="#555555",
            va="bottom")


def save(fig, out_dir, stem):
    png = os.path.join(out_dir, stem + ".png")
    svg = os.path.join(out_dir, stem + ".svg")
    fig.savefig(png, dpi=200, bbox_inches="tight", facecolor="white")
    fig.savefig(svg, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return png, svg


def rf_domain(out_dir):
    fig, ax = plt.subplots(figsize=(14.6, 5.6))
    ax.set_xlim(0, 14.6)
    ax.set_ylim(0, 5.6)
    ax.axis("off")
    title(ax, "250 MHz RF domain - step05_hls_repack > step05_channelizer > step05_subband_bridge",
          "clkRFdiv2 = 250 MHz. 8 x 128-bit RFDC streams -> 4 x 256-bit complex -> 4 x 416-bit "
          "bins -> three 512-bit /doa_v7 streams")
    frame(ax, 0.10, 0.55, 14.35, 4.30, "", RF, "#fffaf2")

    rfdc = box(ax, 0.30, 1.45, 2.30, 2.60, "usp_rf_data_converter",
               "MTS base BD\n4 ADC channels", edge=RF, sub_size=5.2,
               right=[("m00/m01", 128), ("m02/m03", 128), ("m10/m11", 128), ("m12/m13", 128)])

    repack = box(ax, 3.35, 1.55, 2.25, 2.40, "doa_rfdc_repack_0", "rfdc_repack4", edge=RF,
                 left=[("ch0 I/Q", 128), ("ch1 I/Q", 128), ("ch2 I/Q", 128), ("ch3 I/Q", 128)],
                 right=[("ch0", 256), ("ch1", 256), ("ch2", 256), ("ch3", 256)])

    chans = []
    for index in range(4):
        chans.append(box(ax, 6.35, 3.28 - index * 0.62, 2.45, 0.58,
                         "doa_channelizer_%d" % index,
                         "", edge=RF,
                         left=[("s_axis", 256)], right=[("m_axis", 416)], ts=6.4, ps=5.3))

    ax.text(0.40, 0.85, "all four are matlab_channelizer 7.0 (dsphdl.Channelizer, SSR-8, 1024 bins):\n"
                        "256 bit in -> 416 bit out (8 complex s26 bins per beat), TLAST every 128 beats",
            fontsize=5.8, color=RF, ha="left", va="center", family="monospace")

    bridge = box(ax, 9.55, 1.30, 2.55, 3.10, "doa_subband_bridge_0",
                 "doa_subband_bridge_4ch", edge=RF,
                 left=[("ch0..ch3", 416), ("candidate", 192), ("s_axi", 32)],
                 right=[("search", 512), ("capture", 512), ("beam", 512), ("mon0..3", 128)],
                 ts=6.6, ps=5.5, sub_size=5.0)

    for index in range(4):
        arrow(ax, port(rfdc, index, 4, "r"), port(repack, index, 4, "l"), colour=RF,
              label="128" if index == 0 else "")
    for index in range(4):
        arrow(ax, port(repack, index, 4, "r"), port(chans[index], 0, 1, "l"), colour=RF,
              label="256" if index == 0 else "")
    for index in range(4):
        arrow(ax, port(chans[index], 0, 1, "r"), port(bridge, index, 4, "l"), colour=RF,
              label="416" if index == 0 else "")

    outs = box(ax, 12.55, 1.30, 1.75, 3.10, "to /doa_v7",
               "3 x axis_clock_converter",
               edge=GREY, face="#f7f7f7",
               left=[("S_AXIS_SEARCH", 512), ("S_AXIS_CAPTURE", 512),
                     ("S_AXIS_BEAM", 512)], ts=6.6, ps=5.5, sub_size=4.9)
    for index in range(3):
        arrow(ax, port(bridge, index, 4, "r"), port(outs, index, 3, "l"), colour=GREY,
              label="512")
    ax.text(9.55, 4.55, "s_axis_candidate (192 bit) comes back from /doa_v7:\n"
                        "candidate_peak flags the active bin", fontsize=5.6, color=GREY,
            ha="left", va="bottom", family="monospace")
    note(ax, "the three converters are doa_cdc_search, doa_cdc_capture and doa_cdc_beam; "
             "sources: config/zcu208_bd_map.tcl, ip/custom/*/src/*.hpp, V05_RFDC_REPACK4_SPEC.md")
    return save(fig, out_dir, "datapath_rf")


def doa_domain(out_dir):
    fig, ax = plt.subplots(figsize=(14.6, 7.4))
    ax.set_xlim(0, 14.6)
    ax.set_ylim(0, 7.4)
    ax.axis("off")
    title(ax, "125 MHz /doa_v7 - step03_hls_spectrum > step04_hls_candidate | "
              "step02_hls_covariance | step04_hls_beam",
          "clk_doa_125m = 125 MHz, derived from clkRFdiv2 by doa_clk_wiz_125m")
    frame(ax, 0.10, 0.55, 14.35, 6.15, "", DOA, "#f3f7fc")

    # row 1: search -> spectrum -> candidate -> back to the RF domain
    spectrum = box(ax, 1.85, 4.90, 2.25, 1.45, "spectrum_power", "spectrum_power4", edge=DOA,
                   left=[("s_axis", 512)], right=[("m_axis", 256)])
    candidate = box(ax, 4.75, 4.90, 2.25, 1.45, "candidate_peak", "candidate_peak4", edge=DOA,
                    left=[("s_axis", 256)], right=[("m_axis", 192)])
    back = box(ax, 8.05, 4.90, 2.55, 1.45, "doa_cdc_candidate", "axis_clock_converter",
               edge=GREY, face="#f7f7f7",
               left=[("S_AXIS", 192)], right=[("M_AXIS", 192)], ts=6.2, ps=5.5,
               sub_size=5.0)
    arrow(ax, (1.05, 5.62), port(spectrum, 0, 1, "l"), colour=DOA)
    arrow(ax, port(spectrum, 0, 1, "r"), port(candidate, 0, 1, "l"), colour=DOA, label="256")
    arrow(ax, port(candidate, 0, 1, "r"), port(back, 0, 1, "l"), colour=DOA, label="192")
    ax.text(0.25, 5.74, "S_AXIS_SEARCH  512 bit  <- doa_cdc_search", fontsize=6.0,
            color=DOA, ha="left", va="bottom", family="monospace")
    ax.text(10.70, 5.40, "192-bit record back to the\nbridge (active_bin)",
            fontsize=5.6, color=GREY, ha="left", va="center", family="monospace")

    # row 2: capture -> covariance -> dwc -> fifo
    covariance = box(ax, 1.85, 2.85, 2.25, 1.45, "covariance", "doa_covariance_4ch_v4",
                     edge=DOA, left=[("s_axis", 512)],
                     right=[("m_axis", 64), ("16 beats/frame", 0)], ts=6.6, ps=5.5,
                     sub_size=5.0)
    cov_dwc = box(ax, 4.75, 2.95, 1.85, 1.25, "doa_cov_dwc", "axis_dwidth_converter", edge=PS,
                  left=[("S_AXIS", 64)], right=[("M_AXIS", 32)], ts=6.0, ps=5.4,
                  sub_size=4.8)
    cov_fifo = box(ax, 7.10, 2.95, 2.20, 1.25, "doa_cov_fifo", "axi_fifo_mm_s, depth 512",
                   edge=PS, left=[("AXIS", 32)], right=[("S_AXI", 32)], ts=6.0, ps=5.4,
                   sub_size=4.8)
    arrow(ax, (1.05, 3.57), port(covariance, 0, 2, "l"), colour=DOA)
    arrow(ax, port(covariance, 0, 2, "r"), port(cov_dwc, 0, 1, "l"), colour=DOA, label="64")
    arrow(ax, port(cov_dwc, 0, 1, "r"), port(cov_fifo, 0, 1, "l"), colour=PS, label="32")
    ax.text(0.25, 3.70, "S_AXIS_DOA_CAPTURE  512 bit  <- doa_cdc_capture", fontsize=6.0,
            color=DOA, ha="left", va="bottom", family="monospace")

    # row 3: beam monitor -> dwc -> fifo
    beam = box(ax, 1.85, 0.80, 2.25, 1.45, "beam_monitor", "beam_weight_4ch (diagnostic)",
               edge=DOA, left=[("s_axis", 512)], right=[("m_axis", 256)], ts=6.6, ps=5.5,
               sub_size=4.8)
    beam_dwc = box(ax, 4.75, 0.90, 1.85, 1.25, "doa_beam_dwc", "axis_dwidth_converter",
                   edge=PS, left=[("S_AXIS", 256)], right=[("M_AXIS", 32)], ts=6.0, ps=5.4,
                   sub_size=4.8)
    beam_fifo = box(ax, 7.10, 0.90, 2.20, 1.25, "doa_beam_fifo",
                    "axi_fifo_mm_s, depth 2048", edge=PS,
                    left=[("AXIS", 32)], right=[("S_AXI", 32)], ts=6.0, ps=5.4, sub_size=4.8)
    arrow(ax, (1.05, 1.52), port(beam, 0, 1, "l"), colour=DOA)
    arrow(ax, port(beam, 0, 1, "r"), port(beam_dwc, 0, 1, "l"), colour=DOA, label="256")
    arrow(ax, port(beam_dwc, 0, 1, "r"), port(beam_fifo, 0, 1, "l"), colour=PS, label="32")
    ax.text(0.25, 1.65, "S_AXIS_BEAM_MONITOR  512 bit  <- doa_cdc_beam", fontsize=6.0,
            color=DOA, ha="left", va="bottom", family="monospace")

    ps = box(ax, 10.55, 1.10, 2.35, 3.30, "Zynq UltraScale+ PS",
             "R5: DOA / AMC / tracking\nA53: Linux capture",
             edge=PS, left=[("S_AXI (cov)", 32), ("S_AXI (beam)", 32),
                            ("M_AXI_HPM0", 128)], ts=6.6, ps=5.4, sub_size=4.8)
    arrow(ax, port(cov_fifo, 0, 1, "r"), port(ps, 0, 3, "l"), colour=PS, rad=0.10)
    arrow(ax, port(beam_fifo, 0, 1, "r"), port(ps, 1, 3, "l"), colour=PS, rad=-0.10)

    ax.text(7.60, 6.42, "AXI4-Lite slaves of control_interconnect: covariance, candidate_peak,\n"
                        "beam_monitor, bridge s_axi, both FIFOs  (see control_map.png)",
            fontsize=6.0, color=CTRL, ha="left", va="center", family="monospace")
    note(ax, "sources: common/vivado/create_doa_v7_hier.tcl (the /doa_v7 hierarchy), "
             "config/zcu208_bd_map.tcl (FIFOs, dwidth converters). "
             "openai:doa:phase_interf_4ch:1.0 is packaged but not attached.")
    return save(fig, out_dir, "datapath_doa")


def control_map(out_dir):
    fig, ax = plt.subplots(figsize=(12.4, 6.4))
    ax.set_xlim(0, 12.4)
    ax.set_ylim(0, 6.4)
    ax.axis("off")
    title(ax, "AXI4-Lite control side - who the PS talks to, and who it does not")

    ps = box(ax, 0.35, 2.20, 2.20, 2.30, "Zynq UltraScale+ PS", "R5 + A53",
             edge=PS, right=[("M_AXI_HPM0", 128)])
    ic = box(ax, 3.20, 1.95, 2.05, 2.80, "control_interconnect", "smartconnect 1.0",
             edge=CTRL, left=[("S00_AXI", 128)], right=[("M00..M05", 32)])
    arrow(ax, port(ps, 0, 1, "r"), port(ic, 0, 1, "l"), colour=CTRL, label="128")

    slaves = [
        ("doa_cov_fifo", "axi_fifo_mm_s - covariance frames to the R5"),
        ("doa_beam_fifo", "axi_fifo_mm_s - beam frames to the R5"),
        ("doa_subband_bridge_0", "s_axi - active_bin, frame counters"),
        ("covariance", "s_axi_ctrl - calibration, frame length"),
        ("candidate_peak", "s_axi_ctrl - threshold Q8.8 (512 = peak > 2x mean)"),
        ("beam_monitor", "s_axi_ctrl - four Q1.15 weights"),
    ]
    y = 5.05
    for name, duty in slaves:
        b = box(ax, 6.35, y, 5.55, 0.62, name, duty, edge=CTRL, ts=6.6, ps=5.6,
                sub_size=5.2)
        arrow(ax, port(ic, 0, 1, "r"), port(b, 0, 1, "l"), colour=CTRL, rad=0.02)
        y -= 0.83

    ax.text(0.35, 0.30,
            "deliberately not attached:  openai:doa:phase_interf_4ch:1.0\n"
            "packaged and csim/csynth checked, but its net, clock and address come from\n"
            "V07 section 7.5 - attaching it is the remaining part of gate G4.",
            fontsize=6.4, color="#a03c3c", ha="left", va="bottom", family="monospace")
    return save(fig, out_dir, "control_map")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    produced = []
    produced += rf_domain(args.out)
    produced += doa_domain(args.out)
    produced += control_map(args.out)
    for path in produced:
        print("wrote %s" % os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
