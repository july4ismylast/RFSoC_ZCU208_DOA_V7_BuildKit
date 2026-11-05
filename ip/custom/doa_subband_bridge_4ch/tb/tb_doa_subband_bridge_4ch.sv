`timescale 1ns / 1ps

module tb_doa_subband_bridge_4ch;

    reg aclk = 1'b0;
    always #2.0 aclk = ~aclk; // 250 MHz (4.0 ns)

    reg         aresetn = 1'b0;

    reg  [415:0] s_axis_ch0_tdata  = 416'd0;
    reg          s_axis_ch0_tvalid = 1'b0;
    wire         s_axis_ch0_tready;
    reg          s_axis_ch0_tlast  = 1'b0;

    reg  [415:0] s_axis_ch1_tdata  = 416'd0;
    reg          s_axis_ch1_tvalid = 1'b0;
    wire         s_axis_ch1_tready;
    reg          s_axis_ch1_tlast  = 1'b0;

    reg  [415:0] s_axis_ch2_tdata  = 416'd0;
    reg          s_axis_ch2_tvalid = 1'b0;
    wire         s_axis_ch2_tready;
    reg          s_axis_ch2_tlast  = 1'b0;

    reg  [415:0] s_axis_ch3_tdata  = 416'd0;
    reg          s_axis_ch3_tvalid = 1'b0;
    wire         s_axis_ch3_tready;
    reg          s_axis_ch3_tlast  = 1'b0;

    reg  [191:0] s_axis_candidate_tdata  = 192'd0;
    reg  [23:0]  s_axis_candidate_tkeep  = 24'hFFFFFF;
    reg  [23:0]  s_axis_candidate_tstrb  = 24'hFFFFFF;
    reg          s_axis_candidate_tlast  = 1'b0;
    reg          s_axis_candidate_tvalid = 1'b0;
    wire         s_axis_candidate_tready;

    wire [511:0] m_axis_search_tdata;
    wire [63:0]  m_axis_search_tkeep;
    wire [63:0]  m_axis_search_tstrb;
    wire         m_axis_search_tlast;
    wire         m_axis_search_tvalid;
    reg          m_axis_search_tready = 1'b1;

    wire [511:0] m_axis_capture_tdata;
    wire [63:0]  m_axis_capture_tkeep;
    wire [63:0]  m_axis_capture_tstrb;
    wire         m_axis_capture_tlast;
    wire         m_axis_capture_tvalid;
    reg          m_axis_capture_tready = 1'b1;

    wire [511:0] m_axis_beam_tdata;
    wire [63:0]  m_axis_beam_tkeep;
    wire [63:0]  m_axis_beam_tstrb;
    wire         m_axis_beam_tlast;
    wire         m_axis_beam_tvalid;
    reg          m_axis_beam_tready = 1'b1;

    wire [127:0] m_axis_mon_ch0_tdata, m_axis_mon_ch1_tdata, m_axis_mon_ch2_tdata, m_axis_mon_ch3_tdata;
    wire         m_axis_mon_ch0_tvalid, m_axis_mon_ch1_tvalid, m_axis_mon_ch2_tvalid, m_axis_mon_ch3_tvalid;
    reg          m_axis_mon_ch0_tready = 1'b0;
    reg          m_axis_mon_ch1_tready = 1'b0;
    reg          m_axis_mon_ch2_tready = 1'b0;
    reg          m_axis_mon_ch3_tready = 1'b0;

    reg  [7:0]   s_axi_ctrl_awaddr  = 8'd0;
    reg  [2:0]   s_axi_ctrl_awprot  = 3'd0;
    reg          s_axi_ctrl_awvalid = 1'b0;
    wire         s_axi_ctrl_awready;
    reg  [31:0]  s_axi_ctrl_wdata   = 32'd0;
    reg  [3:0]   s_axi_ctrl_wstrb   = 4'hF;
    reg          s_axi_ctrl_wvalid  = 1'b0;
    wire         s_axi_ctrl_wready;
    wire [1:0]   s_axi_ctrl_bresp;
    wire         s_axi_ctrl_bvalid;
    reg          s_axi_ctrl_bready  = 1'b1;
    reg  [7:0]   s_axi_ctrl_araddr  = 8'd0;
    reg  [2:0]   s_axi_ctrl_arprot  = 3'd0;
    reg          s_axi_ctrl_arvalid = 1'b0;
    wire         s_axi_ctrl_arready;
    wire [31:0]  s_axi_ctrl_rdata;
    wire [1:0]   s_axi_ctrl_rresp;
    wire         s_axi_ctrl_rvalid;
    reg          s_axi_ctrl_rready  = 1'b1;

    doa_subband_bridge_4ch dut (
        .aclk                   (aclk),
        .aresetn                (aresetn),
        .s_axis_ch0_tdata       (s_axis_ch0_tdata),
        .s_axis_ch0_tvalid      (s_axis_ch0_tvalid),
        .s_axis_ch0_tready      (s_axis_ch0_tready),
        .s_axis_ch0_tlast       (s_axis_ch0_tlast),
        .s_axis_ch1_tdata       (s_axis_ch1_tdata),
        .s_axis_ch1_tvalid      (s_axis_ch1_tvalid),
        .s_axis_ch1_tready      (s_axis_ch1_tready),
        .s_axis_ch1_tlast       (s_axis_ch1_tlast),
        .s_axis_ch2_tdata       (s_axis_ch2_tdata),
        .s_axis_ch2_tvalid      (s_axis_ch2_tvalid),
        .s_axis_ch2_tready      (s_axis_ch2_tready),
        .s_axis_ch2_tlast       (s_axis_ch2_tlast),
        .s_axis_ch3_tdata       (s_axis_ch3_tdata),
        .s_axis_ch3_tvalid      (s_axis_ch3_tvalid),
        .s_axis_ch3_tready      (s_axis_ch3_tready),
        .s_axis_ch3_tlast       (s_axis_ch3_tlast),
        .s_axis_candidate_tdata (s_axis_candidate_tdata),
        .s_axis_candidate_tkeep (s_axis_candidate_tkeep),
        .s_axis_candidate_tstrb (s_axis_candidate_tstrb),
        .s_axis_candidate_tlast (s_axis_candidate_tlast),
        .s_axis_candidate_tvalid(s_axis_candidate_tvalid),
        .s_axis_candidate_tready(s_axis_candidate_tready),
        .m_axis_search_tdata    (m_axis_search_tdata),
        .m_axis_search_tkeep    (m_axis_search_tkeep),
        .m_axis_search_tstrb    (m_axis_search_tstrb),
        .m_axis_search_tlast    (m_axis_search_tlast),
        .m_axis_search_tvalid   (m_axis_search_tvalid),
        .m_axis_search_tready   (m_axis_search_tready),
        .m_axis_capture_tdata   (m_axis_capture_tdata),
        .m_axis_capture_tkeep   (m_axis_capture_tkeep),
        .m_axis_capture_tstrb   (m_axis_capture_tstrb),
        .m_axis_capture_tlast   (m_axis_capture_tlast),
        .m_axis_capture_tvalid  (m_axis_capture_tvalid),
        .m_axis_capture_tready  (m_axis_capture_tready),
        .m_axis_beam_tdata      (m_axis_beam_tdata),
        .m_axis_beam_tkeep      (m_axis_beam_tkeep),
        .m_axis_beam_tstrb      (m_axis_beam_tstrb),
        .m_axis_beam_tlast      (m_axis_beam_tlast),
        .m_axis_beam_tvalid     (m_axis_beam_tvalid),
        .m_axis_beam_tready     (m_axis_beam_tready),
        .m_axis_mon_ch0_tdata   (m_axis_mon_ch0_tdata),
        .m_axis_mon_ch0_tvalid  (m_axis_mon_ch0_tvalid),
        .m_axis_mon_ch0_tready  (m_axis_mon_ch0_tready),
        .m_axis_mon_ch1_tdata   (m_axis_mon_ch1_tdata),
        .m_axis_mon_ch1_tvalid  (m_axis_mon_ch1_tvalid),
        .m_axis_mon_ch1_tready  (m_axis_mon_ch1_tready),
        .m_axis_mon_ch2_tdata   (m_axis_mon_ch2_tdata),
        .m_axis_mon_ch2_tvalid  (m_axis_mon_ch2_tvalid),
        .m_axis_mon_ch2_tready  (m_axis_mon_ch2_tready),
        .m_axis_mon_ch3_tdata   (m_axis_mon_ch3_tdata),
        .m_axis_mon_ch3_tvalid  (m_axis_mon_ch3_tvalid),
        .m_axis_mon_ch3_tready  (m_axis_mon_ch3_tready),
        .s_axi_ctrl_awaddr      (s_axi_ctrl_awaddr),
        .s_axi_ctrl_awprot      (s_axi_ctrl_awprot),
        .s_axi_ctrl_awvalid     (s_axi_ctrl_awvalid),
        .s_axi_ctrl_awready     (s_axi_ctrl_awready),
        .s_axi_ctrl_wdata       (s_axi_ctrl_wdata),
        .s_axi_ctrl_wstrb       (s_axi_ctrl_wstrb),
        .s_axi_ctrl_wvalid      (s_axi_ctrl_wvalid),
        .s_axi_ctrl_wready      (s_axi_ctrl_wready),
        .s_axi_ctrl_bresp       (s_axi_ctrl_bresp),
        .s_axi_ctrl_bvalid      (s_axi_ctrl_bvalid),
        .s_axi_ctrl_bready      (s_axi_ctrl_bready),
        .s_axi_ctrl_araddr      (s_axi_ctrl_araddr),
        .s_axi_ctrl_arprot      (s_axi_ctrl_arprot),
        .s_axi_ctrl_arvalid     (s_axi_ctrl_arvalid),
        .s_axi_ctrl_arready     (s_axi_ctrl_arready),
        .s_axi_ctrl_rdata       (s_axi_ctrl_rdata),
        .s_axi_ctrl_rresp       (s_axi_ctrl_rresp),
        .s_axi_ctrl_rvalid      (s_axi_ctrl_rvalid),
        .s_axi_ctrl_rready      (s_axi_ctrl_rready)
    );

    // Golden reference helper functions
    function automatic logic [15:0] ref_quantize(input logic signed [25:0] v, input int shift);
        longint signed ext_v, bias, sh;
        begin
            ext_v = v;
            bias  = (shift == 0) ? 64'sd0 : (64'sd1 <<< (shift - 1));
            sh    = (ext_v + bias) >>> shift;
            if (sh > 32767)       ref_quantize = 16'h7FFF;
            else if (sh < -32768) ref_quantize = 16'h8000;
            else                  ref_quantize = sh[15:0];
        end
    endfunction

    function automatic logic signed [25:0] stim_re_s26(input int snap, input int k, input int ch);
        int base_s16;
        begin
            if (snap == 0 && k == 0 && ch == 0) begin
                stim_re_s26 = 26'sd25165824;  // +1.5 -> saturates to 0x7FFF
            end else if (snap == 0 && k == 1 && ch == 0) begin
                stim_re_s26 = -26'sd25165824; // -1.5 -> saturates to 0x8000
            end else if (snap == 0 && k == 2 && ch == 0) begin
                stim_re_s26 = 26'sd256;       // +0.5 LSB @ shift=9 -> rounds to +1
            end else begin
                base_s16 = ((snap * 29 + k * 7 + ch * 3 + 11) % 16384) - 8192;
                stim_re_s26 = $signed(base_s16) <<< 9;
            end
        end
    endfunction

    function automatic logic signed [25:0] stim_im_s26(input int snap, input int k, input int ch);
        int base_s16;
        begin
            if (snap == 0 && k == 2 && ch == 0) begin
                stim_im_s26 = 26'sd255;       // just below +0.5 LSB @ shift=9 -> rounds to 0
            end else begin
                base_s16 = -(((snap * 19 + k * 5 + ch * 13 + 7) % 16384) - 8192);
                stim_im_s26 = $signed(base_s16) <<< 9;
            end
        end
    endfunction

    function automatic logic [31:0] exp_iq32(input int snap, input int k, input int ch, input int shift);
        logic [15:0] i16, q16;
        begin
            i16 = ref_quantize(stim_re_s26(snap, k, ch), shift);
            q16 = ref_quantize(stim_im_s26(snap, k, ch), shift);
            exp_iq32 = {q16, i16};
        end
    endfunction

    // AXI4-Lite tasks (including staggered AW before W)
    task automatic axi_write(input logic [7:0] addr, input logic [31:0] data, input bit stagger_w);
        begin
            @(posedge aclk);
            s_axi_ctrl_awaddr  <= addr;
            s_axi_ctrl_awvalid <= 1'b1;
            if (!stagger_w) begin
                s_axi_ctrl_wdata  <= data;
                s_axi_ctrl_wstrb  <= 4'hF;
                s_axi_ctrl_wvalid <= 1'b1;
                fork
                    begin
                        do @(posedge aclk); while (!(s_axi_ctrl_awvalid && s_axi_ctrl_awready));
                        s_axi_ctrl_awvalid <= 1'b0;
                    end
                    begin
                        do @(posedge aclk); while (!(s_axi_ctrl_wvalid && s_axi_ctrl_wready));
                        s_axi_ctrl_wvalid <= 1'b0;
                    end
                join
            end else begin
                do @(posedge aclk); while (!(s_axi_ctrl_awvalid && s_axi_ctrl_awready));
                s_axi_ctrl_awvalid <= 1'b0;
                @(posedge aclk);
                s_axi_ctrl_wdata  <= data;
                s_axi_ctrl_wstrb  <= 4'hF;
                s_axi_ctrl_wvalid <= 1'b1;
                do @(posedge aclk); while (!(s_axi_ctrl_wvalid && s_axi_ctrl_wready));
                s_axi_ctrl_wvalid <= 1'b0;
            end
            do @(posedge aclk); while (!(s_axi_ctrl_bvalid && s_axi_ctrl_bready));
        end
    endtask

    task automatic axi_read(input logic [7:0] addr, output logic [31:0] data);
        begin
            @(posedge aclk);
            s_axi_ctrl_araddr  <= addr;
            s_axi_ctrl_arvalid <= 1'b1;
            do @(posedge aclk); while (!(s_axi_ctrl_arvalid && s_axi_ctrl_arready));
            s_axi_ctrl_arvalid <= 1'b0;
            do @(posedge aclk); while (!(s_axi_ctrl_rvalid && s_axi_ctrl_rready));
            data = s_axi_ctrl_rdata;
        end
    endtask

    task automatic drive_snapshot(input int snap_idx);
        int b, ln, ch, k;
        logic [415:0] ch_word [0:3];
        logic signed [25:0] re_v, im_v;
        begin
            for (b = 0; b < 128; b = b + 1) begin
                for (ch = 0; ch < 4; ch = ch + 1) begin
                    ch_word[ch] = 416'd0;
                    for (ln = 0; ln < 8; ln = ln + 1) begin
                        k = 8 * b + ln;
                        re_v = stim_re_s26(snap_idx, k, ch);
                        im_v = stim_im_s26(snap_idx, k, ch);
                        ch_word[ch][ln*52 +: 52] = {im_v, re_v};
                    end
                end
                s_axis_ch0_tdata  <= ch_word[0];
                s_axis_ch1_tdata  <= ch_word[1];
                s_axis_ch2_tdata  <= ch_word[2];
                s_axis_ch3_tdata  <= ch_word[3];
                s_axis_ch0_tvalid <= 1'b1;
                s_axis_ch1_tvalid <= 1'b1;
                s_axis_ch2_tvalid <= 1'b1;
                s_axis_ch3_tvalid <= 1'b1;
                s_axis_ch0_tlast  <= (b == 127);
                s_axis_ch1_tlast  <= (b == 127);
                s_axis_ch2_tlast  <= (b == 127);
                s_axis_ch3_tlast  <= (b == 127);
                @(posedge aclk);
                if (!(s_axis_ch0_tready && s_axis_ch1_tready && s_axis_ch2_tready && s_axis_ch3_tready)) begin
                    $fatal(1, "FAIL: s_axis_ch*_tready deasserted during active frame!");
                end
            end
            s_axis_ch0_tvalid <= 1'b0;
            s_axis_ch1_tvalid <= 1'b0;
            s_axis_ch2_tvalid <= 1'b0;
            s_axis_ch3_tvalid <= 1'b0;
            s_axis_ch0_tlast  <= 1'b0;
            s_axis_ch1_tlast  <= 1'b0;
            s_axis_ch2_tlast  <= 1'b0;
            s_axis_ch3_tlast  <= 1'b0;
        end
    endtask

    // Scoreboard queues and AXI4-Stream protocol stability monitors
    int         search_rx_cnt  = 0;
    reg [511:0] search_rx_data [0:511];
    reg         search_rx_last [0:511];

    int         cap_rx_cnt     = 0;
    reg [511:0] cap_rx_data    [0:63];
    reg         cap_rx_last    [0:63];

    int         beam_rx_cnt    = 0;
    reg [511:0] beam_rx_data   [0:63];
    reg         beam_rx_last   [0:63];

    int cyc = 0;
    reg         prev_srch_stall = 1'b0;
    reg [511:0] prev_srch_data  = 512'd0;
    reg         prev_srch_last  = 1'b0;

    reg         prev_cap_stall  = 1'b0;
    reg [511:0] prev_cap_data   = 512'd0;
    reg         prev_cap_last   = 1'b0;

    always @(posedge aclk) begin
        if (!aresetn) begin
            cyc             <= 0;
            prev_srch_stall <= 1'b0;
            prev_cap_stall  <= 1'b0;
        end else begin
            cyc <= cyc + 1;
            // Exercise downstream backpressure on search/capture/beam
            m_axis_search_tready  <= ((cyc % 5) != 2);
            m_axis_capture_tready <= ((cyc % 3) != 1);
            m_axis_beam_tready    <= ((cyc % 4) != 1);

            if (prev_srch_stall) begin
                if (!m_axis_search_tvalid || (m_axis_search_tdata !== prev_srch_data) || (m_axis_search_tlast !== prev_srch_last)) begin
                    $fatal(1, "FAIL: m_axis_search violated AXI4-Stream stability under tready=0");
                end
            end
            prev_srch_stall <= m_axis_search_tvalid && !m_axis_search_tready;
            prev_srch_data  <= m_axis_search_tdata;
            prev_srch_last  <= m_axis_search_tlast;

            if (prev_cap_stall) begin
                if (!m_axis_capture_tvalid || (m_axis_capture_tdata !== prev_cap_data) || (m_axis_capture_tlast !== prev_cap_last)) begin
                    $fatal(1, "FAIL: m_axis_capture violated AXI4-Stream stability under tready=0");
                end
            end
            prev_cap_stall <= m_axis_capture_tvalid && !m_axis_capture_tready;
            prev_cap_data  <= m_axis_capture_tdata;
            prev_cap_last  <= m_axis_capture_tlast;

            if (m_axis_search_tvalid && m_axis_search_tready) begin
                search_rx_data[search_rx_cnt] = m_axis_search_tdata;
                search_rx_last[search_rx_cnt] = m_axis_search_tlast;
                search_rx_cnt = search_rx_cnt + 1;
            end
            if (m_axis_capture_tvalid && m_axis_capture_tready) begin
                cap_rx_data[cap_rx_cnt] = m_axis_capture_tdata;
                cap_rx_last[cap_rx_cnt] = m_axis_capture_tlast;
                cap_rx_cnt = cap_rx_cnt + 1;
            end
            if (m_axis_beam_tvalid && m_axis_beam_tready) begin
                beam_rx_data[beam_rx_cnt] = m_axis_beam_tdata;
                beam_rx_last[beam_rx_cnt] = m_axis_beam_tlast;
                beam_rx_cnt = beam_rx_cnt + 1;
            end
        end
    end

    reg [31:0] rval;
    int s_idx, lane_i, ch_i, bin_k, word_i;
    reg [31:0] got_w, exp_w;

    initial begin
        #2000000;
        $fatal(1, "TIMEOUT: tb_doa_subband_bridge_4ch exceeded 2 ms simulation budget");
    end

    initial begin
        repeat (8) @(posedge aclk);
        aresetn <= 1'b1;
        repeat (4) @(posedge aclk);

        // 1. Check reset defaults
        axi_read(8'h00, rval);
        if (rval !== 32'h0000_000F) $fatal(1, "FAIL: CTRL default mismatch: 0x%08x", rval);
        axi_read(8'h04, rval);
        if (rval !== 32'd18)        $fatal(1, "FAIL: MANUAL_BIN default mismatch: %0d", rval);
        axi_read(8'h08, rval);
        if (rval !== 32'd9)         $fatal(1, "FAIL: SCALE_SHIFT default mismatch: %0d", rval);

        // 2. Test Search Path (enable search only first)
        axi_write(8'h00, 32'h0000_0004, 1'b1); // search_en=1, capture_en=0, beam_en=0
        drive_snapshot(0);
        while (search_rx_cnt < 256) @(posedge aclk);
        repeat (4) @(posedge aclk);
        if (search_rx_cnt !== 256) $fatal(1, "FAIL: expected 256 search beats, got %0d", search_rx_cnt);

        for (s_idx = 0; s_idx < 256; s_idx = s_idx + 1) begin
            if (search_rx_last[s_idx] !== (s_idx == 255)) begin
                $fatal(1, "FAIL: search TLAST mismatch at beat %0d", s_idx);
            end
            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                bin_k = 4 * s_idx + lane_i;
                for (ch_i = 0; ch_i < 4; ch_i = ch_i + 1) begin
                    word_i = lane_i * 4 + ch_i;
                    got_w  = search_rx_data[s_idx][word_i*32 +: 32];
                    exp_w  = exp_iq32(0, bin_k, ch_i, 9);
                    if (got_w !== exp_w) begin
                        $fatal(1, "FAIL: search mismatch beat=%0d bin=%0d ch=%0d got=0x%08x exp=0x%08x",
                               s_idx, bin_k, ch_i, got_w, exp_w);
                    end
                end
            end
        end
        $display("PASS Test 1: 256-beat natural-order search serializer + rounding/saturation + backpressure");

        // 3. Test Candidate Peak Feedback + 4-Snapshot Selected-Bin Capture & Beam
        axi_write(8'h0C, 32'd4, 1'b0); // CAPTURE_BEATS = 4 (16 snapshots)
        axi_write(8'h10, 32'd2, 1'b1); // BEAM_BEATS    = 2 (8 snapshots/packet)

        // Inject candidate bin 517 (beat=64, hi_half=1, sub_lane=1)
        @(posedge aclk);
        s_axis_candidate_tdata  <= {32'd0, 64'h0001_0002_0003_0004, 64'h0123_4567_89AB_CDEF, 15'd0, 1'b1, 16'd517};
        s_axis_candidate_tvalid <= 1'b1;
        s_axis_candidate_tlast  <= 1'b1;
        @(posedge aclk);
        s_axis_candidate_tvalid <= 1'b0;
        s_axis_candidate_tlast  <= 1'b0;
        repeat (2) @(posedge aclk);

        // Enable auto_bin_en=1, capture_en=1, search_en=0, beam_en=1 (0x0B)
        axi_write(8'h00, 32'h0000_000B, 1'b0);
        repeat (2) @(posedge aclk);

        for (s_idx = 1; s_idx <= 16; s_idx = s_idx + 1) begin
            drive_snapshot(s_idx);
        end
        repeat (16) @(posedge aclk);

        if (cap_rx_cnt !== 4)  $fatal(1, "FAIL: expected 4 capture beats, got %0d", cap_rx_cnt);
        if (beam_rx_cnt !== 4) $fatal(1, "FAIL: expected 4 beam beats (2x2), got %0d", beam_rx_cnt);

        for (s_idx = 0; s_idx < 4; s_idx = s_idx + 1) begin
            if (cap_rx_last[s_idx] !== (s_idx == 3)) begin
                $fatal(1, "FAIL: capture TLAST mismatch at beat %0d", s_idx);
            end
            if (beam_rx_last[s_idx] !== ((s_idx % 2) == 1)) begin
                $fatal(1, "FAIL: beam TLAST mismatch at beat %0d", s_idx);
            end
            for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
                for (ch_i = 0; ch_i < 4; ch_i = ch_i + 1) begin
                    word_i = lane_i * 4 + ch_i;
                    exp_w  = exp_iq32(1 + s_idx * 4 + lane_i, 517, ch_i, 9);
                    if (cap_rx_data[s_idx][word_i*32 +: 32] !== exp_w) begin
                        $fatal(1, "FAIL: capture data mismatch beat=%0d lane=%0d ch=%0d got=0x%08x exp=0x%08x",
                               s_idx, lane_i, ch_i, cap_rx_data[s_idx][word_i*32 +: 32], exp_w);
                    end
                    if (beam_rx_data[s_idx][word_i*32 +: 32] !== exp_w) begin
                        $fatal(1, "FAIL: beam data mismatch beat=%0d lane=%0d ch=%0d", s_idx, lane_i, ch_i);
                    end
                end
            end
        end

        // Check telemetry registers
        axi_read(8'h18, rval);
        if (rval !== {15'd0, 1'b1, 16'd517}) $fatal(1, "FAIL: LAST_CANDIDATE mismatch: 0x%08x", rval);
        axi_read(8'h1C, rval);
        if (rval !== 32'h89AB_CDEF)          $fatal(1, "FAIL: PEAK_LO mismatch: 0x%08x", rval);
        axi_read(8'h20, rval);
        if (rval !== 32'h0123_4567)          $fatal(1, "FAIL: PEAK_HI mismatch: 0x%08x", rval);
        axi_read(8'h3C, rval);
        if (rval !== 32'd0)                  $fatal(1, "FAIL: unexpected drop count: 0x%08x", rval);
        $display("PASS Test 2: Closed-loop candidate bin 517 capture + beam + AXI4-Lite telemetry");

        // 4. Test Manual Bin Override (bin 26: beat=3, hi_half=0, sub_lane=2)
        axi_write(8'h00, 32'h0000_0000, 1'b0); // disable capture cleanly before manual bin change
        axi_write(8'h04, 32'd26, 1'b0);        // MANUAL_BIN = 26
        axi_write(8'h0C, 32'd1,  1'b0);        // CAPTURE_BEATS = 1 (4 snapshots)
        axi_write(8'h00, 32'h0000_0002, 1'b0); // auto_bin_en=0, capture_en=1
        repeat (2) @(posedge aclk);

        for (s_idx = 20; s_idx < 24; s_idx = s_idx + 1) begin
            drive_snapshot(s_idx);
        end
        repeat (16) @(posedge aclk);
        if (cap_rx_cnt !== 5 || cap_rx_last[4] !== 1'b1) begin
            $fatal(1, "FAIL: manual bin capture beat missing (cap_rx_cnt=%0d)", cap_rx_cnt);
        end
        for (lane_i = 0; lane_i < 4; lane_i = lane_i + 1) begin
            for (ch_i = 0; ch_i < 4; ch_i = ch_i + 1) begin
                word_i = lane_i * 4 + ch_i;
                exp_w  = exp_iq32(20 + lane_i, 26, ch_i, 9);
                if (cap_rx_data[4][word_i*32 +: 32] !== exp_w) begin
                    $fatal(1, "FAIL: manual bin 26 mismatch lane=%0d ch=%0d got=0x%08x exp=0x%08x",
                           lane_i, ch_i, cap_rx_data[4][word_i*32 +: 32], exp_w);
                end
            end
        end
        $display("PASS Test 3: Manual bin 26 override verified");

        $display("ALL TESTS PASSED: tb_doa_subband_bridge_4ch");
        $finish;
    end

endmodule
