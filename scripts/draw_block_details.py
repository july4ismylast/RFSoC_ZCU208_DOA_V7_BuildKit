#!/usr/bin/env python3
"""One internal block diagram per block: what is inside it, port by port, with notes.

    docs/diagrams/blocks/<stem>.png   (and .svg)

Twenty-three pictures: every PL block, the clocking, the control interconnect, the RPU
firmware (DOA, AMC, tracking), the APU/Linux side, the host benches, the Vivado base and
the IP packaging flow.  Each picture carries the block's inputs, its internal stages in
order, its outputs, and the notes that would otherwise only exist in a README.

Nothing here invents structure: the internal stages and register names come from
ip/custom/*/src/*.hpp, ip/custom/*/README.md, ip/custom/doa_subband_bridge_4ch/README.md
(register map), common/vivado/*.tcl (what the BD builds) and step3..step6 (the software).

Run: python3 scripts/draw_block_details.py [--only STEM]
"""
from __future__ import annotations

import argparse
import os
import textwrap

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as patches  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "docs", "diagrams", "blocks")

PL = "#b8720d"
DOA = "#2f6ba8"
PS = "#2f7d47"
CTRL = "#6b4fa0"
HOST = "#6b7280"

# stem, title, subtitle, colour, inputs, stages, outputs, notes
BLOCKS = [
    ("rfdc", "usp_rf_data_converter  (RF Data Converter, in the MTS base)",
     "4 ADC channels, 2.048 GSPS per channel, zone-2 R2C DDC, decimation by 4",
     PL,
     [("s_axi (config)", "32"), ("clk_adc0..3", "2.048 GHz"), ("clk_pl", "250 MHz")],
     [("ADC tile 225 ch0/ch1", "4 x 128-bit AXIS I/Q per channel"),
      ("ADC tile 226 ch2/ch3", "zone-2 real-to-complex mixer"),
      ("Digital decimation by 4", "512 MSPS complex per channel"),
      ("AXIS output stage", "m00/m01 .. m12/m13, 250 MHz, 128 bit each")],
     [("m00/m01 .. m12/m13", "8 x 128"), ("clkRFdiv2 out", "250 MHz")],
     ["configured by the MTS base project (stage V03), never by this repository's scripts",
      "the eight outputs are I/Q pairs per antenna: even stream = I, odd = Q",
      "repack4 exists because these are separate streams, not interleaved samples"]),

    ("rfdc_repack4", "doa_rfdc_repack_0  -  rfdc_repack4 1.0",
     "gearbox: eight RFDC streams -> four complex SSR-8 streams",
     PL,
     [("ch0_i .. ch3_q", "8 x 128")],
     [("pair I/Q per channel", "ch0: m00+m01 -> 4 complex words"),
      ("interleave samples", "word s = the s-th oldest sample in the beat"),
      ("pack {Q[31:16], I[15:0]}", "project-wide complex packing"),
      ("AXIS master x4", "one stream per antenna")],
     [("m_axis_ch0 .. ch3", "4 x 256")],
     ["no control port: it is pure wiring plus packing",
      "AMD's axis_combiner does not do this: it concatenates beats and leaves the consumer to un-interleave",
      "csim must be bit-exact before csynth runs (tb/rfdc_repack4_tb.cpp)"]),

    ("matlab_channelizer", "doa_channelizer_0..3  -  matlab_channelizer 7.0",
     "one 1024-bin transposed channelizer per antenna (dsphdl.Channelizer)",
     PL,
     [("s_axis", "256"), ("clock enable", "from the wrapper")],
     [("AXI4-Stream sink", "channelizer_axis_wrapper.sv"),
      ("prototype channelizer", "dsp.Channelizer, 8 subbands, FFT length 1024"),
      ("streaming core", "transposed FilterBank, 8 complex outputs per beat"),
      ("TLAST generator", "every 128 accepted beats = one snapshot"),
      ("sfix26_En24 output", "52 bit per complex bin word")],
     [("m_axis", "416"), ("tlast", "128 beats")],
     ["built by HDL Coder from MATLAB R2024a: make step05_channelizer",
      "systolic form was rejected: four of them reached 93.2% of the CLB LUTs",
      "ip/model_composer/channelizer is the alternative route and is unfinished"]),

    ("subband_bridge", "doa_subband_bridge_0  -  doa_subband_bridge_4ch 1.0",
     "lockstep ingestion, serialiser, packer, legacy monitor",
     PL,
     [("s_axis_ch0..3", "4 x 416"), ("s_axis_candidate", "192"), ("s_axi_ctrl", "32")],
     [("ingest + tready", "always ready: the channelizers can never stall"),
      ("scale stage", "sfix26_En24 -> sfix16_En15, half-up, saturating, SCALE_SHIFT=9"),
      ("BRAM snapshot store", "dual 128 x 512, one 4-channel snapshot"),
      ("search serialiser", "natural bin order 0..1023, 256 beats, TLAST"),
      ("selected-bin packer", "four snapshots per 512-bit beat"),
      ("beam packetiser", "64 beats per TLAST by default"),
      ("AXI-Lite registers", "active_bin, counters, drop counts")],
     [("m_axis_search", "512"), ("m_axis_capture", "512"), ("m_axis_beam", "512"),
      ("mon_ch0..3", "4 x 128")],
     ["the only block that knows everybody's timing; tready is tied high on purpose",
      "registers: 0x00 CTRL, 0x04 MANUAL_BIN, 0x08 SCALE_SHIFT, 0x0C CAPTURE_BEATS",
      "0x10 BEAM_PACKET_BEATS, 0x14 STATUS, 0x18 LAST_CANDIDATE, 0x1C..0x28 peak/avg,",
      "0x2C..0x34 frame counters, 0x38 CANDIDATE_COUNT, 0x3C DROP_COUNTS",
      "hand-written RTL packaged by package_ip.tcl; csim is a SystemVerilog test bench"]),

    ("cdc_forward", "doa_cdc_search / _capture / _beam  -  axis_clock_converter 1.1",
     "three 512-bit AXI4-Stream crossings, 250 MHz -> 125 MHz",
     PL,
     [("S_AXIS (250 MHz)", "512 x3")],
     [("asynchronous FIFO", "grey-coded pointers per direction"),
      ("data path", "TDATA + TVALID/TREADY/TLAST carried across"),
      ("packet integrity", "TLAST crosses the same boundary as the payload")],
     [("M_AXIS (125 MHz)", "512 x3")],
     ["one converter per stream: search, capture, beam",
      "candidate traffic crosses back in the other direction (doa_cdc_candidate)"]),

    ("cdc_candidate", "doa_cdc_candidate  -  axis_clock_converter 1.1",
     "192-bit crossing in the other direction: 125 MHz -> 250 MHz",
     DOA,
     [("S_AXIS (125 MHz)", "192")],
     [("asynchronous FIFO", "125 MHz write, 250 MHz read"),
      ("record integrity", "bin index, validity, peak and average cross together")],
     [("M_AXIS (250 MHz)", "192"), ("-> bridge active_bin", "latched")],
     ["this is the only loop that closes across the two clock domains",
      "it is why the bridge latches active_bin instead of reading a wire"]),

    ("spectrum_power", "spectrum_power  -  spectrum_power4 2.0",
     "four lanes of incoherent power: the detector statistic",
     DOA,
     [("s_axis", "512")],
     [("4 lanes x 4 channels", "complex sfix16 per word"),
      ("per-channel magnitude^2", "I^2 + Q^2, widened"),
      ("lane accumulation", "four unsigned 64-bit powers per beat"),
      ("TLAST copy", "frame boundaries preserved")],
     [("m_axis", "256")],
     ["one beat per clock, no control port",
      "this is the statistic the candidate gate thresholds; it is not the covariance"]),

    ("candidate_peak", "candidate_peak  -  candidate_peak4 1.0",
     "per-frame maximum versus the global average",
     DOA,
     [("s_axis", "256"), ("thresholdQ8_8", "16")],
     [("max tracker", "largest of the four 64-bit powers seen this frame"),
      ("average accumulator", "sum / bin count over the frame"),
      ("compare at TLAST", "peak > threshold x average (Q8.8, 512 = 2.0x)"),
      ("record builder", "bin index, validity, peak, average")],
     [("m_axis", "192")],
     ["deliberately not sold as CA-CFAR: it is a cheap reason to capture or not",
      "its record is what selects active_bin in the bridge, through the CDC"]),

    ("covariance", "covariance  -  doa_covariance_4ch_v4 7.1",
     "the DOA statistic: upper triangle of R = XX^H",
     DOA,
     [("s_axis", "512"), ("cal0..cal3", "4 x 32 (Q2.14)"), ("frameSamples", "16")],
     [("calibration", "complex Q2.14 gain per channel, >>14 rescale"),
      ("accumulate 4096 samples", "int64 accumulators, worst case 51 bits"),
      ("4 powers + 6 + 6 cross terms", "Re and Im kept separately"),
      ("emit 16 x 64-bit words", "one AXI4-Stream burst, TLAST at the end")],
     [("m_axis", "64 x 16 beats")],
     ["frame processor: II=1 during a 1024-beat capture, then a short burst",
      "it needs a triggered capture in front of it: the bridge's m_axis_capture",
      "csim must match all 16 words exactly before synthesis is allowed"]),

    ("beam_monitor", "beam_monitor  -  beam_weight_4ch 2.1",
     "diagnostic: are the weights really applied as computed?",
     DOA,
     [("s_axis", "512"), ("w0..w3", "4 x 32 (Q1.15)")],
     [("four Q1.15 weights", "one complex weight per antenna"),
      ("per-lane multiply-accumulate", "four lanes per clock"),
      ("round and saturate", "back to sfix16_En15")],
     [("m_axis", "256")],
     ["not used to estimate DOA and nothing downstream depends on it",
      "its purpose is to make a calibration or steering error visible in hardware"]),

    ("phase_interf", "phase_interf_4ch 1.0  (packaged, NOT attached)",
     "six cross-spectra and six CORDIC phases per bin",
     CTRL,
     [("s_axis", "512"), ("cal0..cal3", "4 x 32"), ("frameSamples/frameTag", "16 + 16")],
     [("calibrate four channels", "Q2.14 complex gain"),
      ("six cross-spectra", "complex products of channel pairs"),
      ("one shared CORDIC", "16 iterations, time-multiplexed over six phases"),
      ("Q3.13 phase out", "<= 2 LSB error"),
      ("frame result", "16 x 64-bit words plus a 128-bit phase word")],
     [("m_axis", "64 x 16"), ("m_phase", "128")],
     ["packaged and csim/csynth checked, but its net, clock and address are undecided",
      "V07_PHASE_INTERFEROMETRY.md section 7.5 says what it needs; attaching it is G4 work",
      "one CORDIC instead of six: the phase rate is one frame per 4096 samples"]),

    ("clocking", "doa_clk_wiz_125m + doa_rst_125m",
     "the 125 MHz DOA clock and its reset, derived from clkRFdiv2",
     PS,
     [("clkRFdiv2", "250 MHz"), ("reset from the PS", "peripheral reset")],
     [("MMCM", "250 MHz -> 125 MHz, phase aligned"),
      ("BUFG fan-out", "one clock per region"),
      ("proc_sys_reset", "synchronous release to the 125 MHz domain")],
     [("clk_doa_125m", "125 MHz"), ("reset_doa_125m_n", "active low")],
     ["the 125 MHz domain exists so the DOA logic has two cycles per RF beat",
      "both the CDCs and the dwidth converters are reset from here"]),

    ("fifo_cov", "doa_cov_dwc + doa_cov_fifo",
     "64-bit results narrowed to 32 bit, buffered, and read by the PS",
     PS,
     [("S_AXIS", "64")],
     [("axis_dwidth_converter", "64 -> 32 bit, beats split"),
      ("axi_fifo_mm_s (RX only)", "depth 512 x 32 bit"),
      ("S_AXI slave", "occupancy, reset, data read")],
     [("S_AXI", "32")],
     ["the buffer absorbs one frame burst while the PS is busy with the previous frame",
      "depth 512 = 16 words per frame x 32 frames of slack"]),

    ("fifo_beam", "doa_beam_dwc + doa_beam_fifo",
     "the same path for the diagnostic beam stream",
     PS,
     [("S_AXIS", "256")],
     [("axis_dwidth_converter", "256 -> 32 bit"),
      ("axi_fifo_mm_s (RX only)", "depth 2048 x 32 bit"),
      ("S_AXI slave", "occupancy, reset, data read")],
     [("S_AXI", "32")],
     ["deeper than the covariance FIFO because beam packets are longer (64 beats default)",
      "the diagnostic stream must never be able to stall the DOA path"]),

    ("control_ic", "control_interconnect  -  smartconnect 1.0",
     "one AXI4-Lite master from the PS, six 32-bit slaves",
     CTRL,
     [("S00_AXI", "128")],
     [("clock and reset", "clk_doa_125m domain"),
      ("address decode", "six 4 KB windows"),
      ("width conversion", "128 -> 32 bit per slave"),
      ("arbitration", "round robin, no QoS")],
     [("M00..M05", "6 x 32")],
     ["slaves: doa_cov_fifo, doa_beam_fifo, bridge, covariance, candidate_peak, beam_monitor",
      "phase_interf_4ch is not a seventh slave: it has no address yet"]),

    ("rpu", "RPU  -  Cortex-R5F, bare metal",
     "step3_r5_doa and step4_r5_amc in C99 (libm, no allocation); step5 is the python ladder",
     PS,
     [("covariance frame", "16 x 64 bit from the FIFO"),
      ("candidate bins", "192-bit records via the bridge"),
      ("control", "AXI4-Lite writes")],
     [("frame intake", "reads the FIFO, aligns frames"),
      ("DOA estimate", "u_yz = -(B^T W B)^-1 B^T phi / k, ladder rung selection"),
      ("AMC", "features -> modulation label, same code as the model"),
      ("tracking", "births, retirements, ghost and malformed accounting"),
      ("telemetry", "results to a static buffer for the RPMsg loop")],
     [("angle + label + track", "per frame"), ("deadline", "one AMC frame on the R5F")],
     ["G7a and G8a are closed on the host with this code; G8b needs Embedded Coder",
      "G8c is the deadline measurement, which needs the board",
      "firmware/amc_r5 holds the C that goes into the RPU build"]),

    ("rpu_doa", "RPU: the DOA rung ladder",
     "cheapest rung first, and the reason for each rung",
     PS,
     [("R (4x4 Hermitian)", "16 x 64 bit"), ("prior frame", "track state")],
     [("rung 1: coarse WPI", "all-pairs phases, unweighted"),
      ("rung 2: weighted WPI", "per-pair weights from SNR and bandwidth"),
      ("rung 3: Gauss-Newton", "refine from the WPI seed"),
      ("score C = sum w_r (d_r/sigma_r)^2", "sigma: direction 0.5 deg, bandwidth 0.35"),
      ("decoy handling", "independent decoy vs repeater, cepstrum ripple for the latter")],
     [("azimuth, elevation", "per detected source"), ("confidence", "C and rung used")],
     ["module penalty 9 keeps a heavier rung from winning on a tie",
      "a repeater is rank 1 in every bin, so no per-bin estimator separates it",
      "step3_r5_doa/c is the implementation; step3_r5_doa/py is the reference"]),

    ("rpu_amc", "RPU: AMC (automatic modulation classification)",
     "features to label, on the same code the model was validated with",
     PS,
     [("burst samples", "selected bin, calibrated"), ("vectors", "build/amc/amc_vectors.bin")],
     [("feature extraction", "amc_features.m ported to C"),
      ("classifier", "amc_model.h parameters, fixed point"),
      ("label + confidence", "per burst"),
      ("verification hook", "same vectors as the MATLAB model")],
     [("label", "per burst"), ("agreement", "100.0% of 120 bursts")],
     ["G8a: make amc-port, double and single build agree with the model on all 120 bursts",
      "accuracy against the true class is 72.5% in the firmware and 72.5% in the model",
      "G8b builds it for the RPU with Embedded Coder, which is not installed here"]),

    ("rpu_tracking", "RPU: tracking",
     "tracks across frames, with ghosts and malformed frames accounted for",
     PS,
     [("detections", "angle + label per frame"), ("frame id", "sequence")],
     [("association", "gate on predicted angle"),
      ("track update", "smoothed state per track"),
      ("lifecycle", "birth, retire, ghost flag"),
      ("frame accounting", "malformed frames counted, never silently dropped")],
     [("tracks", "live set"), ("counters", "born, retired, ghosts, malformed")],
     ["the A53 supervisor prints frames=7 cells=15 tracks_live=2 born=3 retired=1",
      "ghosts=1 malformed=0 on the fixture; T6.2 requires both ladders to agree (3 tracks)"]),

    ("apu", "APU  -  Cortex-A53, Linux  (step6_ps_linux)",
     "the supervisor: cells to tracks to telemetry, plus the four jobs the A53 keeps",
     PS,
     [("cells (JSONL)", "stdin, straight from the R5 telemetry"),
      ("fixture", "fixture_cells.jsonl, 15 cells/7 frames")],
     [("ladder", "mod -> direction -> bandwidth -> cadence, as in step5"),
      ("association and retirement", "retire after N empty frames"),
      ("policy", "which rungs and gates run (--policy direction-only)"),
      ("telemetry", "one JSON object per cell and per retirement, JSONL on stdout")],
     [("track events", "JSONL"), ("summary line", "frames/cells/born/retired/ghosts on stderr")],
     ["the A53 does four jobs and no maths: calibration manager, policy, telemetry, watchdog",
      "T6.1..T6.5 compare it with step5_r5_tracking on the same fixture; both give 3 tracks",
      "cross-built with the PetaLinux SDK to build/step6/supervisor_aarch64; not yet run on an A53"]),

    ("host", "HOST  -  every measurement that needs no board",
     "eight step benches, the gates they close, and the build that packages the design",
     HOST,
     [("python3 + numpy", "no licence"), ("optional MATLAB", "R2024a / R2022b")],
     [("step0 physics", "geometry, estimators, spacing rule -> G0"),
      ("step1 contract", "RFDC, MTS, 512-bit at 7.8125 ns"),
      ("step2 kernels", "fixed-point references of the PL blocks -> G1a"),
      ("step3/4/5 R5 models", "DOA, AMC, tracking -> G7a, G8a"),
      ("step6 fixtures", "capture format the APU writes"),
      ("step7 checklist", "the eleven commands that need the board")],
     [("green gates", "G0, G1a-c, G7a, G8a"), ("evidence", "docs/evidence/")],
     ["`make steps` runs all eight: 8/8 PASS, no vendor tools required",
      "the host also owns the build: make pipeline drives HLS, Vivado and MATLAB",
      "every number in this guide that is not from a Vivado report came from here"]),

    ("mts_base", "Stage V03  -  the MTS base project",
     "AMD's ZCU208 RFSoC-MTS tree, adapted for the 2023.2 lock",
     HOST,
     [("upstream/RFSoC-MTS", "pinned SHA"), ("patches", "two recorded substitutions")],
     [("fetch", "make rebuild STEP=step01_fetch_references FETCH_SET=RFSoC-MTS"),
      ("copy to build/mts_base_src_2023p2", "prepare_mts_2023p2_patch.sh"),
      ("patch 1", "zynq_ultra_ps_e 3.4 -> 3.5 for the 2023.2 catalog"),
      ("patch 2", "impl_1 strategy -> Performance_ExtraTimingOpt"),
      ("vivado -source mts.tcl", "creates mts/mts.xpr")],
     [("mts.xpr", "BASE_XPR"), ("mts BD", "BASE_BD")],
     ["no stepNN_ target builds it; step00 checks it and step07 opens it",
      "`make mts-base` does all of it and refuses to wipe an existing build",
      "prepare_mts_2023p2_patch.sh rm -rf's its destination, hence that guard"]),

    ("ip_flow", "IP packaging and collection  -  steps 02..06",
     "eight packaged IPs (seven custom + one MATLAB) into one repository with pinned VLNVs",
     HOST,
     [("ip/custom/*", "5 HLS kernels + 2 RTL"), ("ip/matlab/channelizer_hdl", "HDL Coder")],
     [("csim", "each kernel proves its own arithmetic"),
      ("csynth", "4.000 ns, out-of-context numbers"),
      ("export_design -format ip_catalog", "component.xml with the pinned VLNV"),
      ("collect_ip.sh", "checks every VLNV, writes ip_manifest.tsv"),
      ("BD ip_repo_paths", "step07 appends, never overwrites")],
     [("build/ip_repo", "one repository"), ("ip_manifest.tsv", "the flat list")],
     ["a stale component.xml fails at step06, with the directory and expected value named",
      "doa_create_pinned_ip means the BD cannot instantiate an unpinned version",
      "config/ip_versions.tcl is the single source of truth for every VLNV"]),
]


def short(text, width):
    """Port details sit in a fixed box: cut them rather than let them run outside."""
    return textwrap.shorten(str(text), width=width, placeholder="...")


def detail(stem, title, subtitle, colour, inputs, stages, outputs, notes, out_dir):
    wrapped_notes = []
    for note in notes:
        wrapped_notes.extend(textwrap.wrap(note, 112) or [""])

    stage_h = 0.62
    stage_gap = 0.26
    chain_h = len(stages) * (stage_h + stage_gap)
    side_h = max(len(inputs), len(outputs)) * 0.62
    notes_h = len(wrapped_notes) * 0.21 + 0.30
    body_h = max(chain_h, side_h) + notes_h + 0.85
    top = body_h + 1.45

    fig, ax = plt.subplots(figsize=(12.4, top * 0.60))
    ax.set_xlim(0, 12.4)
    ax.set_ylim(0, top)
    ax.axis("off")

    ax.text(0.20, top - 0.16, title, fontsize=10.2, fontweight="bold", va="top", color=colour)
    ax.text(0.20, top - 0.52, subtitle, fontsize=6.8, va="top", color="#444444", style="italic")

    frame_bottom = 0.30
    frame_top = top - 1.20
    ax.add_patch(patches.FancyBboxPatch(
        (0.15, frame_bottom), 12.1, frame_top - frame_bottom,
        boxstyle="round,pad=0.03,rounding_size=0.12",
        linewidth=1.3, edgecolor=colour, facecolor="#fcfcfe", zorder=1))

    # ---- inputs (left column)
    y = frame_top - 0.62
    ax.text(0.35, frame_top - 0.16, "inputs", fontsize=6.2, color=colour, fontweight="bold")
    for name, detail_text in inputs:
        ax.add_patch(patches.FancyBboxPatch(
            (0.35, y - 0.26), 2.25, 0.50, boxstyle="round,pad=0.02,rounding_size=0.05",
            linewidth=1.0, edgecolor=colour, facecolor="white", zorder=3))
        ax.text(0.44, y + 0.07, name, fontsize=6.2, family="monospace", va="center", zorder=4)
        ax.text(0.44, y - 0.14, short(detail_text, 38), fontsize=5.2, color="#666666", va="center",
                family="monospace", zorder=4)
        y -= 0.62

    # ---- internal stages (middle column)
    ax.text(3.10, frame_top - 0.16, "inside", fontsize=6.2, color=colour, fontweight="bold")
    y = frame_top - 0.62
    boxes = []
    for index, (name, detail_text) in enumerate(stages):
        ax.add_patch(patches.FancyBboxPatch(
            (2.95, y - stage_h + 0.20), 4.40, stage_h,
            boxstyle="round,pad=0.02,rounding_size=0.06",
            linewidth=1.2, edgecolor=colour, facecolor="#ffffff", zorder=3))
        ax.text(3.06, y - 0.04, "%d. %s" % (index + 1, name), fontsize=6.4,
                fontweight="bold", va="center", color="#222222", zorder=4)
        wrapped = textwrap.fill(short(detail_text, 132), 70)
        if "\n" in wrapped:
            ax.text(3.06, y - 0.13, wrapped, fontsize=5.2, color="#555555",
                    va="top", family="monospace", zorder=4)
        else:
            ax.text(3.06, y - 0.29, wrapped, fontsize=5.4, color="#555555",
                    va="center", family="monospace", zorder=4)
        boxes.append((y - stage_h + 0.20, y + 0.20))
        y -= stage_h + stage_gap
    for index in range(len(boxes) - 1):
        ax.annotate("", xy=(5.15, boxes[index + 1][1] + 0.02),
                    xytext=(5.15, boxes[index][0] - 0.02),
                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=1.3, mutation_scale=9))
    if boxes:
        ax.annotate("", xy=(2.93, (boxes[0][0] + boxes[0][1]) / 2),
                    xytext=(2.64, (boxes[0][0] + boxes[0][1]) / 2),
                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=1.2, mutation_scale=8))

    # ---- outputs (right column)
    y = frame_top - 0.62
    ax.text(7.90, frame_top - 0.16, "outputs", fontsize=6.2, color=colour, fontweight="bold")
    for name, detail_text in outputs:
        ax.add_patch(patches.FancyBboxPatch(
            (7.85, y - 0.26), 2.75, 0.50, boxstyle="round,pad=0.02,rounding_size=0.05",
            linewidth=1.0, edgecolor=colour, facecolor="white", zorder=3))
        ax.text(7.94, y + 0.07, name, fontsize=6.2, family="monospace", va="center", zorder=4)
        ax.text(7.94, y - 0.14, short(detail_text, 47), fontsize=5.2, color="#666666", va="center",
                family="monospace", zorder=4)
        y -= 0.62
    if boxes:
        last = boxes[-1]
        ax.annotate("", xy=(7.83, (last[0] + last[1]) / 2),
                    xytext=(7.37, (last[0] + last[1]) / 2),
                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=1.2, mutation_scale=8))

    # ---- notes, placed under whichever column is taller
    chain_bottom = boxes[-1][0] if boxes else frame_top - 0.6
    notes_y = min(chain_bottom, frame_top - 0.62 - max(len(inputs), len(outputs)) * 0.62) - 0.66
    ax.text(0.35, notes_y + 0.18, "notes", fontsize=6.2, color=colour, fontweight="bold")
    ax.text(0.35, notes_y, "\n".join("- " + line for line in wrapped_notes),
            fontsize=5.6, va="top", color="#333333", family="monospace", linespacing=1.5)

    os.makedirs(out_dir, exist_ok=True)
    png = os.path.join(out_dir, stem + ".png")
    svg = os.path.join(out_dir, stem + ".svg")
    fig.savefig(png, dpi=170, bbox_inches="tight", facecolor="white")
    fig.savefig(svg, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    return png


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--only", default=None, help="render one stem")
    args = parser.parse_args()
    count = 0
    for entry in BLOCKS:
        if args.only and entry[0] != args.only:
            continue
        detail(*entry, out_dir=args.out)
        count += 1
    print("%d block diagram(s) under %s" % (count, os.path.relpath(args.out, ROOT)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
