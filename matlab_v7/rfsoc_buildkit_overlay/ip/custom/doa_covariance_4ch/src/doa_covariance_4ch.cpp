#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>

typedef ap_axiu<128,0,0,0> axis128_t;
typedef ap_axiu<64,0,0,0> axis64_t;

static ap_int<16> low16(ap_uint<32> value) {
    return (ap_int<16>)value.range(15,0);
}

static ap_int<16> high16(ap_uint<32> value) {
    return (ap_int<16>)value.range(31,16);
}

static void calibrate(ap_int<16> inputReal, ap_int<16> inputImag,
                      ap_uint<32> packedCoefficient,
                      ap_int<20>& outputReal, ap_int<20>& outputImag) {
#pragma HLS INLINE
    const ap_int<16> coefficientReal=low16(packedCoefficient);
    const ap_int<16> coefficientImag=high16(packedCoefficient);
    const ap_int<36> realProduct=(ap_int<32>)inputReal*coefficientReal-
                                 (ap_int<32>)inputImag*coefficientImag;
    const ap_int<36> imagProduct=(ap_int<32>)inputReal*coefficientImag+
                                 (ap_int<32>)inputImag*coefficientReal;
    // Calibration coefficients are complex Q2.14.
    outputReal=(ap_int<20>)(realProduct >> 14);
    outputImag=(ap_int<20>)(imagProduct >> 14);
}

extern "C" void doa_covariance_4ch(hls::stream<axis128_t>& s_axis,
                                    hls::stream<axis64_t>& m_axis,
                                    ap_uint<32> cal0,
                                    ap_uint<32> cal1,
                                    ap_uint<32> cal2,
                                    ap_uint<32> cal3,
                                    ap_uint<16> frameSamples) {
#pragma HLS INTERFACE axis port=s_axis
#pragma HLS INTERFACE axis port=m_axis
#pragma HLS INTERFACE s_axilite port=cal0 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=cal1 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=cal2 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=cal3 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=frameSamples bundle=ctrl
#pragma HLS INTERFACE s_axilite port=return bundle=ctrl

    const ap_uint<32> coefficients[4]={cal0,cal1,cal2,cal3};
#pragma HLS ARRAY_PARTITION variable=coefficients complete
    const ap_uint<3> firstChannel[6]={0,0,0,1,1,2};
    const ap_uint<3> secondChannel[6]={1,2,3,2,3,3};
#pragma HLS ARRAY_PARTITION variable=firstChannel complete
#pragma HLS ARRAY_PARTITION variable=secondChannel complete

    ap_int<64> power[4]={0,0,0,0};
    ap_int<64> crossReal[6]={0,0,0,0,0,0};
    ap_int<64> crossImag[6]={0,0,0,0,0,0};
#pragma HLS ARRAY_PARTITION variable=power complete
#pragma HLS ARRAY_PARTITION variable=crossReal complete
#pragma HLS ARRAY_PARTITION variable=crossImag complete

    const ap_uint<16> samples=(frameSamples==0) ? (ap_uint<16>)4096 : frameSamples;
sample_loop:
    for (ap_uint<17> sample=0; sample<(ap_uint<17>)samples; sample++) {
#pragma HLS PIPELINE II=1
#pragma HLS LOOP_TRIPCOUNT min=4096 max=4096 avg=4096
        const axis128_t input=s_axis.read();
        ap_int<20> realValue[4];
        ap_int<20> imagValue[4];
#pragma HLS ARRAY_PARTITION variable=realValue complete
#pragma HLS ARRAY_PARTITION variable=imagValue complete
    channel_loop:
        for (int channel=0; channel<4; channel++) {
#pragma HLS UNROLL
            const ap_uint<32> packed=input.data.range(32*channel+31,32*channel);
            calibrate(low16(packed),high16(packed),coefficients[channel],
                      realValue[channel],imagValue[channel]);
            power[channel]+=(ap_int<40>)realValue[channel]*realValue[channel]+
                            (ap_int<40>)imagValue[channel]*imagValue[channel];
        }
    pair_loop:
        for (int pair=0; pair<6; pair++) {
#pragma HLS UNROLL
            const int first=firstChannel[pair];
            const int second=secondChannel[pair];
            // R(second,first) = x_second * conj(x_first).
            crossReal[pair]+=(ap_int<40>)realValue[second]*realValue[first]+
                             (ap_int<40>)imagValue[second]*imagValue[first];
            crossImag[pair]+=(ap_int<40>)imagValue[second]*realValue[first]-
                             (ap_int<40>)realValue[second]*imagValue[first];
        }
    }

output_loop:
    for (int index=0; index<16; index++) {
#pragma HLS PIPELINE II=1
        ap_int<64> value;
        if (index<4) {
            value=power[index];
        } else if (index<10) {
            value=crossReal[index-4];
        } else {
            value=crossImag[index-10];
        }
        axis64_t output;
        output.data=(ap_uint<64>)value;
        output.keep=-1;
        output.strb=-1;
        output.last=(index==15);
        m_axis.write(output);
    }
}
