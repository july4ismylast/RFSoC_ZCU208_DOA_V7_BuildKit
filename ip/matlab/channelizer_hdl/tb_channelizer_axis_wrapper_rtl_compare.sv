`timescale 1ns/1ps

module tb_channelizer_axis_wrapper_rtl_compare;
    localparam integer SSR_BEATS = 128;
    reg aclk = 1'b0;
    reg aresetn = 1'b0;
    reg [255:0] s_axis_tdata = 256'd0;
    reg s_axis_tvalid = 1'b0;
    wire s_axis_tready;
    wire [415:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready = 1'b1;
    wire m_axis_tlast;

    reg [255:0] input_mem [0:SSR_BEATS-1];
    reg [415:0] expected_mem [0:SSR_BEATS-1];
    integer input_beats = 0;
    integer output_beats = 0;
    integer beat;

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
        end else begin
            if (s_axis_tvalid && s_axis_tready)
                input_beats = input_beats + 1;
            if (m_axis_tvalid && m_axis_tready) begin
                if (output_beats >= SSR_BEATS)
                    $fatal(1, "RTL emitted more than %0d output transfers", SSR_BEATS);
                if (m_axis_tdata !== expected_mem[output_beats])
                    $fatal(1, "Payload mismatch at SSR beat %0d: got %h expected %h",
                           output_beats, m_axis_tdata, expected_mem[output_beats]);
                if (m_axis_tlast !== (output_beats == SSR_BEATS-1))
                    $fatal(1, "TLAST mismatch at SSR beat %0d", output_beats);
                output_beats = output_beats + 1;
            end
        end
    end

    initial begin
        $readmemh("input.mem", input_mem);
        $readmemh("expected.mem", expected_mem);
        repeat (8) @(negedge aclk);
        aresetn = 1'b1;

        // Continuous SSR-8 source: one frame is 128 beats of eight samples.
        for (beat = 0; beat < SSR_BEATS; beat = beat + 1) begin
            @(negedge aclk);
            s_axis_tdata = input_mem[beat];
            s_axis_tvalid = 1'b1;
            do @(posedge aclk); while (s_axis_tready !== 1'b1);
        end
        @(negedge aclk);
        s_axis_tvalid = 1'b0;

        // Flush the registered channelizer pipeline after the one-frame input.
        repeat (512) @(posedge aclk);
        @(negedge aclk);
        if (input_beats != SSR_BEATS)
            $fatal(1, "Accepted %0d input beats; expected %0d", input_beats, SSR_BEATS);
        if (output_beats != SSR_BEATS)
            $fatal(1, "Observed %0d output beats; expected %0d", output_beats, SSR_BEATS);
        $display("GATE4 RTL PAYLOAD SIM RESULT=PASS input_beats=%0d output_beats=%0d exact_data=1 tlast_index=127",
                 input_beats, output_beats);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "RTL payload comparison simulation timeout");
    end
endmodule
