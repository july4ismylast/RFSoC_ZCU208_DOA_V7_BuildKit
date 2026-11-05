// Experimental single-channel AXI4-Stream shell around the Gate-1T RTL.
//
// Contract derived from V05 + the passed V06 Gates 0T-3T:
//   * input: 8 complex signed-16 samples/beat, lane 0 in the LSB word,
//     each word packed {imag[15:0], real[15:0]}; no TKEEP/TLAST;
//   * output: 8 complex signed-26 bins/beat, lane 0 in the LSB word,
//     each word packed {imag[25:0], real[25:0]}; TLAST every 128
//     accepted output beats (one 1024-bin snapshot);
//   * no internal elastic buffer: downstream TREADY stalls the core via
//     its HDL Coder clock-enable and propagates upstream as S_AXIS_TREADY.
//     This matches the V05 continuous-search assumption; board-level FIFO
//     sizing/overflow protection remains a later integration task.
//
// This is an isolated wrapper candidate, not a BD connection or package.
module channelizer_axis_wrapper (
    input  wire         aclk,
    input  wire         aresetn,

    input  wire [255:0] s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    output wire [415:0] m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast
);
    localparam [6:0] LAST_BEAT_IN_SNAPSHOT = 7'd127;

    wire core_valid_out;
    wire signed [15:0] core_re_in [0:7];
    wire signed [15:0] core_im_in [0:7];
    wire [25:0] core_re_out [0:7];
    wire [25:0] core_im_out [0:7];
    wire core_ce_out;
    reg [6:0] output_beat_in_snapshot;

    // The raw dsphdl.Channelizer has no TREADY port. Use its global
    // clock-enable to hold all internal state while the AXI sink is stalled.
    assign s_axis_tready = m_axis_tready;
    wire core_clk_enable = m_axis_tready;
    wire core_input_valid = s_axis_tvalid && s_axis_tready;

    genvar lane;
    generate
        for (lane = 0; lane < 8; lane = lane + 1) begin : g_pack_lanes
            assign core_re_in[lane] = s_axis_tdata[(32*lane) +: 16];
            assign core_im_in[lane] = s_axis_tdata[(32*lane + 16) +: 16];
            assign m_axis_tdata[(52*lane) +: 26] = core_re_out[lane];
            assign m_axis_tdata[(52*lane + 26) +: 26] = core_im_out[lane];
        end
    endgenerate

    Channelizer_DUT u_channelizer (
        .clk(aclk),
        .reset(~aresetn),
        .clk_enable(core_clk_enable),
        .dataIn_re_0(core_re_in[0]), .dataIn_re_1(core_re_in[1]),
        .dataIn_re_2(core_re_in[2]), .dataIn_re_3(core_re_in[3]),
        .dataIn_re_4(core_re_in[4]), .dataIn_re_5(core_re_in[5]),
        .dataIn_re_6(core_re_in[6]), .dataIn_re_7(core_re_in[7]),
        .dataIn_im_0(core_im_in[0]), .dataIn_im_1(core_im_in[1]),
        .dataIn_im_2(core_im_in[2]), .dataIn_im_3(core_im_in[3]),
        .dataIn_im_4(core_im_in[4]), .dataIn_im_5(core_im_in[5]),
        .dataIn_im_6(core_im_in[6]), .dataIn_im_7(core_im_in[7]),
        .validIn(core_input_valid),
        .ce_out(core_ce_out),
        .dataOut_re_0(core_re_out[0]), .dataOut_re_1(core_re_out[1]),
        .dataOut_re_2(core_re_out[2]), .dataOut_re_3(core_re_out[3]),
        .dataOut_re_4(core_re_out[4]), .dataOut_re_5(core_re_out[5]),
        .dataOut_re_6(core_re_out[6]), .dataOut_re_7(core_re_out[7]),
        .dataOut_im_0(core_im_out[0]), .dataOut_im_1(core_im_out[1]),
        .dataOut_im_2(core_im_out[2]), .dataOut_im_3(core_im_out[3]),
        .dataOut_im_4(core_im_out[4]), .dataOut_im_5(core_im_out[5]),
        .dataOut_im_6(core_im_out[6]), .dataOut_im_7(core_im_out[7]),
        .validOut(core_valid_out)
    );

    assign m_axis_tvalid = core_valid_out;
    assign m_axis_tlast = core_valid_out &&
                          (output_beat_in_snapshot == LAST_BEAT_IN_SNAPSHOT);

    always @(posedge aclk) begin
        if (!aresetn) begin
            output_beat_in_snapshot <= 7'd0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (output_beat_in_snapshot == LAST_BEAT_IN_SNAPSHOT)
                output_beat_in_snapshot <= 7'd0;
            else
                output_beat_in_snapshot <= output_beat_in_snapshot + 7'd1;
        end
    end
endmodule
