#include "beam_weight_4ch.hpp"

static ap_int<16> low16(ap_uint<32> value) { return (ap_int<16>)value.range(15,0); }
static ap_int<16> high16(ap_uint<32> value) { return (ap_int<16>)value.range(31,16); }

extern "C" void beam_weight_4ch(hls::stream<axis512_beam_t>& s_axis,
                                hls::stream<axis256_beam_t>& m_axis,
                                ap_uint<32> w0, ap_uint<32> w1,
                                ap_uint<32> w2, ap_uint<32> w3) {
#pragma HLS INTERFACE axis register_mode=both port=s_axis
#pragma HLS INTERFACE axis register_mode=both port=m_axis
#pragma HLS INTERFACE s_axilite port=w0 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=w1 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=w2 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=w3 bundle=ctrl
// Free-running one-beat datapath like spectrum_power4/candidate_peak4: the
// weights stay AXI-Lite registers, but there must be no ap_start handshake
// per beat.  (v2.0 used s_axilite port=return, i.e. ap_ctrl_hs, which stalls
// a single-beat top function in the BD; fixed in IP version 2.1, V01.)
#pragma HLS INTERFACE ap_ctrl_none port=return
#pragma HLS PIPELINE II=1
    axis512_beam_t input=s_axis.read();
    axis256_beam_t output;
    output.data=0;
    const ap_uint<32> weights[4]={w0,w1,w2,w3};
#pragma HLS ARRAY_PARTITION variable=weights complete
lane_loop:
    for (int lane=0; lane<4; ++lane) {
#pragma HLS UNROLL
        ap_int<40> realAccumulator=0, imagAccumulator=0;
    channel_loop:
        for (int channel=0; channel<4; ++channel) {
#pragma HLS UNROLL
            const int word=lane*4+channel;
            ap_uint<32> packed=input.data.range(32*word+31,32*word);
            ap_int<16> xr=low16(packed), xi=high16(packed);
            ap_int<16> wr=low16(weights[channel]), wi=high16(weights[channel]);
            realAccumulator+=(ap_int<32>)xr*wr-(ap_int<32>)xi*wi;
            imagAccumulator+=(ap_int<32>)xr*wi+(ap_int<32>)xi*wr;
        }
        ap_int<32> yr=(ap_int<32>)(realAccumulator>>15);
        ap_int<32> yi=(ap_int<32>)(imagAccumulator>>15);
        output.data.range(64*lane+31,64*lane)=(ap_uint<32>)yr;
        output.data.range(64*lane+63,64*lane+32)=(ap_uint<32>)yi;
    }
    output.keep=-1; output.strb=-1; output.last=input.last;
    m_axis.write(output);
}

