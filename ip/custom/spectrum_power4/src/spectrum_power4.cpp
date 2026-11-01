#include "spectrum_power4.hpp"

extern "C" void spectrum_power4(hls::stream<axis512_power_t>& s_axis,
                                hls::stream<axis256_power_t>& m_axis) {
#pragma HLS INTERFACE axis register_mode=both port=s_axis
#pragma HLS INTERFACE axis register_mode=both port=m_axis
#pragma HLS INTERFACE ap_ctrl_none port=return
#pragma HLS PIPELINE II=1
    axis512_power_t input=s_axis.read();
    axis256_power_t output;
    output.data=0;
lane_loop:
    for (int lane=0; lane<4; ++lane) {
#pragma HLS UNROLL
        ap_uint<64> power=0;
    channel_loop:
        for (int channel=0; channel<4; ++channel) {
#pragma HLS UNROLL
            const int word=lane*4+channel;
            ap_uint<32> packed=input.data.range(32*word+31,32*word);
            ap_int<16> realValue=(ap_int<16>)packed.range(15,0);
            ap_int<16> imagValue=(ap_int<16>)packed.range(31,16);
            ap_uint<33> channelPower=(ap_int<32>)realValue*realValue+
                                     (ap_int<32>)imagValue*imagValue;
            power+=channelPower;
        }
        output.data.range(64*lane+63,64*lane)=power;
    }
    output.keep=-1;
    output.strb=-1;
    output.last=input.last;
    m_axis.write(output);
}

