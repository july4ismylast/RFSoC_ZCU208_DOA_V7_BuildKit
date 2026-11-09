#!/usr/bin/env python3
"""One internal block diagram per block: what is inside it, function by function.

    docs/diagrams/blocks/<stem>.png   (and .svg)

Twenty-three pictures: every PL block, the clocking, the control interconnect, the RPU
(whole, DOA estimator, AMC, tracking), the APU supervisor, the host benches, the Vivado
base and the IP packaging flow.  Each picture carries the block's inputs, its internal
stages *with the function, module or file that implements each stage*, its outputs, and
the notes that would otherwise only exist in a README.

Nothing here invents structure.  Every code reference below is a name that exists in this
repository:

  ip/custom/*/src/*.cpp, *.hpp          HLS kernels: top function, static helpers, pragmas
  ip/custom/doa_subband_bridge_4ch/rtl  the bridge: functions, FSMs, registers
  ip/matlab/channelizer_hdl             the channelizer wrapper and the generated DUT
  config/zcu208_bd_map.tcl              BD wiring, RFDC config, interconnects, FIFO depths
  config.mk                             the rate and clock numbers
  step3_r5_doa/c, firmware/amc_r5       the R5F code: doa_core.c, amc.c
  step5_r5_tracking/py, step6_ps_linux  the ladder, twice: python and C++
  step0..step7                          the host benches

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
#
# inputs / outputs : (port name, "width, clock, or where it comes from")
# stages           : (block name, "function / module / file", "what it does")
BLOCKS = [
    ("rfdc", "usp_rf_data_converter_1  (RF Data Converter, owned by the MTS base)",
     "4 ADC channels at 4.000 GSPS, fine R2C mixer, decimation 2, 8 samples/beat at 250 MHz",
     PL,
     [("ADC0..ADC3", "4.000 GSPS, direct clock, LMX2594_4000"),
      ("clk_pl", "500 MHz, CONFIG.PL_Clock_Freq"),
      ("s_axi", "32, config from the BD")],
     [("fine mixer R2C", "CONFIG.Mixer_Type=2, NCO=-3.000 GHz", "zone-2 3 GHz band to baseband"),
      ("decimate by 2", "CONFIG.Decimation_Mode=2", "4.000 GSPS real -> 2.000 GSPS complex"),
      ("fabric format", "CONFIG.Data_Width=8, Fabric_Freq=250.000", "8 complex samples per 128-bit word"),
      ("MTS alignment", "CONFIG.ADC0..1_Multi_Tile_Sync=1", "SYSREF and NCO phase shared by all tiles"),
      ("fabric clocking", "m*_axis_aclk = clk_rf_250m", "every output stream runs at 250 MHz")],
     [("m00_axis .. m13_axis", "8 x 128, I and Q of 4 antennas"), ("adc sample clock", "4.000 GHz")],
     ["set up by config/zcu208_bd_map.tcl (V04 + V07), not by the upstream MTS defaults",
      "upstream MTS ships real output, decimation 1; the DOA map switches on I/Q and decimation 2",
      "8 samples x 250 MHz = 2.000 GSPS complex: every later width in this design assumes that"]),

    ("rfdc_repack4", "doa_rfdc_repack_0  -  rfdc_repack4 1.0",
     "the gearbox: eight 128-bit RFDC streams -> four 256-bit complex SSR-8 streams",
     PL,
     [("s_axis_ch0_i .. ch3_q", "8 x 128, 250 MHz, from the RFDC")],
     [("read eight beats", "s_axis_ch*.read(), rfdc_repack4()", "one I beat and one Q beat per antenna"),
      ("pair I and Q", "static pack_iq_ssr8()", "{Q[31:16], I[15:0]} per complex sample"),
      ("interleave 8 samples", "pack_lane: #pragma HLS UNROLL", "sample s of the beat = s-th oldest sample"),
      ("four writers", "m_axis_ch0..ch3.write()", "beat n in, beat n out: no rate change"),
      ("no state, no control", "#pragma HLS PIPELINE II=1, ap_ctrl_none", "pure wiring once the packing is right")],
     [("m_axis_ch0 .. ch3", "4 x 256, 250 MHz")],
     ["csim must be bit-exact before csynth runs (tb/rfdc_repack4_tb.cpp)",
      "AMD's axis_combiner concatenates beats and leaves the consumer to un-interleave; this does not",
      "beat order is preserved; MTS aligns samples across tiles before this block"]),

    ("matlab_channelizer", "doa_channelizer_0..3  -  matlab_channelizer 7.0",
     "channelizer_axis_wrapper.sv around Channelizer_DUT.v from HDL Coder (1024 bands, SSR-8)",
     PL,
     [("s_axis", "256: 8 complex sfix16 lanes"),
      ("aclk / aresetn", "250 MHz, from the DOA hierarchy"),
      ("m_axis_tready", "back-pressure from the bridge")],
     [("lane unpack", "g_pack_lanes: s_axis_tdata[32*lane +: 16]", "core_re_in/core_im_in, 8 lanes"),
      ("Channelizer_DUT", "hdl_prj/hdlsrc_transposed/Channelizer_DUT.v", "HDL Coder subsystem, 228 files"),
      ("ChannelizerCore", "dsphdl.Channelizer, transposed direct form", "1024 bands, 12 taps/band, 12288 coefficients"),
      ("no TREADY on the core", "core_clk_enable = m_axis_tready", "a stall holds all internal state"),
      ("snapshot framing", "output_beat_in_snapshot == LAST_BEAT_IN_SNAPSHOT", "TLAST on every 128th beat"),
      ("lane pack", "m_axis_tdata[52*lane +: 26]", "8 x sfix26_En24 -> one 416-bit beat")],
     [("m_axis", "416, sfix26_En24"), ("m_axis_tlast", "one per 1024-bin snapshot")],
     ["built by HDL Coder: make step05_channelizer; the DUT is a Simulink subsystem, not a leaf System block",
      "latency 351 cycles transposed vs 1760 systolic; systolic rejected: 93.2 % CLB LUTs for four",
      "Gates 0T..4C passed on the user PC, 4C bit-exact against the MATLAB fixed-point golden"]),

    ("subband_bridge", "doa_subband_bridge_0  -  doa_subband_bridge_4ch 1.0",
     "hand-written RTL: lockstep ingest, quantiser, snapshot store, serialiser, packers, registers",
     PL,
     [("s_axis_ch0..3", "4 x 416, sfix26_En24, 250 MHz"),
      ("s_axis_candidate", "192, from doa_cdc_candidate"),
      ("s_axi_ctrl", "32, M12 of control_interconnect")],
     [("always-ready sinks", "assign s_axis_ch*_tready = aresetn", "the four channelizers must run lockstep"),
      ("quantise", "function quantize_s26_to_s16", "half-up, saturating, SCALE_SHIFT=9 to sfix16_En15"),
      ("stage 1 alignment", "q_lo512/q_hi512, in_beat_idx, q_valid", "one coherent 4-channel beat, registered"),
      ("search FSM", "SRCH_IDLE / SRCH_CAPTURE, 256 beats", "bins 0..1023 in natural order, TLAST at the end"),
      ("snapshot packer", "snap_pack_reg, snap_lane_cnt", "active_bin locked for 4096 samples, 4 snapshots/beat"),
      ("beam packetiser", "reg_beam_beats, default 64", "TLAST closes each beam packet"),
      ("register file", "aw_holding / w_holding, 0x00..0x3C", "control, telemetry, capture and beam drop counts")],
     [("m_axis_search", "512"), ("m_axis_capture", "512"), ("m_axis_beam", "512"),
      ("mon_ch0..3", "4 x 128, legacy monitor")],
     ["the only block that knows everybody's timing; tready is tied high on purpose",
      "registers: 0x00 CTRL, 0x04 MANUAL_BIN, 0x08 SCALE_SHIFT, 0x0C CAPTURE_BEATS, 0x10 BEAM_PACKET_BEATS",
      "0x14 STATUS, 0x18 LAST_CANDIDATE, 0x1C/0x20 peak, 0x24/0x28 average, 0x2C..0x34 counters, 0x38/0x3C counts",
      "its SystemVerilog test bench (tb/tb_doa_subband_bridge_4ch.sv) is the golden check for the register map"]),

    ("cdc_forward", "doa_cdc_search / _capture / _beam  -  axis_clock_converter 1.1",
     "three 512-bit AXI4-Stream crossings, 250 MHz -> 125 MHz",
     PL,
     [("S_AXIS", "512 x3, from the bridge at 250 MHz"),
      ("s_axis_aclk / m_axis_aclk", "clk_rf_250m / clk_doa_125m")],
     [("write side", "CONFIG.IS_ACLK_ASYNC=1, s_axis_aclk", "pointer lives in the 250 MHz domain"),
      ("asynchronous FIFO", "axis_clock_converter, one per stream", "grey-coded pointers, no combinational path"),
      ("read side", "m_axis_aclk = clk_doa_125m", "drained by spectrum/covariance/beam logic"),
      ("packet integrity", "TDATA + TVALID/TREADY/TLAST", "TLAST crosses the same boundary as the payload")],
     [("M_AXIS", "512 x3 at 125 MHz")],
     ["one converter per stream: sharing would couple search traffic to capture latency",
      "capture is what produces the covariance frame, so it gets its own crossing",
      "the three instances are wired in config/zcu208_bd_map.tcl section 6"]),

    ("cdc_candidate", "doa_cdc_candidate  -  axis_clock_converter 1.1",
     "192-bit crossing in the other direction: 125 MHz -> 250 MHz",
     DOA,
     [("S_AXIS", "192, from candidate_peak at 125 MHz"),
      ("s_axis_aclk / m_axis_aclk", "clk_doa_125m / clk_rf_250m")],
     [("write side", "s_axis_aclk = clk_doa_125m", "the record is built in the DOA domain"),
      ("asynchronous FIFO", "axis_clock_converter, IS_ACLK_ASYNC=1", "bin index, validity, peak, average together"),
      ("read side", "m_axis_aclk = clk_rf_250m", "consumed by the bridge's candidate sink"),
      ("latch", "pending_auto_bin, has_auto_bin", "the bridge keeps the bin; it never reads a live wire")],
     [("M_AXIS -> active_bin", "192 at 250 MHz, latched")],
     ["this is the only loop that closes across the two clock domains",
      "it is why STATUS[9:0] can be read at any time: active_bin is a register, not a path",
      "STATUS[17] has_auto_bin and STATUS[16] last_cand_valid say whether the loop has produced anything"]),

    ("spectrum_power", "spectrum_power  -  spectrum_power4 2.0",
     "spectrum_power4(): four lanes of incoherent power, II=1, no control port",
     DOA,
     [("s_axis", "512: 4 lanes x 4 channels, sfix16 complex")],
     [("beat read", "spectrum_power4(), s_axis.read()", "one 512-bit beat per clock"),
      ("lane_loop", "for lane 0..3, #pragma HLS UNROLL", "four independent ap_uint<64> power sums"),
      ("channel_loop", "I*I + Q*Q into ap_uint<33>", "four complex channels per lane"),
      ("pack", "output.data.range(64*lane+63, 64*lane)", "four 64-bit powers in a 256-bit beat"),
      ("frame boundary", "output.last = input.last", "TLAST copied through untouched")],
     [("m_axis", "256")],
     ["#pragma HLS INTERFACE ap_ctrl_none: free-running, one beat per clock, no ap_start",
      "register_mode=both on both ports: the 512-bit input is registered before fan-out",
      "this is the detector statistic, not the covariance; confusing the two misreads the design"]),

    ("candidate_peak", "candidate_peak  -  candidate_peak4 1.0",
     "candidate_peak4(): per-frame maximum vs the frame average, one record at TLAST",
     DOA,
     [("s_axis", "256: 4 x 64-bit powers, from spectrum_power"),
      ("thresholdQ8_8", "16, s_axilite; 512 = 2.0x")],
     [("static frame state", "frameSum, framePeak, peakBin, binBase", "carried in registers, no BRAM"),
      ("lane_loop", "nextSum += power; if (power > nextPeak)", "peak index = binBase + lane"),
      ("at TLAST: average", "average = nextSum / (binBase + 4)", "integer divide, once per frame"),
      ("at TLAST: compare", "valid = (nextPeak<<8) > average*thresholdQ8_8", "Q8.8 threshold, one comparator"),
      ("record builder", "bin[15:0] valid[16] peak[95:32] avg[159:96]", "the 192-bit candidate record")],
     [("m_axis", "192, one beat per frame")],
     ["ap_ctrl_none: it must not stall a single-beat path; only thresholdQ8_8 is AXI-Lite",
      "deliberately not CA-CFAR: a cheap reason to capture or not, nothing more",
      "its record is what becomes active_bin at the bridge, through doa_cdc_candidate"]),

    ("covariance", "covariance  -  doa_covariance_4ch_v4 7.1",
     "doa_covariance_4ch_v4(): the upper triangle of R = X X^H, triggered by the PS",
     DOA,
     [("s_axis", "512: 4 lanes x 4 channels per beat"),
      ("cal0..3", "4 x 32 s_axilite, Q2.14 complex gain"),
      ("frameSamples", "16 s_axilite, 0 means 4096"),
      ("ap_start / ap_done", "s_axilite port=return (ap_ctrl_hs)")],
     [("calibrate()", "static, #pragma HLS INLINE", "complex Q2.14 gain, >>14, ap_int<20> out"),
      ("beat_loop", "for beat < (samples+3)/4, PIPELINE II=1", "1024 beats of 4 samples for 4096"),
      ("lane_loop / channel_loop", "UNROLL 4 x 4", "16 calibrated samples per beat"),
      ("accumulate", "power[4], crossReal[6], crossImag[6], ap_int<64>", "Re and Im kept apart; worst case 51 bits"),
      ("output_loop", "16 x 64-bit, TLAST at index 15", "powers, then cross Re, then cross Im")],
     [("m_axis", "64, 16 beats per frame")],
     ["ap_ctrl_hs is deliberate: the PS starts a frame, so a capture and an integration cannot drift apart",
      "it needs the bridge's m_axis_capture in front of it: it is a frame processor, not a stream processor",
      "csim must match all 16 words exactly before synthesis is allowed (tb/doa_covariance_4ch_v4_tb.cpp)"]),

    ("beam_monitor", "beam_monitor  -  beam_weight_4ch 2.1",
     "beam_weight_4ch(): apply four Q1.15 complex weights, so a steering error is visible",
     DOA,
     [("s_axis", "512: 4 lanes x 4 channels"),
      ("w0..w3", "4 x 32 s_axilite, Q1.15 complex weights")],
     [("weight array", "weights[4], ARRAY_PARTITION complete", "one complex weight per antenna, in registers"),
      ("lane_loop / channel_loop", "UNROLL, ap_int<40> accumulators", "y = sum w* x, real and imag"),
      ("normalise", ">>15 back to sfix16_En15", "Q1.15 weights keep the gain"),
      ("frame boundary", "output.last = input.last", "packet timing preserved")],
     [("m_axis", "256")],
     ["ap_ctrl_none since 2.1: v2.0 used s_axilite port=return and stalled in the BD",
      "nothing downstream depends on it and it does not estimate DOA",
      "its job is to make a calibration or steering error measurable in hardware"]),

    ("phase_interf", "phase_interf_4ch 1.0  (packaged, NOT attached)",
     "phase_interf_4ch() + phase_interf_core.hpp: six cross-spectra, one shared CORDIC",
     CTRL,
     [("s_axis", "512"),
      ("cal0..3", "4 x 32, Q2.14 (CalCoefficient)"),
      ("frameSamples / frameTag", "16 + 16")],
     [("calibrate()", "phase_interf_core.hpp, CalCoefficient", "same Q2.14 gain as the covariance kernel"),
      ("six cross-spectra", "pair table 01 02 03 12 13 23", "complex products of channel pairs"),
      ("atan2_q13()", "kAtanQ30[32] table, 16 iterations", "one CORDIC, time-multiplexed over six phases"),
      ("Q3.13 phase", "ap_int<16> per pair, LSB 1.22e-4 rad", "phase of each baseline"),
      ("frame result", "16 x 64-bit + m_phase[128]", "closes every frameSamples samples")],
     [("m_axis", "64 x 16 beats"), ("m_phase", "128, six phases packed")],
     ["packaged and csim/csynth checked, but its net, clock and address are undecided",
      "V07_PHASE_INTERFEROMETRY.md section 7.5 lists exactly what attaching it needs; that is G4 work",
      "one CORDIC instead of six: the phase rate is one frame per 4096 samples"]),

    ("clocking", "clocktreeMTS/clkRFdiv2  ->  doa_clk_wiz_125m + doa_rst_125m",
     "the 125 MHz DOA clock and its reset, derived from the MTS divider",
     PS,
     [("clkRFdiv2", "250 MHz, clocktreeMTS (not the RFDC pin)"),
      ("clkRF", "500 MHz, the RFDC fabric clock"),
      ("pl_resetn0", "from zynq_ultra_ps_e_0")],
     [("source select", "clk_rf_250m, config/zcu208_bd_map.tcl:227", "the MTS divider, already MTS-aligned"),
      ("doa_clk_wiz_125m", "clk_wiz, CLKOUT1_REQUESTED_OUT_FREQ", "DOA_CLOCK_HZ = 125.000 MHz"),
      ("BUFG fan-out", "one clock per region", "one 125 MHz net for the whole /doa_v7 hierarchy"),
      ("doa_rst_125m", "proc_sys_reset, pl_resetn0", "synchronous release, active-low output")],
     [("clk_doa_125m", "125 MHz"), ("reset_doa_125m_n", "active low")],
     ["the 125 MHz domain gives the DOA logic two cycles per RF beat; the RFDC side stays at 250 MHz",
      "the three CDCs and the two dwidth converters are all reset from here: one reset, no strays",
      "the MTS clock tree is the authority: re-deriving 125 MHz from the RFDC would break MTS alignment"]),

    ("fifo_cov", "doa_cov_dwc + doa_cov_fifo",
     "64-bit results narrowed to 32 bit, buffered, read by the PS at M10",
     PS,
     [("S_AXIS", "64, from covariance m_axis")],
     [("doa_cov_dwc", "axis_dwidth_converter, M_TDATA_NUM_BYTES=4", "64 -> 32 bit, beats split"),
      ("doa_cov_fifo", "axi_fifo_mm_s, C_RX_FIFO_DEPTH=512", "RX only, 512 x 32 bit, no TX"),
      ("S_AXI @ M10", "control_interconnect M10_AXI", "occupancy, reset, data register"),
      ("clocking", "clk_doa_125m / rst_doa_125m_n", "the same domain as the producer")],
     [("S_AXI", "32, to the PS")],
     ["depth 512 = 16 words per frame x 32 frames of slack for a busy PS",
      "RX-only on purpose: nothing here ever writes back into the DOA path",
      "wired in config/zcu208_bd_map.tcl section 7, the widest IP settings quoted there"]),

    ("fifo_beam", "doa_beam_dwc + doa_beam_fifo",
     "the same path for the diagnostic beam stream, four times deeper",
     PS,
     [("S_AXIS", "256, from beam_monitor m_axis")],
     [("doa_beam_dwc", "axis_dwidth_converter, M_TDATA_NUM_BYTES=4", "256 -> 32 bit, beats split"),
      ("doa_beam_fifo", "axi_fifo_mm_s, C_RX_FIFO_DEPTH=2048", "RX only, 2048 x 32 bit"),
      ("S_AXI @ M11", "control_interconnect M11_AXI", "occupancy, reset, data register"),
      ("clocking", "clk_doa_125m / rst_doa_125m_n", "the same domain as beam_monitor")],
     [("S_AXI", "32, to the PS")],
     ["deeper because beam packets are longer: 64 beats per TLAST by default",
      "the diagnostic stream must never be able to stall the DOA path",
      "same tcl section as the covariance FIFO, only the depth differs (2048 vs 512)"]),

    ("control_ic", "control_interconnect  -  smartconnect 1.0",
     "one AXI4-Lite master from the PS; the MTS base takes M00..M06, the DOA design M07..M12",
     CTRL,
     [("S00_AXI", "128, from zynq_ultra_ps_e_0"),
      ("aclk / aresetn", "clk_doa_125m, except the bridge")],
     [("port count", "CONFIG.NUM_MI = 13", "set by the DOA map, M00..M06 stay with the base"),
      ("M07 S_AXI_COV_CTRL", "covariance (125 MHz)", "cal0..3, frameSamples, ap_start/done"),
      ("M08 S_AXI_CANDIDATE_CTRL", "candidate_peak (125 MHz)", "thresholdQ8_8"),
      ("M09 S_AXI_BEAM_CTRL", "beam_monitor (125 MHz)", "w0..w3"),
      ("M10 / M11", "doa_cov_fifo, doa_beam_fifo", "FIFO control and data registers"),
      ("M12 s_axi_ctrl", "doa_subband_bridge_0 (250 MHz)", "the only slave in the RF clock domain")],
     [("M07..M12", "6 x 32 to the DOA slaves")],
     ["the bridge port is re-clocked to clk_rf_250m and reset by rst_rf_250m_n: see the tcl rewire",
      "phase_interf_4ch is not a seventh DOA slave: it has no address until G4 attaches it",
      "NUM_MI=13 is asserted by the map script; a different number fails the run, not the silicon"]),

    ("rpu", "RPU  -  Cortex-R5F, bare metal",
     "doa_core.c and amc.c in C99 (libm, no allocation); the ladder twice: python and C++",
     PS,
     [("covariance frame", "16 x 64 bit, from doa_cov_fifo"),
      ("host cells", "az, el, bw, mod: from the A53 or the bench"),
      ("control", "AXI4-Lite writes")],
     [("frame intake", "step3_r5_doa/c/doa_core.h", "R as 4x4 complex double, frame aligned"),
      ("DOA estimate", "doa_estimate()", "WPI seed -> local ML -> Gauss-Newton"),
      ("AMC", "amc_run() in firmware/amc_r5/amc.c", "six features -> nearest class mean"),
      ("association", "associate() / Store.update()", "the step5 ladder, the same in C++ in step6"),
      ("telemetry", "static buffers, no malloc", "one record per frame for the RPMsg loop")],
     [("angle + label", "per frame"), ("track set", "ids, votes, verified flag")],
     ["G7a and G8a are closed on the host with exactly this code",
      "G8b needs Embedded Coder, G8c needs the board: both are open, and neither is a code gap",
      "nothing allocates, which is what lets it drop into an RPMsg loop with a static buffer"]),

    ("rpu_doa", "RPU: doa_core.c, the estimator from R to an angle",
     "doa_wpi() sets up, doa_bartlett() searches, Gauss-Newton refines, angles() reports",
     PS,
     [("r_re / r_im", "16 doubles: 4x4 Hermitian R"),
      ("fc_hz, dy_m, dz_m", "carrier and the array baseline"),
      ("gn_iterations", "int, usually 3")],
     [("positions()", "static, y-z plane", "p[4][2] from dy, dz: the geometry"),
      ("doa_wpi()", "6 pairs, weight = c/(1-c), clip 0.05..100", "weighted least squares, the seed"),
      ("solve2()", "-(B^T W B)^-1 B^T phi / k", "2x2 solve, then clamp |u| <= 0.999999"),
      ("doa_bartlett()", "4 stages of 3x3: 0.5/0.1/0.02/0.005 deg", "36 ML evaluations, az +-55, el +-45"),
      ("dominant_vector()", "4 power iterations of R", "the projector seed for Newton"),
      ("Gauss-Newton", "gn_iterations, analytic grad and Hessian", "refine on the same Bartlett cost"),
      ("angles()", "u_yz -> az, el", "the two numbers every later stage speaks")],
     [("out_az_el[2]", "degrees"), ("return", "0 = solved, 1 = singular")],
     ["the 'rungs' live in step5, not here: this file is one estimator with three stages",
      "the decoy question is answered later, by two_arrivals() on the raw burst",
      "step3_r5_doa/py is the reference and step3_r5_doa/testbench compares them"]),

    ("rpu_amc", "RPU: AMC, the same classifier in MATLAB and in C",
     "amc_features.m -> classify_modulation.m -> amc_export.py -> amc.c -> amc_port_check.py",
     PS,
     [("burst samples", "1024 complex, 4 samples/symbol"),
      ("amc_model.h", "class means and scales, the shared tables")],
     [("amc_features.m", "matlab_v7/", "|C40|, C42, sigma_ap, gamma_max, freq_std, spike"),
      ("classify_modulation.m", "matlab_v7/, Embedded Coder target", "nearest class mean + margin"),
      ("amc_export.py", "writes amc_model.h + amc_model_params.m", "the same tables both ways"),
      ("amc_features()", "firmware/amc_r5/amc.c, fft_complex()", "1024-point FFT, 1024 atan2, 4 sqrt"),
      ("amc_classify()", "amc.c, 6-D standardised space", "label plus margin"),
      ("amc_port_check.py", "double and single builds, 120 bursts", "G8a: 100.0 % label agreement")],
     [("label", "5 classes"), ("margin", "float")],
     ["accuracy 72.5 % through the firmware, the single build and the model: they cannot disagree",
      "build_tables() and fft_complex() are the only non-obvious code; both are static and allocation-free",
      "G8b (Embedded Coder output for the R5) and G8c (cycles) are open"]),

    ("rpu_tracking", "RPU: the association ladder and the track store",
     "step5_r5_tracking/py/ladder.py: four rungs, a cost, greedy association, a decoy check",
     PS,
     [("cells", "az, el, bw_hz, mod, frame per detection"),
      ("tracks", "the store carried across frames")],
     [("rung 1 modulation", "rung_residuals(): 0.0 or 9.0", "a different label is a different emitter"),
      ("rung 2 direction", "hypot(daz, del) / 0.5", "sigma 0.5 deg, gate 1.5"),
      ("rung 3 bandwidth", "|log(bw/bw)| / 0.35", "separates emitters at the same direction"),
      ("rung 4 cadence", "max(0, gap-1) / 1.5", "hoppers, gate 1.2"),
      ("cost() and associate()", "C = sum w_r d_r^2, greedy sort", "weights 1/1/1/0.5 over measured rungs"),
      ("Store.update()", "_absorb(), retire after 3 frames", "birth, label vote, verification, retire"),
      ("two_arrivals()", "autocorrelation peak, 10..300 ns", "a repeater is one waveform arriving twice")],
     [("report", "alive, born, retired per frame"), ("tracks", "cells, votes, verified, arrivals")],
     ["the residual for a wrong label is 9.0, not a penalty term: it is one rung's distance",
      "two_arrivals() is also exported as verification_index, the name the GUIDE uses",
      "step6_ps_linux/c/supervisor.cpp is the same ladder in C++, and T6.2 makes them agree"]),

    ("apu", "APU  -  Cortex-A53, Linux  (step6_ps_linux)",
     "supervisor.cpp: cells in as JSONL, tracks out as JSONL, a summary line for the watchdog",
     PS,
     [("cells (JSONL)", "stdin, one object per detection"),
      ("fixture_cells.jsonl", "15 cells over 7 frames"),
      ("policy", "--policy direction-only | full")],
     [("parse_cell()", "supervisor.cpp, read_double/read_string", "frame, az, el, bw_hz, mod"),
      ("passes()", "same four rungs as ladder.py", "gate per rung, skip what is not measurable"),
      ("absorb()", "update the track, vote the label", "smoothed az/el, vote counts"),
      ("retirement", "retire after N empty frames", "a legal empty frame still advances the clock"),
      ("telemetry", "one JSON object per cell and per retirement", "stdout, JSONL"),
      ("summary", "frames=/cells=/born=/retired=/ghosts=/malformed=", "stderr, what a watchdog parses")],
     [("track events", "JSONL on stdout"), ("summary line", "stderr, exit code 0")],
     ["T6.1..T6.5 compare it with step5_r5_tracking on the same fixture: both build 3 tracks",
      "the A53 does four jobs and no maths: calibration manager, policy, telemetry, watchdog",
      "cross target build/step6/supervisor_aarch64 exists; nothing has run on an A53 yet"]),

    ("host", "HOST  -  every measurement that needs no board",
     "the eight step benches, the code each one runs, and the gate it closes",
     HOST,
     [("python3 + numpy", "no licence needed"),
      ("optional MATLAB", "R2024a for HDL Coder and the models")],
     [("step0 -> G0", "step0_antenna/py/array_model.py, make_scenes.py", "geometry, estimators, spacing rule"),
      ("step1 -> contract", "step1_rfadc_mts/py/capture_format.py", "512-bit beats at 7.8125 ns"),
      ("step2 -> G1a/G1c", "ip/custom/*/tb/*.cpp, step2_pl_ip/kernels.tsv", "fixed-point reference of every kernel"),
      ("step3/4/5 -> G7a/G8a", "doa_core.c, amc.c, ladder.py", "the R5 algorithms, on the host"),
      ("step6 -> T6.1..5", "step6_ps_linux/testbench/run_testbench.py", "the A53 twin of the ladder"),
      ("step7 -> the board", "step7_board_bringup/checklist.sh", "eleven commands that need silicon")],
     [("green gates", "G0, G1a-c, G7a, G8a, T6.x, amc-port"), ("evidence", "docs/evidence/")],
     ["make steps runs all eight benches: 8/8 PASS, no vendor tools required",
      "the host also owns the build: make pipeline drives HLS, Vivado and MATLAB",
      "every number in this guide that is not from a Vivado report came from here"]),

    ("mts_base", "Stage V03  -  the MTS base project",
     "scripts/build_mts_base.sh: fetch, copy, patch, open; never wipes a built base",
     HOST,
     [("upstream/RFSoC-MTS", "pinned SHA"),
      ("patches", "two recorded substitutions")],
     [("wrapper", "scripts/build_mts_base.sh (make mts-base)", "refuses to rebuild unless MTS_BASE_FORCE=1"),
      ("fetch", "make rebuild STEP=step01_fetch_references", "FETCH_SET=RFSoC-MTS, pinned"),
      ("copy", "prepare_mts_2023p2_patch.sh", "build/mts_base_src_2023p2, rm -rf'd by the script itself"),
      ("patch 1", "zynq_ultra_ps_e 3.4 -> 3.5", "the 2023.2 catalog has 3.5"),
      ("patch 2", "impl_1 -> Performance_ExtraTimingOpt", "the only implementation strategy"),
      ("open", "vivado -source mts.tcl", "creates mts/mts.xpr, the BASE_XPR")],
     [("mts.xpr", "BASE_XPR"), ("mts BD", "BASE_BD, the BD every later stage edits")],
     ["no stepNN_ target builds it: step00 checks it, step07 opens it",
      "the guard exists because prepare_mts_2023p2_patch.sh removes its destination first",
      "config/zcu208_bd_map.tcl then edits this BD; it never re-creates it"]),

    ("ip_flow", "IP packaging and collection  -  steps 02..06",
     "eight packaged IPs (six HLS kernels, the RTL bridge, the MATLAB channelizer) with pinned VLNVs",
     HOST,
     [("ip/custom/*/src", "6 HLS kernels"),
      ("rfdc_repack4 + bridge", "2 hand-written RTL blocks in ip/custom"),
      ("ip/matlab/channelizer_hdl", "HDL Coder output")],
     [("csim", "csim_design, inside build_hls.tcl", "each kernel proves its own arithmetic first"),
      ("csynth", "vitis_hls, 7.8125 ns or 4.0 ns by kernel", "the numbers quoted in Part 2"),
      ("export_design", "-format ip_catalog, component.xml", "the pinned VLNV from config/ip_versions.tcl"),
      ("collect_ip.sh", "build/ip_repo + ip_manifest.tsv", "one repository, one flat list"),
      ("check_ip_component.py", "VLNV and port check per IP", "a stale component.xml fails here, by name"),
      ("doa_create_pinned_ip", "config/zcu208_bd_map.tcl", "the BD cannot instantiate another version")],
     [("build/ip_repo", "one IP repository"), ("ip_manifest.tsv", "what is in it")],
     ["config/ip_versions.tcl is the single source of truth: no wildcard VLNVs anywhere",
      "step06 checks the manifest before step07 opens the BD: a missing IP is named, not guessed at",
      "the bridge and the channelizer are packaged by their own tcl, not by Vitis HLS"]),
]


# What is inside a stage that is itself a block: (stem, stage number) -> sub-blocks.
# Facts only, each traceable to the source named in the stage line above it.
INSIDE = {
    ("matlab_channelizer", 2): [
        "atomic subsystem: ChannelizerCore is its only MATLAB System block",
        "u_FilterBank + u_FFT are the two generated children",
        "228 generated files, one per pipeline register group",
    ],
    ("matlab_channelizer", 3): [
        "FilterBank: 12 288 coefficients (1024 bands x 12 taps), 16 subFilters x 12 DSPs",
        "FFT: 25 102 LUTs, 43 571 FFs, 120 DSPs; 351 cycles end to end",
        "transposed: 10 800 LUTs + 176 RAMB36 (systolic: 63 439 LUTs, 57 670 SRLs)",
    ],
    ("subband_bridge", 3): [
        "4 channels x 8 subbands quantised per beat, then registered",
        "q_lo512 / q_hi512 hold the two halves of one 4-channel snapshot beat",
        "in_beat_idx counts 0..127: one snapshot = 1024 bins",
    ],
    ("subband_bridge", 4): [
        "4 bins x 4 channels per 512-bit beat: 16 words of 32 bit",
        "srch_state[2:0] is readable in STATUS[26:24] at any time",
    ],
    ("subband_bridge", 5): [
        "extract active_bin[9:0] from all four channels, once per snapshot",
        "pack 4 consecutive snapshots per 512-bit beat",
        "active_bin locked for CAPTURE_BEATS=1024 beats = 4096 snapshots",
    ],
    ("subband_bridge", 7): [
        "0x00 CTRL, 0x04 MANUAL_BIN, 0x08 SCALE_SHIFT, 0x0C/0x10 beats",
        "0x14 STATUS, 0x18 LAST_CANDIDATE, 0x1C..0x28 peak and average",
        "0x2C..0x38 frame and candidate counters, 0x3C drop counts",
    ],
    ("cdc_forward", 2): [
        "write pointer in the 250 MHz domain, read pointer in the 125 MHz one",
        "grey-coded pointers, two flip-flops per bit across the boundary",
        "TLAST crosses with TDATA, so a frame cannot be cut in half",
    ],
    ("cdc_candidate", 2): [
        "written at 125 MHz, read at 250 MHz: the mirror image",
        "bin[15:0], valid[16], peak[95:32], average[159:96] as one record",
        "the bridge consumes it into pending_auto_bin / has_auto_bin",
    ],
    ("candidate_peak", 3): [
        "binCount = binBase + 4 after the last beat of the frame",
        "average = nextSum / binCount, integer division",
        "frameSum, framePeak, peakBin, binBase all cleared for the next frame",
    ],
    ("candidate_peak", 5): [
        "bin[15:0], valid[16]",
        "peak[95:32] and average[159:96], 64 bit each",
        "keep and strb all ones, TLAST set: one beat per frame",
    ],
    ("covariance", 4): [
        "power[c] += |x_c|^2 for the four channels",
        "crossReal[pair], crossImag[pair] for 01 02 03 12 13 23",
        "ap_int<40> products into ap_int<64> accumulators",
    ],
    ("covariance", 5): [
        "index 0..3 powers, 4..9 cross real, 10..15 cross imaginary",
        "TLAST on index 15: exactly one burst per integration frame",
    ],
    ("phase_interf", 3): [
        "16 CORDIC iterations, vectoring mode, one instance only",
        "kAtanQ30[32] table, Q2.30 angle accumulated then rounded to Q3.13",
        "six phases time-multiplexed: 1 pair per beat-group, no sixfold area",
    ],
    ("clocking", 2): [
        "MMCM: 250 MHz in, 125 MHz out, phase aligned",
        "CLKOUT1 only, integer divide, no fractional setting",
        "doa_clk_wiz_125m is a pinned part of the DOA hierarchy",
    ],
    ("fifo_cov", 2): [
        "RX FIFO 512 x 32 bit, no TX interface at all",
        "C_USE_TX_DATA=0, C_USE_TX_CTRL=0, C_USE_RX_DATA=1",
        "S_AXI exposes RRD/RDF, RLR, ISR/IER and the reset",
    ],
    ("fifo_beam", 2): [
        "identical IP, only C_RX_FIFO_DEPTH differs: 2048 x 32 bit",
        "RX only, so the diagnostic path can never write back",
        "S_AXI at M11 of control_interconnect",
    ],
    ("control_ic", 1): [
        "one 128-bit master, thirteen mirrored slaves",
        "M00..M06 belong to the MTS base and are left alone",
        "M07..M12 are the DOA design: three kernels, two FIFOs, the bridge",
    ],
    ("rpu", 2): [
        "doa_wpi(): weighted least squares seed from six baselines",
        "doa_bartlett(): 4 stages of 3x3, 36 ML evaluations",
        "Gauss-Newton: gn_iterations steps with analytic gradient/Hessian",
    ],
    ("rpu_doa", 2): [
        "coherence weight c/(1-c) per baseline, clipped to 0.05..100",
        "phase[pair] = atan2(crossImag, crossReal)",
        "2x2 normal equations (B^T W B) over the six baselines",
    ],
    ("rpu_doa", 6): [
        "gradient 2*Re(conj(d) . (P a)) for the az and el basis",
        "Hessian 2*Re(conj(d_i) . (P d_j)), 2x2",
        "step solved from the same 2x2 helper, applied, then re-steered",
    ],
    ("rpu_amc", 1): [
        "|C40| fourth-order cumulant: the BPSK/QPSK discriminator",
        "C42 = mean|x|^4 / power^2, sigma_ap = amplitude variation",
        "gamma_max and freq_std from fft_complex(), spike for a carrier",
    ],
    ("rpu_amc", 4): [
        "build_tables() once: twiddles, class scales",
        "fft_complex(): 1024-point, in place, static buffers (16 kB + 4 kB)",
        "1024 atan2 and 4 sqrt per burst, no allocation anywhere",
    ],
    ("rpu_tracking", 5): [
        "passes(): every measurable rung must be inside its gate",
        "cost(): C = sum w_r d_r^2 over the rungs that were measured",
        "greedy: sort by cost, then by how many rungs were measurable",
    ],
    ("matlab_channelizer", 5): [
        "one snapshot = 128 accepted beats = 1024 bins x 8 lanes",
        "TLAST on the beat whose index is 127, then the counter wraps",
        "counters are per channel: four wrappers, four TLASTs, one per antenna",
    ],
    ("subband_bridge", 6): [
        "TLAST every BEAM_PACKET_BEATS beats (default 64 = 256 snapshots)",
        "drop count increments if the downstream FIFO is ever not ready",
        "beam_drop_count is the low half of 0x3C, readable from the PS",
    ],
    ("candidate_peak", 1): [
        "frameSum: ap_uint<80>, four 64-bit powers per beat for 1024 beats",
        "framePeak: ap_uint<64>, peakBin: ap_uint<16>, binBase: ap_uint<16>",
        "no BRAM and no ping-pong: the frame is one pass, the record is written at TLAST",
    ],
    ("rpu_doa", 4): [
        "36 evaluations per estimate, each a 4x4 quadratic form",
        "az clamped to +-55 deg, el to +-45 deg after every stage",
    ],
    ("rpu_doa", 5): [
        "v = R v, normalised, four times: 4x4 complex matrix-vector per step",
        "seeded with the steering vector of the Bartlett solution",
        "gives the projector P = I - v v^H the Newton step needs",
    ],
    ("rpu_tracking", 6): [
        "a cell with no track passes the gates creates a new track (birth)",
        "absorb() appends the cell, updates az/el and votes for the label",
        "a track with no cell for RETIRE_FRAMES=3 frames is retired, ghosts included",
    ],
    ("host", 4): [
        "doa_core.c is the R5F estimator, compiled on the host for G7a",
        "amc.c is the exported classifier, checked by amc_port_check.py for G8a",
        "ladder.py is the association and the decoy check, reused by step6 as the referee",
    ],
    ("mts_base", 5): [
        "the MTS BD ships impl_1 set to a default strategy",
        "the patch pins Performance_ExtraTimingOpt so every run is comparable",
        "any other strategy silently changes the WNS in the final report",
    ],
    ("ip_flow", 4): [
        "one directory per IP under build/ip_repo, never a merged blob",
        "each VLNV is compared with config/ip_versions.tcl before it is listed",
        "ip_manifest.tsv is what step06 and step07 read",
    ],
    ("rfdc", 1): [
        "NCO_Freq = -RF_CENTER = -3.000 GHz (PG269 absolute-NCO convention)",
        "Nyquist=1 selects zone 2; the 2-4 GHz band lands at baseband",
        "from here on the samples are complex: one I stream and one Q stream",
    ],
    ("rfdc", 2): [
        "decimating filter inside the tile (PG269), CalOpt_Mode=1",
        "4.000 GSPS real -> 2.000 GSPS complex per channel",
        "Decimation_Mode=2 is set by the DOA map, not by upstream MTS",
    ],
    ("rfdc", 3): [
        "each 128-bit word carries 8 samples of 16 bit",
        "two streams per channel: m00/m01 = I/Q of ADC0, and so on",
        "8 samples x 250 MHz = 2.000 GSPS: the rate every width assumes",
    ],
    ("rfdc", 4): [
        "SYSREF reaches all four tiles from clocktreeMTS",
        "NCO phase and decimator state reset together on every SYSREF",
        "mts_all_true() is asserted post-validate or the map script aborts",
    ],
    ("rfdc_repack4", 2): [
        "sample s of the input beat becomes sample s of the output beat",
        "{Q[31:16], I[15:0]} is the project-wide complex packing",
        "8 samples per 256-bit output beat, order never permuted",
    ],
    ("spectrum_power", 3): [
        "16 multipliers: 4 lanes x 4 channels, all unrolled",
        "I*I + Q*Q in ap_int<32>, widened to ap_uint<33> per channel",
        "four channels summed into one ap_uint<64> per lane",
    ],
    ("beam_monitor", 2): [
        "4 lanes x 4 channels unrolled into 16 complex multiplies",
        "real = sum(xr*wr - xi*wi), imag = sum(xr*wi + xi*wr)",
        "ap_int<40> accumulator, >>15 after the loop, then saturate",
    ],
    ("host", 1): [
        "array_model.py: geometry, steering vectors, R = X X^H / K",
        "make_scenes.py: the 0/5/10/20 dB scenarios and the decoy scene",
        "closes G0: 5.996 GHz at 25 mm, 4.997 GHz at 30 mm",
    ],
    ("host", 3): [
        "kernels.tsv: one row per kernel, VLNV and rate",
        "tb/*.cpp: the golden vectors every csim replays",
        "closes G1a (fixed point) and G1c (VLNV contract)",
    ],
    ("mts_base", 3): [
        "removes the destination, then copies the pinned tree",
        "the two patches are applied in place afterwards",
        "build_mts_base.sh refuses this path unless MTS_BASE_FORCE=1",
    ],
    ("ip_flow", 1): [
        "csim_design inside build_hls.tcl, against tb/ vectors",
        "a failing csim stops the flow before any packaging",
        "the bridge uses its SystemVerilog bench instead of C simulation",
    ],
    ("apu", 3): [
        "smoothed az/el per track, label vote counts",
        "verified flag and arrivals count carried on the track",
        "an empty frame is legal and still advances the clock",
    ],
}


# Stages whose inside is a chain of named sub-blocks: drawn as boxes, left to right.
CHIPS = {
    ("matlab_channelizer", 3): [
        ("u_FilterBank", "16 subFilters, 12 taps"),
        ("u_FFT", "1024-point, 120 DSPs"),
    ],
    ("subband_bridge", 4): [
        ("SRCH_IDLE", "wait for 128 beats"),
        ("SRCH_CAPTURE", "dual 128 x 512 BRAM"),
        ("serialiser", "256 beats, TLAST 255"),
    ],
    ("rpu_doa", 4): [
        ("stage 1", "0.5 deg, 3x3"),
        ("stage 2-3", "0.1 / 0.02 deg"),
        ("stage 4", "0.005 deg"),
    ],
}


def short(text, width):
    """Port details sit in a fixed box: cut them rather than let them run outside."""
    return textwrap.shorten(str(text), width=width, placeholder="...")


def detail(stem, title, subtitle, colour, inputs, stages, outputs, notes, out_dir):
    wrapped_notes = []
    for note in notes:
        wrapped_notes.extend(textwrap.wrap(note, 118) or [""])

    rich = any(len(stage) > 2 for stage in stages)
    stage_h = 0.86 if rich else 0.60
    stage_gap = 0.20
    sub_h = [0.27 * len(INSIDE.get((stem, index + 1), []))
             + (0.62 if CHIPS.get((stem, index + 1)) else 0.0) for index in range(len(stages))]
    chain_h = sum(0.92 + sub_h[index] + stage_gap for index in range(len(stages))) \
        if rich else len(stages) * (stage_h + stage_gap)
    side_h = max(len(inputs), len(outputs)) * 0.68
    notes_text_h = len(wrapped_notes) * 0.21
    top = 3.24 + max(chain_h, side_h) + notes_text_h

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

    # ---- inputs, left column
    y = frame_top - 0.66
    ax.text(0.35, frame_top - 0.16, "inputs", fontsize=6.2, color=colour, fontweight="bold")
    for name, detail_text in inputs:
        ax.add_patch(patches.FancyBboxPatch(
            (0.35, y - 0.34), 2.35, 0.64, boxstyle="round,pad=0.02,rounding_size=0.05",
            linewidth=1.0, edgecolor=colour, facecolor="white", zorder=3))
        ax.text(0.44, y - 0.02, short(name, 36), fontsize=6.0, family="monospace", va="center", zorder=4)
        ax.text(0.44, y - 0.23, short(detail_text, 42), fontsize=5.0, color="#666666",
                va="center", family="monospace", zorder=4)
        y -= 0.68

    # ---- internal stages, middle column
    ax.text(3.10, frame_top - 0.16, "inside  (stage -> the code that does it)", fontsize=6.2,
            color=colour, fontweight="bold")
    y = frame_top - 0.66
    boxes = []
    for index, stage in enumerate(stages):
        name = stage[0]
        code = stage[1] if len(stage) > 2 else None
        desc = stage[2] if len(stage) > 2 else stage[1]
        subs = INSIDE.get((stem, index + 1), [])
        chip = CHIPS.get((stem, index + 1), [])
        extra = 0.27 * len(subs) + (0.62 if chip else 0.0)
        height = (0.92 if rich else 0.60) + extra
        box_top = y
        box_bottom = y - height
        ax.add_patch(patches.FancyBboxPatch(
            (2.95, box_bottom), 5.00, height, boxstyle="round,pad=0.02,rounding_size=0.06",
            linewidth=1.2, edgecolor=colour, facecolor="#ffffff", zorder=3))
        ax.text(3.06, box_top - 0.17, "%d. %s" % (index + 1, name), fontsize=6.3,
                fontweight="bold", va="center", color="#222222", zorder=4)
        if code is None:
            ax.text(3.06, box_top - 0.40, short(desc, 92), fontsize=5.2, color="#555555",
                    va="center", family="monospace", zorder=4)
        else:
            ax.text(3.06, box_top - 0.40, short(code, 96), fontsize=4.9, color=colour,
                    va="center", family="monospace", zorder=4)
            ax.text(3.06, box_top - 0.65, short(desc, 96), fontsize=4.9, color="#555555",
                    va="center", family="monospace", zorder=4)
        if subs or chip:
            panel_top = box_top - 0.78
            ax.add_patch(patches.FancyBboxPatch(
                (3.02, box_bottom + 0.10), 4.86, panel_top - box_bottom - 0.10,
                boxstyle="round,pad=0.01,rounding_size=0.04", linewidth=0.7,
                edgecolor=colour, facecolor="#f3f3f6", zorder=4))
            text_top = panel_top - 0.10
            if chip:
                width = (4.70 - 0.30 * (len(chip) - 1)) / len(chip)
                for chip_index, (chip_name, chip_sub) in enumerate(chip):
                    chip_x = 3.10 + chip_index * (width + 0.30)
                    ax.add_patch(patches.FancyBboxPatch(
                        (chip_x, panel_top - 0.62), width, 0.44,
                        boxstyle="round,pad=0.01,rounding_size=0.04", linewidth=0.8,
                        edgecolor=colour, facecolor="white", zorder=5))
                    ax.text(chip_x + 0.06, panel_top - 0.34, short(chip_name, 26), fontsize=5.2,
                            fontweight="bold", family="monospace", va="center", zorder=6)
                    ax.text(chip_x + 0.06, panel_top - 0.52, short(chip_sub, 30), fontsize=4.5,
                            color="#555555", family="monospace", va="center", zorder=6)
                    if chip_index < len(chip) - 1:
                        ax.annotate("", xy=(chip_x + width + 0.27, panel_top - 0.40),
                                    xytext=(chip_x + width + 0.04, panel_top - 0.40),
                                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=0.9,
                                                    mutation_scale=7), zorder=6)
                text_top = panel_top - 0.72
            for sub_index, sub in enumerate(subs):
                ax.text(3.10, text_top - sub_index * 0.27, "- " + short(sub, 82),
                        fontsize=4.7, color="#3b3b3b", va="top", family="monospace", zorder=5)
        boxes.append((box_bottom, box_top))
        y -= height + stage_gap

    for index in range(len(boxes) - 1):
        ax.annotate("", xy=(5.45, boxes[index + 1][1] + 0.015),
                    xytext=(5.45, boxes[index][0] - 0.015),
                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=1.2, mutation_scale=8))
    if boxes:
        first_mid = (boxes[0][0] + boxes[0][1]) / 2
        ax.annotate("", xy=(2.93, first_mid), xytext=(2.74, first_mid),
                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=1.2, mutation_scale=8))
        last_mid = (boxes[-1][0] + boxes[-1][1]) / 2
        ax.annotate("", xy=(8.28, last_mid), xytext=(7.99, last_mid),
                    arrowprops=dict(arrowstyle="-|>", color=colour, lw=1.2, mutation_scale=8))

    # ---- outputs, right column
    y = frame_top - 0.66
    ax.text(8.35, frame_top - 0.16, "outputs", fontsize=6.2, color=colour, fontweight="bold")
    for name, detail_text in outputs:
        ax.add_patch(patches.FancyBboxPatch(
            (8.30, y - 0.34), 3.85, 0.64, boxstyle="round,pad=0.02,rounding_size=0.05",
            linewidth=1.0, edgecolor=colour, facecolor="white", zorder=3))
        ax.text(8.40, y - 0.02, short(name, 58), fontsize=6.0, family="monospace", va="center", zorder=4)
        ax.text(8.40, y - 0.23, short(detail_text, 66), fontsize=5.0, color="#666666",
                va="center", family="monospace", zorder=4)
        y -= 0.68

    # ---- notes, under whichever column is taller
    chain_bottom = boxes[-1][0] if boxes else frame_top - 0.7
    side_bottom = frame_top - 0.66 - max(len(inputs), len(outputs)) * 0.68
    notes_y = min(chain_bottom, side_bottom) - 0.58
    ax.text(0.35, notes_y, "notes", fontsize=6.2, color=colour, fontweight="bold", va="top")
    ax.text(0.35, notes_y - 0.26, "\n".join("- " + line for line in wrapped_notes),
            fontsize=5.5, va="top", color="#333333", family="monospace", linespacing=1.5)

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
