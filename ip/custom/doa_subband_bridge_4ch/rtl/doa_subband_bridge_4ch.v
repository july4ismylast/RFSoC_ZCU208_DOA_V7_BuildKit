`timescale 1ns / 1ps
// =============================================================================
// Module: doa_subband_bridge_4ch
// VLNV:   openai:doa:doa_subband_bridge_4ch:1.0
//
// Purpose:
//   Single-clock (250 MHz clkRFdiv2) deterministic bridge between the four
//   single-channel transposed SSR-8 channelizers (openai:doa:matlab_channelizer:7.0,
//   416-bit m_axis = 8 lanes x {Q sfix26_En24, I sfix26_En24}, 128 beats/frame)
//   and the three 512-bit four-lane x four-channel AXI4-Stream inputs of /doa_v7:
//     - m_axis_search  -> S_AXIS_SEARCH       (1024 bins = 256 beats/frame)
//     - m_axis_capture -> S_AXIS_DOA_CAPTURE  (4 snapshots/beat on active_bin)
//     - m_axis_beam    -> S_AXIS_BEAM_MONITOR (4 snapshots/beat on active_bin)
//
//   Also terminates /doa_v7/M_AXIS_CANDIDATE (192-bit) for closed-loop hardware
//   peak-bin tracking (with AXI4-Lite manual override and telemetry) and drives
//   four non-blocking 128-bit monitor/tie-off streams for the legacy MTS
//   capture hierarchies (/hier_adc0..2_cap and /deepCapture).
// =============================================================================

module doa_subband_bridge_4ch (
    input  wire         aclk,
    input  wire         aresetn,

    // 4x SSR-8 channelizer slave streams (52 bytes = 416 bits each)
    input  wire [415:0] s_axis_ch0_tdata,
    input  wire         s_axis_ch0_tvalid,
    output wire         s_axis_ch0_tready,
    input  wire         s_axis_ch0_tlast,

    input  wire [415:0] s_axis_ch1_tdata,
    input  wire         s_axis_ch1_tvalid,
    output wire         s_axis_ch1_tready,
    input  wire         s_axis_ch1_tlast,

    input  wire [415:0] s_axis_ch2_tdata,
    input  wire         s_axis_ch2_tvalid,
    output wire         s_axis_ch2_tready,
    input  wire         s_axis_ch2_tlast,

    input  wire [415:0] s_axis_ch3_tdata,
    input  wire         s_axis_ch3_tvalid,
    output wire         s_axis_ch3_tready,
    input  wire         s_axis_ch3_tlast,

    // Candidate peak feedback stream from /doa_v7/M_AXIS_CANDIDATE (24 bytes = 192 bits)
    input  wire [191:0] s_axis_candidate_tdata,
    input  wire [23:0]  s_axis_candidate_tkeep,
    input  wire [23:0]  s_axis_candidate_tstrb,
    input  wire         s_axis_candidate_tlast,
    input  wire         s_axis_candidate_tvalid,
    output wire         s_axis_candidate_tready,

    // Search spectrum master stream -> S_AXIS_SEARCH (64 bytes = 512 bits)
    output reg  [511:0] m_axis_search_tdata,
    output wire [63:0]  m_axis_search_tkeep,
    output wire [63:0]  m_axis_search_tstrb,
    output reg          m_axis_search_tlast,
    output reg          m_axis_search_tvalid,
    input  wire         m_axis_search_tready,

    // Selected-bin covariance capture master stream -> S_AXIS_DOA_CAPTURE (512 bits)
    output reg  [511:0] m_axis_capture_tdata,
    output wire [63:0]  m_axis_capture_tkeep,
    output wire [63:0]  m_axis_capture_tstrb,
    output reg          m_axis_capture_tlast,
    output reg          m_axis_capture_tvalid,
    input  wire         m_axis_capture_tready,

    // Selected-bin beamformer monitor master stream -> S_AXIS_BEAM_MONITOR (512 bits)
    output reg  [511:0] m_axis_beam_tdata,
    output wire [63:0]  m_axis_beam_tkeep,
    output wire [63:0]  m_axis_beam_tstrb,
    output reg          m_axis_beam_tlast,
    output reg          m_axis_beam_tvalid,
    input  wire         m_axis_beam_tready,

    // Legacy MTS capture hierarchy tie-off / optional subband monitor streams (128 bits)
    output reg  [127:0] m_axis_mon_ch0_tdata,
    output reg          m_axis_mon_ch0_tvalid,
    input  wire         m_axis_mon_ch0_tready,

    output reg  [127:0] m_axis_mon_ch1_tdata,
    output reg          m_axis_mon_ch1_tvalid,
    input  wire         m_axis_mon_ch1_tready,

    output reg  [127:0] m_axis_mon_ch2_tdata,
    output reg          m_axis_mon_ch2_tvalid,
    input  wire         m_axis_mon_ch2_tready,

    output reg  [127:0] m_axis_mon_ch3_tdata,
    output reg          m_axis_mon_ch3_tvalid,
    input  wire         m_axis_mon_ch3_tready,

    // AXI4-Lite control/status interface
    input  wire [7:0]   s_axi_ctrl_awaddr,
    input  wire [2:0]   s_axi_ctrl_awprot,
    input  wire         s_axi_ctrl_awvalid,
    output wire         s_axi_ctrl_awready,
    input  wire [31:0]  s_axi_ctrl_wdata,
    input  wire [3:0]   s_axi_ctrl_wstrb,
    input  wire         s_axi_ctrl_wvalid,
    output wire         s_axi_ctrl_wready,
    output wire [1:0]   s_axi_ctrl_bresp,
    output reg          s_axi_ctrl_bvalid,
    input  wire         s_axi_ctrl_bready,
    input  wire [7:0]   s_axi_ctrl_araddr,
    input  wire [2:0]   s_axi_ctrl_arprot,
    input  wire         s_axi_ctrl_arvalid,
    output wire         s_axi_ctrl_arready,
    output reg  [31:0]  s_axi_ctrl_rdata,
    output wire [1:0]   s_axi_ctrl_rresp,
    output reg          s_axi_ctrl_rvalid,
    input  wire         s_axi_ctrl_rready
);

    // -------------------------------------------------------------------------
    // Always-ready upstream channelizer and candidate feedback sinks:
    // rfdc_repack4 + 4x matlab_channelizer must run lockstep without stall.
    // -------------------------------------------------------------------------
    assign s_axis_ch0_tready       = aresetn;
    assign s_axis_ch1_tready       = aresetn;
    assign s_axis_ch2_tready       = aresetn;
    assign s_axis_ch3_tready       = aresetn;
    assign s_axis_candidate_tready = aresetn;

    assign m_axis_search_tkeep     = 64'hFFFF_FFFF_FFFF_FFFF;
    assign m_axis_search_tstrb     = 64'hFFFF_FFFF_FFFF_FFFF;
    assign m_axis_capture_tkeep    = 64'hFFFF_FFFF_FFFF_FFFF;
    assign m_axis_capture_tstrb    = 64'hFFFF_FFFF_FFFF_FFFF;
    assign m_axis_beam_tkeep       = 64'hFFFF_FFFF_FFFF_FFFF;
    assign m_axis_beam_tstrb       = 64'hFFFF_FFFF_FFFF_FFFF;

    assign s_axi_ctrl_bresp        = 2'b00;
    assign s_axi_ctrl_rresp        = 2'b00;

    // Suppress unused sideband lint warnings
    wire unused_ok = &{1'b0,
        s_axis_ch1_tlast, s_axis_ch2_tlast, s_axis_ch3_tlast,
        s_axis_candidate_tdata[191:160], s_axis_candidate_tdata[31:17],
        s_axis_candidate_tkeep, s_axis_candidate_tstrb, s_axis_candidate_tlast,
        s_axi_ctrl_awprot, s_axi_ctrl_arprot};

    // -------------------------------------------------------------------------
    // Signed sfix26_En24 -> sfix16_En15 quantizer with half-up rounding and
    // symmetric 16-bit saturation. Default shift=9 gives unity gain (2^-24 * 2^9 = 2^-15).
    // -------------------------------------------------------------------------
    function [15:0] quantize_s26_to_s16;
        input [25:0] raw_val;
        input [3:0]  shift;
        reg signed [27:0] ext_val;
        reg signed [27:0] round_bias;
        reg signed [27:0] rounded;
        reg signed [27:0] shifted;
        begin
            ext_val = {{2{raw_val[25]}}, raw_val};
            if (shift == 4'd0) begin
                round_bias = 28'sd0;
            end else begin
                round_bias = $signed(28'sd1 <<< (shift - 4'd1));
            end
            rounded = ext_val + round_bias;
            shifted = rounded >>> shift;
            if (shifted > 28'sd32767) begin
                quantize_s26_to_s16 = 16'h7FFF;
            end else if (shifted < -28'sd32768) begin
                quantize_s26_to_s16 = 16'h8000;
            end else begin
                quantize_s26_to_s16 = shifted[15:0];
            end
        end
    endfunction

    function [31:0] pack_iq32;
        input [51:0] lane52;
        input [3:0]  shift;
        reg [15:0] i16;
        reg [15:0] q16;
        begin
            i16 = quantize_s26_to_s16(lane52[25:0],  shift);
            q16 = quantize_s26_to_s16(lane52[51:26], shift);
            pack_iq32 = {q16, i16};
        end
    endfunction

    // -------------------------------------------------------------------------
    // Control and telemetry registers
    // -------------------------------------------------------------------------
    reg        ctrl_auto_bin_en;
    reg        ctrl_capture_en;
    reg        ctrl_search_en;
    reg        ctrl_beam_en;
    reg        ctrl_mon_en;
    reg [9:0]  reg_manual_bin;
    reg [3:0]  reg_scale_shift;
    reg [15:0] reg_capture_beats;
    reg [15:0] reg_beam_beats;

    reg [9:0]  pending_auto_bin;
    reg        has_auto_bin;
    reg [15:0] last_cand_bin;
    reg        last_cand_valid;
    reg [63:0] last_cand_peak;
    reg [63:0] last_cand_avg;
    reg [31:0] candidate_count;

    reg [9:0]  active_bin;
    reg [31:0] snapshot_count;
    reg [31:0] search_frame_count;
    reg [31:0] capture_frame_count;
    reg [15:0] capture_drop_count;
    reg [15:0] beam_drop_count;

    // AXI4-Lite independent AW/W channel latches
    reg        aw_holding;
    reg [7:0]  aw_addr_reg;
    reg        w_holding;
    reg [31:0] w_data_reg;
    reg [3:0]  w_strb_reg;

    assign s_axi_ctrl_awready = aresetn && !aw_holding && !s_axi_ctrl_bvalid;
    assign s_axi_ctrl_wready  = aresetn && !w_holding  && !s_axi_ctrl_bvalid;
    assign s_axi_ctrl_arready = aresetn && !s_axi_ctrl_rvalid;

    wire [9:0] desired_bin = (ctrl_auto_bin_en && has_auto_bin) ? pending_auto_bin : reg_manual_bin;

    // -------------------------------------------------------------------------
    // Stage 1: Coherent 4-channel beat alignment & registered s26->s16 quantizer
    // -------------------------------------------------------------------------
    wire all_ch_valid = aresetn &&
                        s_axis_ch0_tvalid && s_axis_ch1_tvalid &&
                        s_axis_ch2_tvalid && s_axis_ch3_tvalid;

    reg [6:0]   in_beat_idx;
    reg         q_valid;
    reg [6:0]   q_beat_idx;
    reg         q_last;
    reg [511:0] q_lo512;
    reg [511:0] q_hi512;
    reg [127:0] q_mon0;
    reg [127:0] q_mon1;
    reg [127:0] q_mon2;
    reg [127:0] q_mon3;

    // Combinational quantized words feeding the Stage-1 pipeline registers
    reg [511:0] comb_lo512;
    reg [511:0] comb_hi512;
    reg [127:0] comb_mon0;
    reg [127:0] comb_mon1;
    reg [127:0] comb_mon2;
    reg [127:0] comb_mon3;

    integer ln;
    always @(*) begin
        comb_lo512 = 512'd0;
        comb_hi512 = 512'd0;
        comb_mon0  = 128'd0;
        comb_mon1  = 128'd0;
        comb_mon2  = 128'd0;
        comb_mon3  = 128'd0;
        for (ln = 0; ln < 4; ln = ln + 1) begin
            comb_lo512[(ln*4 + 0)*32 +: 32] = pack_iq32(s_axis_ch0_tdata[ln*52 +: 52], reg_scale_shift);
            comb_lo512[(ln*4 + 1)*32 +: 32] = pack_iq32(s_axis_ch1_tdata[ln*52 +: 52], reg_scale_shift);
            comb_lo512[(ln*4 + 2)*32 +: 32] = pack_iq32(s_axis_ch2_tdata[ln*52 +: 52], reg_scale_shift);
            comb_lo512[(ln*4 + 3)*32 +: 32] = pack_iq32(s_axis_ch3_tdata[ln*52 +: 52], reg_scale_shift);

            comb_hi512[(ln*4 + 0)*32 +: 32] = pack_iq32(s_axis_ch0_tdata[(ln+4)*52 +: 52], reg_scale_shift);
            comb_hi512[(ln*4 + 1)*32 +: 32] = pack_iq32(s_axis_ch1_tdata[(ln+4)*52 +: 52], reg_scale_shift);
            comb_hi512[(ln*4 + 2)*32 +: 32] = pack_iq32(s_axis_ch2_tdata[(ln+4)*52 +: 52], reg_scale_shift);
            comb_hi512[(ln*4 + 3)*32 +: 32] = pack_iq32(s_axis_ch3_tdata[(ln+4)*52 +: 52], reg_scale_shift);
        end
        for (ln = 0; ln < 8; ln = ln + 1) begin
            comb_mon0[ln*16 +: 16] = quantize_s26_to_s16(s_axis_ch0_tdata[ln*52 +: 26], reg_scale_shift);
            comb_mon1[ln*16 +: 16] = quantize_s26_to_s16(s_axis_ch1_tdata[ln*52 +: 26], reg_scale_shift);
            comb_mon2[ln*16 +: 16] = quantize_s26_to_s16(s_axis_ch2_tdata[ln*52 +: 26], reg_scale_shift);
            comb_mon3[ln*16 +: 16] = quantize_s26_to_s16(s_axis_ch3_tdata[ln*52 +: 26], reg_scale_shift);
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            in_beat_idx    <= 7'd0;
            q_valid        <= 1'b0;
            q_beat_idx     <= 7'd0;
            q_last         <= 1'b0;
            q_lo512        <= 512'd0;
            q_hi512        <= 512'd0;
            q_mon0         <= 128'd0;
            q_mon1         <= 128'd0;
            q_mon2         <= 128'd0;
            q_mon3         <= 128'd0;
            snapshot_count <= 32'd0;
        end else begin
            q_valid <= all_ch_valid;
            if (all_ch_valid) begin
                q_beat_idx <= in_beat_idx;
                q_last     <= s_axis_ch0_tlast || (in_beat_idx == 7'd127);
                q_lo512    <= comb_lo512;
                q_hi512    <= comb_hi512;
                q_mon0     <= comb_mon0;
                q_mon1     <= comb_mon1;
                q_mon2     <= comb_mon2;
                q_mon3     <= comb_mon3;
                if (s_axis_ch0_tlast || (in_beat_idx == 7'd127)) begin
                    in_beat_idx    <= 7'd0;
                    snapshot_count <= snapshot_count + 32'd1;
                end else begin
                    in_beat_idx <= in_beat_idx + 7'd1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Search Snapshot Buffer & 256-Beat Serializer (m_axis_search)
    // Captures one coherent 128-beat snapshot (bins 0..1023) and emits 256
    // 512-bit beats in natural bin order with TLAST on beat 255.
    // -------------------------------------------------------------------------
    localparam [2:0] SRCH_IDLE    = 3'd0;
    localparam [2:0] SRCH_CAPTURE = 3'd1;
    localparam [2:0] SRCH_FETCH   = 3'd2;
    localparam [2:0] SRCH_PREP_LO = 3'd3;
    localparam [2:0] SRCH_WAIT_LO = 3'd4;
    localparam [2:0] SRCH_WAIT_HI = 3'd5;

    (* ram_style = "block" *) reg [511:0] search_lo_mem [0:127];
    (* ram_style = "block" *) reg [511:0] search_hi_mem [0:127];

    reg [2:0]   srch_state;
    reg [6:0]   srch_pair_idx;
    reg [511:0] srch_pair_lo;
    reg [511:0] srch_pair_hi;

    wire srch_mem_we = q_valid &&
                       (((srch_state == SRCH_IDLE) && ctrl_search_en && (q_beat_idx == 7'd0)) ||
                        (srch_state == SRCH_CAPTURE));

    always @(posedge aclk) begin
        if (srch_mem_we) begin
            search_lo_mem[q_beat_idx] <= q_lo512;
            search_hi_mem[q_beat_idx] <= q_hi512;
        end
        srch_pair_lo <= search_lo_mem[srch_pair_idx];
        srch_pair_hi <= search_hi_mem[srch_pair_idx];
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            srch_state           <= SRCH_IDLE;
            srch_pair_idx        <= 7'd0;
            m_axis_search_tdata  <= 512'd0;
            m_axis_search_tlast  <= 1'b0;
            m_axis_search_tvalid <= 1'b0;
            search_frame_count   <= 32'd0;
        end else begin
            case (srch_state)
                SRCH_IDLE: begin
                    m_axis_search_tvalid <= 1'b0;
                    m_axis_search_tlast  <= 1'b0;
                    if (ctrl_search_en && q_valid && (q_beat_idx == 7'd0)) begin
                        if (q_last) begin
                            srch_pair_idx <= 7'd0;
                            srch_state    <= SRCH_FETCH;
                        end else begin
                            srch_state <= SRCH_CAPTURE;
                        end
                    end
                end

                SRCH_CAPTURE: begin
                    if (q_valid && q_last) begin
                        srch_pair_idx <= 7'd0;
                        srch_state    <= SRCH_FETCH;
                    end
                end

                SRCH_FETCH: begin
                    // search_lo_mem[srch_pair_idx] / search_hi_mem[srch_pair_idx]
                    // latch into srch_pair_lo / srch_pair_hi on this clock edge.
                    srch_state <= SRCH_PREP_LO;
                end

                SRCH_PREP_LO: begin
                    m_axis_search_tdata  <= srch_pair_lo;
                    m_axis_search_tlast  <= 1'b0;
                    m_axis_search_tvalid <= 1'b1;
                    srch_state           <= SRCH_WAIT_LO;
                end

                SRCH_WAIT_LO: begin
                    if (m_axis_search_tready) begin
                        m_axis_search_tdata  <= srch_pair_hi;
                        m_axis_search_tlast  <= (srch_pair_idx == 7'd127);
                        m_axis_search_tvalid <= 1'b1;
                        srch_state           <= SRCH_WAIT_HI;
                    end
                end

                SRCH_WAIT_HI: begin
                    if (m_axis_search_tready) begin
                        m_axis_search_tvalid <= 1'b0;
                        m_axis_search_tlast  <= 1'b0;
                        if (srch_pair_idx == 7'd127) begin
                            search_frame_count <= search_frame_count + 32'd1;
                            srch_state         <= SRCH_IDLE;
                        end else begin
                            srch_pair_idx <= srch_pair_idx + 7'd1;
                            srch_state    <= SRCH_FETCH;
                        end
                    end
                end

                default: begin
                    srch_state           <= SRCH_IDLE;
                    m_axis_search_tvalid <= 1'b0;
                    m_axis_search_tlast  <= 1'b0;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Selected-Bin 4-Snapshot Packer (m_axis_capture & m_axis_beam)
    // Locks active_bin across each covariance integration frame so all 4096
    // spatial snapshots come from a single coherent frequency bin.
    // -------------------------------------------------------------------------
    reg [1:0]   snap_lane_cnt;
    reg [383:0] snap_pack_reg;
    reg [15:0]  cap_beat_cnt;
    reg [15:0]  beam_beat_cnt;

    wire [6:0] active_beat     = active_bin[9:3];
    wire       active_hi_half  = active_bin[2];
    wire [1:0] active_sub_lane = active_bin[1:0];

    wire [127:0] selected_snap128 = active_hi_half
        ? q_hi512[active_sub_lane*128 +: 128]
        : q_lo512[active_sub_lane*128 +: 128];

    wire [511:0] packed_4snap512 = {selected_snap128, snap_pack_reg};
    wire [15:0]  eff_capture_beats = (reg_capture_beats == 16'd0) ? 16'd1 : reg_capture_beats;
    wire [15:0]  eff_beam_beats    = (reg_beam_beats    == 16'd0) ? 16'd1 : reg_beam_beats;

    always @(posedge aclk) begin
        if (!aresetn) begin
            active_bin           <= 10'd18;
            snap_lane_cnt        <= 2'd0;
            snap_pack_reg        <= 384'd0;
            cap_beat_cnt         <= 16'd0;
            beam_beat_cnt        <= 16'd0;
            m_axis_capture_tdata <= 512'd0;
            m_axis_capture_tlast <= 1'b0;
            m_axis_capture_tvalid<= 1'b0;
            m_axis_beam_tdata    <= 512'd0;
            m_axis_beam_tlast    <= 1'b0;
            m_axis_beam_tvalid   <= 1'b0;
            capture_frame_count  <= 32'd0;
            capture_drop_count   <= 16'd0;
            beam_drop_count      <= 16'd0;
        end else begin
            // Clear valid when downstream accepts the holding beat
            if (m_axis_capture_tvalid && m_axis_capture_tready) begin
                m_axis_capture_tvalid <= 1'b0;
                m_axis_capture_tlast  <= 1'b0;
            end
            if (m_axis_beam_tvalid && m_axis_beam_tready) begin
                m_axis_beam_tvalid <= 1'b0;
                m_axis_beam_tlast  <= 1'b0;
            end

            // Update active_bin cleanly when idle/between capture frames
            if (!ctrl_capture_en) begin
                snap_lane_cnt <= 2'd0;
                cap_beat_cnt  <= 16'd0;
                active_bin    <= desired_bin;
            end else if ((cap_beat_cnt == 16'd0) && (snap_lane_cnt == 2'd0) &&
                         !(q_valid && (q_beat_idx == active_beat))) begin
                active_bin <= desired_bin;
            end

            if (!ctrl_beam_en) begin
                beam_beat_cnt <= 16'd0;
            end

            if (q_valid && (q_beat_idx == active_beat)) begin
                if (!ctrl_capture_en && !ctrl_beam_en) begin
                    snap_lane_cnt <= 2'd0;
                end else if (snap_lane_cnt < 2'd3) begin
                    snap_pack_reg[snap_lane_cnt*128 +: 128] <= selected_snap128;
                    snap_lane_cnt <= snap_lane_cnt + 2'd1;
                end else begin
                    snap_lane_cnt <= 2'd0;

                    // Covariance capture output (strict AXI4-Stream holding reg)
                    if (ctrl_capture_en) begin
                        if (!m_axis_capture_tvalid || m_axis_capture_tready) begin
                            m_axis_capture_tdata  <= packed_4snap512;
                            m_axis_capture_tvalid <= 1'b1;
                            if (cap_beat_cnt + 16'd1 >= eff_capture_beats) begin
                                m_axis_capture_tlast <= 1'b1;
                                cap_beat_cnt         <= 16'd0;
                                capture_frame_count  <= capture_frame_count + 32'd1;
                                active_bin           <= desired_bin;
                            end else begin
                                m_axis_capture_tlast <= 1'b0;
                                cap_beat_cnt         <= cap_beat_cnt + 16'd1;
                            end
                        end else begin
                            capture_drop_count <= capture_drop_count + 16'd1;
                        end
                    end

                    // Beamformer monitor output (strict AXI4-Stream holding reg)
                    if (ctrl_beam_en) begin
                        if (!m_axis_beam_tvalid || m_axis_beam_tready) begin
                            m_axis_beam_tdata  <= packed_4snap512;
                            m_axis_beam_tvalid <= 1'b1;
                            if (beam_beat_cnt + 16'd1 >= eff_beam_beats) begin
                                m_axis_beam_tlast <= 1'b1;
                                beam_beat_cnt      <= 16'd0;
                            end else begin
                                m_axis_beam_tlast <= 1'b0;
                                beam_beat_cnt      <= beam_beat_cnt + 16'd1;
                            end
                        end else begin
                            beam_drop_count <= beam_drop_count + 16'd1;
                        end
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Legacy MTS Capture Tie-Off / Optional Monitor Outputs (strict AXI4-Stream)
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_mon_ch0_tdata  <= 128'd0;
            m_axis_mon_ch0_tvalid <= 1'b0;
            m_axis_mon_ch1_tdata  <= 128'd0;
            m_axis_mon_ch1_tvalid <= 1'b0;
            m_axis_mon_ch2_tdata  <= 128'd0;
            m_axis_mon_ch2_tvalid <= 1'b0;
            m_axis_mon_ch3_tdata  <= 128'd0;
            m_axis_mon_ch3_tvalid <= 1'b0;
        end else begin
            if (!m_axis_mon_ch0_tvalid || m_axis_mon_ch0_tready) begin
                m_axis_mon_ch0_tvalid <= ctrl_mon_en && q_valid;
                if (ctrl_mon_en && q_valid) m_axis_mon_ch0_tdata <= q_mon0;
            end
            if (!m_axis_mon_ch1_tvalid || m_axis_mon_ch1_tready) begin
                m_axis_mon_ch1_tvalid <= ctrl_mon_en && q_valid;
                if (ctrl_mon_en && q_valid) m_axis_mon_ch1_tdata <= q_mon1;
            end
            if (!m_axis_mon_ch2_tvalid || m_axis_mon_ch2_tready) begin
                m_axis_mon_ch2_tvalid <= ctrl_mon_en && q_valid;
                if (ctrl_mon_en && q_valid) m_axis_mon_ch2_tdata <= q_mon2;
            end
            if (!m_axis_mon_ch3_tvalid || m_axis_mon_ch3_tready) begin
                m_axis_mon_ch3_tvalid <= ctrl_mon_en && q_valid;
                if (ctrl_mon_en && q_valid) m_axis_mon_ch3_tdata <= q_mon3;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Candidate Feedback Capture & AXI4-Lite Register File
    // -------------------------------------------------------------------------
    wire aw_capture = s_axi_ctrl_awvalid && s_axi_ctrl_awready;
    wire w_capture  = s_axi_ctrl_wvalid  && s_axi_ctrl_wready;
    wire wr_ready_to_commit = (aw_holding || aw_capture) && (w_holding || w_capture);
    wire [7:0]  wr_eff_addr = aw_holding ? aw_addr_reg : s_axi_ctrl_awaddr;
    wire [31:0] wr_eff_data = w_holding  ? w_data_reg  : s_axi_ctrl_wdata;
    wire [3:0]  wr_eff_strb = w_holding  ? w_strb_reg  : s_axi_ctrl_wstrb;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_auto_bin_en   <= 1'b1;
            ctrl_capture_en    <= 1'b1;
            ctrl_search_en     <= 1'b1;
            ctrl_beam_en       <= 1'b1;
            ctrl_mon_en        <= 1'b0;
            reg_manual_bin     <= 10'd18;
            reg_scale_shift    <= 4'd9;
            reg_capture_beats  <= 16'd1024;
            reg_beam_beats     <= 16'd64;

            pending_auto_bin   <= 10'd18;
            has_auto_bin       <= 1'b0;
            last_cand_bin      <= 16'd0;
            last_cand_valid    <= 1'b0;
            last_cand_peak     <= 64'd0;
            last_cand_avg      <= 64'd0;
            candidate_count    <= 32'd0;

            aw_holding         <= 1'b0;
            aw_addr_reg        <= 8'd0;
            w_holding          <= 1'b0;
            w_data_reg         <= 32'd0;
            w_strb_reg         <= 4'd0;
            s_axi_ctrl_bvalid  <= 1'b0;
            s_axi_ctrl_rvalid  <= 1'b0;
            s_axi_ctrl_rdata   <= 32'd0;
        end else begin
            // Candidate feedback stream from candidate_peak4
            if (s_axis_candidate_tvalid && s_axis_candidate_tready) begin
                last_cand_bin   <= s_axis_candidate_tdata[15:0];
                last_cand_valid <= s_axis_candidate_tdata[16];
                last_cand_peak  <= s_axis_candidate_tdata[95:32];
                last_cand_avg   <= s_axis_candidate_tdata[159:96];
                candidate_count <= candidate_count + 32'd1;
                if (s_axis_candidate_tdata[16]) begin
                    pending_auto_bin <= s_axis_candidate_tdata[9:0];
                    has_auto_bin     <= 1'b1;
                end
            end

            // AXI4-Lite Write Channel
            if (aw_capture) begin
                aw_holding  <= 1'b1;
                aw_addr_reg <= s_axi_ctrl_awaddr;
            end
            if (w_capture) begin
                w_holding  <= 1'b1;
                w_data_reg <= s_axi_ctrl_wdata;
                w_strb_reg <= s_axi_ctrl_wstrb;
            end

            if (s_axi_ctrl_bvalid && s_axi_ctrl_bready) begin
                s_axi_ctrl_bvalid <= 1'b0;
            end

            if (wr_ready_to_commit && !s_axi_ctrl_bvalid) begin
                aw_holding        <= 1'b0;
                w_holding         <= 1'b0;
                s_axi_ctrl_bvalid <= 1'b1;
                case (wr_eff_addr[7:2])
                    6'h00: begin
                        if (wr_eff_strb[0]) begin
                            ctrl_auto_bin_en <= wr_eff_data[0];
                            ctrl_capture_en  <= wr_eff_data[1];
                            ctrl_search_en   <= wr_eff_data[2];
                            ctrl_beam_en     <= wr_eff_data[3];
                            ctrl_mon_en      <= wr_eff_data[4];
                        end
                    end
                    6'h01: begin
                        if (wr_eff_strb[0]) reg_manual_bin[7:0]  <= wr_eff_data[7:0];
                        if (wr_eff_strb[1]) reg_manual_bin[9:8]  <= wr_eff_data[9:8];
                    end
                    6'h02: begin
                        if (wr_eff_strb[0]) reg_scale_shift      <= wr_eff_data[3:0];
                    end
                    6'h03: begin
                        if (wr_eff_strb[0]) reg_capture_beats[7:0]  <= wr_eff_data[7:0];
                        if (wr_eff_strb[1]) reg_capture_beats[15:8] <= wr_eff_data[15:8];
                    end
                    6'h04: begin
                        if (wr_eff_strb[0]) reg_beam_beats[7:0]  <= wr_eff_data[7:0];
                        if (wr_eff_strb[1]) reg_beam_beats[15:8] <= wr_eff_data[15:8];
                    end
                    default: ;
                endcase
            end

            // AXI4-Lite Read Channel
            if (s_axi_ctrl_rvalid && s_axi_ctrl_rready) begin
                s_axi_ctrl_rvalid <= 1'b0;
            end
            if (s_axi_ctrl_arvalid && s_axi_ctrl_arready) begin
                s_axi_ctrl_rvalid <= 1'b1;
                case (s_axi_ctrl_araddr[7:2])
                    6'h00: s_axi_ctrl_rdata <= {27'd0, ctrl_mon_en, ctrl_beam_en, ctrl_search_en, ctrl_capture_en, ctrl_auto_bin_en};
                    6'h01: s_axi_ctrl_rdata <= {22'd0, reg_manual_bin};
                    6'h02: s_axi_ctrl_rdata <= {28'd0, reg_scale_shift};
                    6'h03: s_axi_ctrl_rdata <= {16'd0, reg_capture_beats};
                    6'h04: s_axi_ctrl_rdata <= {16'd0, reg_beam_beats};
                    6'h05: s_axi_ctrl_rdata <= {5'd0, srch_state, 6'd0, has_auto_bin, last_cand_valid, 6'd0, active_bin};
                    6'h06: s_axi_ctrl_rdata <= {15'd0, last_cand_valid, last_cand_bin};
                    6'h07: s_axi_ctrl_rdata <= last_cand_peak[31:0];
                    6'h08: s_axi_ctrl_rdata <= last_cand_peak[63:32];
                    6'h09: s_axi_ctrl_rdata <= last_cand_avg[31:0];
                    6'h0A: s_axi_ctrl_rdata <= last_cand_avg[63:32];
                    6'h0B: s_axi_ctrl_rdata <= snapshot_count;
                    6'h0C: s_axi_ctrl_rdata <= search_frame_count;
                    6'h0D: s_axi_ctrl_rdata <= capture_frame_count;
                    6'h0E: s_axi_ctrl_rdata <= candidate_count;
                    6'h0F: s_axi_ctrl_rdata <= {capture_drop_count, beam_drop_count};
                    default: s_axi_ctrl_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
