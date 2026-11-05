`timescale 1ns/1ps

module tb_channelizer_axis_wrapper;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg [255:0] s_axis_tdata = 256'd0;
    reg s_axis_tvalid = 1'b0;
    wire s_axis_tready;
    wire [415:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready = 1'b1;
    wire m_axis_tlast;

    integer input_beats = 0;
    integer output_beats = 0;
    integer tlast_beats = 0;
    integer held_output_cycles = 0;
    integer beat;
    integer lane;
    reg stall_active = 1'b0;
    reg [415:0] held_output_data;
    reg held_output_last;
    reg [255:0] held_input_data;

    always #2 aclk = ~aclk;

    channelizer_axis_wrapper dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    always @(posedge aclk) begin
        if (!aresetn) begin
            input_beats = 0;
            output_beats = 0;
            tlast_beats = 0;
            held_output_cycles = 0;
            stall_active = 1'b0;
        end else begin
            if (s_axis_tvalid && s_axis_tready)
                input_beats = input_beats + 1;

            if (m_axis_tvalid && m_axis_tready) begin
                if (m_axis_tlast) begin
                    if (output_beats != 127)
                        $fatal(1, "TLAST on output beat index %0d, expected 127", output_beats);
                    tlast_beats = tlast_beats + 1;
                end
                output_beats = output_beats + 1;
                if (output_beats > 128)
                    $fatal(1, "More than 128 output transfers for one input snapshot");
            end

            if (m_axis_tvalid && !m_axis_tready) begin
                if (!stall_active) begin
                    held_output_data = m_axis_tdata;
                    held_output_last = m_axis_tlast;
                end else if ((m_axis_tdata !== held_output_data) ||
                             (m_axis_tlast !== held_output_last)) begin
                    $fatal(1, "Output data or TLAST changed while stalled");
                end
                if (s_axis_tready !== 1'b0)
                    $fatal(1, "S_AXIS_TREADY did not follow stalled M_AXIS_TREADY");
                held_output_cycles = held_output_cycles + 1;
                stall_active = 1'b1;
            end else begin
                stall_active = 1'b0;
            end
        end
    end

    task automatic set_input_beat(input integer beat_index);
        integer sample_lane;
        integer sample_value;
        begin
            for (sample_lane = 0; sample_lane < 8; sample_lane = sample_lane + 1) begin
                sample_value = beat_index * 8 + sample_lane + 1;
                s_axis_tdata[(32*sample_lane) +: 16] = sample_value[15:0];
                s_axis_tdata[(32*sample_lane + 16) +: 16] = -sample_value;
            end
        end
    endtask

    task automatic send_input_beat(input integer beat_index);
        begin
            @(negedge aclk);
            set_input_beat(beat_index);
            s_axis_tvalid = 1'b1;
            do @(posedge aclk); while (s_axis_tready !== 1'b1);
        end
    endtask

    initial begin
        repeat (8) @(negedge aclk);
        aresetn = 1'b1;

        // One 1024-sample snapshot: 128 SSR-8 input transfers.
        for (beat = 0; beat < 128; beat = beat + 1)
            send_input_beat(beat);
        @(negedge aclk);
        s_axis_tvalid = 1'b0;

        wait (m_axis_tvalid === 1'b1);
        @(negedge aclk);
        m_axis_tready = 1'b0;
        set_input_beat(128);
        held_input_data = s_axis_tdata;
        s_axis_tvalid = 1'b1;

        // Prove output hold and upstream ready propagation across a real stall.
        repeat (8) begin
            @(negedge aclk);
            if (s_axis_tready !== 1'b0)
                $fatal(1, "Input ready was not deasserted during sink stall");
            if ((s_axis_tvalid !== 1'b1) || (s_axis_tdata !== held_input_data))
                $fatal(1, "Source beat was not held stable while input was backpressured");
        end

        m_axis_tready = 1'b1;
        do @(posedge aclk); while (s_axis_tready !== 1'b1);
        @(negedge aclk);
        s_axis_tvalid = 1'b0;

        wait (output_beats == 128);
        @(negedge aclk);
        m_axis_tready = 1'b0;
        repeat (3) @(negedge aclk);

        if (input_beats != 129)
            $fatal(1, "Accepted %0d input transfers, expected 129 including the stalled held beat", input_beats);
        if (output_beats != 128)
            $fatal(1, "Accepted %0d output transfers, expected 128", output_beats);
        if (tlast_beats != 1)
            $fatal(1, "Observed %0d accepted TLAST transfers, expected exactly one", tlast_beats);
        if (held_output_cycles < 8)
            $fatal(1, "Observed only %0d stalled output cycles", held_output_cycles);

        $display("GATE4 AXI WRAPPER SIM RESULT=PASS input_beats=%0d output_beats=%0d tlast_beats=%0d held_cycles=%0d",
                 input_beats, output_beats, tlast_beats, held_output_cycles);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Gate-4 wrapper simulation timeout");
    end
endmodule
