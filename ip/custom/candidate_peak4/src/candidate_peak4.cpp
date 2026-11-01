#include "candidate_peak4.hpp"

extern "C" void candidate_peak4(hls::stream<axis256_candidate_t>& s_axis,
                                hls::stream<axis192_candidate_t>& m_axis,
                                ap_uint<16> thresholdQ8_8) {
#pragma HLS INTERFACE axis register_mode=both port=s_axis
#pragma HLS INTERFACE axis register_mode=both port=m_axis
#pragma HLS INTERFACE s_axilite port=thresholdQ8_8 bundle=ctrl
#pragma HLS INTERFACE ap_ctrl_none port=return
#pragma HLS PIPELINE II=1
    static ap_uint<80> frameSum=0;
    static ap_uint<64> framePeak=0;
    static ap_uint<16> peakBin=0;
    static ap_uint<16> binBase=0;

    axis256_candidate_t input=s_axis.read();
    ap_uint<80> nextSum=frameSum;
    ap_uint<64> nextPeak=framePeak;
    ap_uint<16> nextPeakBin=peakBin;
lane_loop:
    for (int lane=0; lane<4; ++lane) {
#pragma HLS UNROLL
        ap_uint<64> power=input.data.range(64*lane+63,64*lane);
        nextSum+=power;
        if (power>nextPeak) {
            nextPeak=power;
            nextPeakBin=binBase+lane;
        }
    }

    if (input.last) {
        ap_uint<16> binCount=binBase+4;
        ap_uint<64> average=(ap_uint<64>)(nextSum/binCount);
        ap_uint<80> scaledAverage=(ap_uint<80>)average*thresholdQ8_8;
        ap_uint<1> valid=((ap_uint<80>)nextPeak<<8)>scaledAverage;
        axis192_candidate_t output;
        output.data=0;
        output.data.range(15,0)=nextPeakBin;
        output.data[16]=valid;
        output.data.range(95,32)=nextPeak;
        output.data.range(159,96)=average;
        output.keep=-1; output.strb=-1; output.last=1;
        m_axis.write(output);
        frameSum=0; framePeak=0; peakBin=0; binBase=0;
    } else {
        frameSum=nextSum; framePeak=nextPeak; peakBin=nextPeakBin; binBase+=4;
    }
}

