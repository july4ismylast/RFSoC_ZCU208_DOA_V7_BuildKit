// channelizer_dut -- the same datapath as channelizer.slx, written by hand.
//
// The Model Composer model is one way to describe this design; this file is the
// other, and it is the one that can be packaged into an IP right now:
//
//     make ip-from-hdl
//
// Four independent channels, 16-bit signed samples with 14 binary point bits
// (sfix16_En14, range -2 .. 1.99994, LSB 2^-14 = 6.1e-5), four clock cycles of
// delay each, one sample per clock at 200 MHz.
//
// The delay is a plain shift register: same latency as the "Delay" block in the
// model, no clock enable, no reset (Model Composer exports none either), so the
// pipeline contents after power-up are undefined until four clocks have passed --
// exactly as in the model.
`timescale 1ns / 1ps

module channelizer_dut #(
    parameter integer CHANNELS = 4,
    parameter integer WIDTH    = 16,
    parameter integer LATENCY  = 4
) (
    input  wire                          clk,
    input  wire [CHANNELS*WIDTH-1:0]     din,
    output wire [CHANNELS*WIDTH-1:0]     dout
);

    genvar ch;
    generate
        for (ch = 0; ch < CHANNELS; ch = ch + 1) begin : g_channel
            reg [WIDTH-1:0] pipe [0:LATENCY-1];
            integer stage;

            always @(posedge clk) begin
                pipe[0] <= din[ch*WIDTH +: WIDTH];
                for (stage = 1; stage < LATENCY; stage = stage + 1) begin
                    pipe[stage] <= pipe[stage-1];
                end
            end

            assign dout[ch*WIDTH +: WIDTH] = pipe[LATENCY-1];
        end
    endgenerate

endmodule
