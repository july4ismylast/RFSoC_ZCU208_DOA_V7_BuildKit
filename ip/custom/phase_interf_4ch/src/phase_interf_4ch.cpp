#include "phase_interf_4ch.hpp"
#include "phase_interf_core.hpp"

// -----------------------------------------------------------------------------
// V07 per-bin phase interferometer (see V07_PHASE_INTERFEROMETRY.md).
//
// For every frame (frameSamples complex samples per channel) the block
// accumulates, from the calibrated lanes:
//
//   power[c]      = sum |X_c|^2
//   cross[p]      = sum X_a * conj(X_b)     for the six baselines below
//
// and then extracts six phases with a 16-iteration CORDIC.  The convolution-free
// sign convention (proven by the host test and by
// scripts/phase_interf_verify.py) is
//
//   phase(S_ab) = +2*pi*f*(p_b - p_a).u/c   =>   u_axis = +phase*c/(2*pi*f*d)
//
// so a positive phase on baseline 0 (CH1->CH2, +y) means uy > 0, and baseline 1
// (CH1->CH3, +z) means uz > 0.
//
// The phase record is produced at the DOA clock (behind the bin selector), not
// at the 250 MHz bin rate: six CORDICs at 250 MHz for every bin would be absurd,
// and the PS only needs phases for the bins that the search branch selected.
// -----------------------------------------------------------------------------

static pir::CalCoefficient unpackCal(ap_uint<32> packed) {
    pir::CalCoefficient cal;
    cal.re = static_cast<std::int16_t>((ap_int<16>)packed.range(15, 0));
    cal.im = static_cast<std::int16_t>((ap_int<16>)packed.range(31, 16));
    return cal;
}

extern "C" void phase_interf_4ch(hls::stream<axis512_t>& s_axis,
                                 hls::stream<axis64_t>& m_axis,
                                 hls::stream<axis128_t>& m_phase,
                                 ap_uint<32> cal0,
                                 ap_uint<32> cal1,
                                 ap_uint<32> cal2,
                                 ap_uint<32> cal3,
                                 ap_uint<16> frameSamples,
                                 ap_uint<16> frameTag) {
// register_mode=both on the wide stream, matching doa_covariance_4ch_v4: the
// 512-bit input fans out to 16 calibration multipliers before use.
#pragma HLS INTERFACE axis register_mode=both port=s_axis
#pragma HLS INTERFACE axis port=m_axis
#pragma HLS INTERFACE axis port=m_phase
#pragma HLS INTERFACE s_axilite port=cal0 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=cal1 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=cal2 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=cal3 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=frameSamples bundle=ctrl
#pragma HLS INTERFACE s_axilite port=frameTag bundle=ctrl
#pragma HLS INTERFACE s_axilite port=return bundle=ctrl

    pir::CalCoefficient cal[4];
#pragma HLS ARRAY_PARTITION variable=cal complete
    cal[0] = unpackCal(cal0);
    cal[1] = unpackCal(cal1);
    cal[2] = unpackCal(cal2);
    cal[3] = unpackCal(cal3);

    ap_int<64> power[4];
    ap_int<64> crossReal[6];
    ap_int<64> crossImag[6];
#pragma HLS ARRAY_PARTITION variable=power complete
#pragma HLS ARRAY_PARTITION variable=crossReal complete
#pragma HLS ARRAY_PARTITION variable=crossImag complete

    for (int channel = 0; channel < 4; ++channel) {
#pragma HLS UNROLL
        power[channel] = 0;
    }
    for (int pair = 0; pair < 6; ++pair) {
#pragma HLS UNROLL
        crossReal[pair] = 0;
        crossImag[pair] = 0;
    }

    const ap_uint<16> samples = (frameSamples == 0) ? (ap_uint<16>)4096 : frameSamples;
    const int beatCount = (samples.to_uint() + 3) / 4;

beat_loop:
    for (int beat = 0; beat < beatCount; ++beat) {
#pragma HLS PIPELINE II=1
#pragma HLS LOOP_TRIPCOUNT min=1 max=1024 avg=1024
        axis512_t input = s_axis.read();
    lane_loop:
        for (int lane = 0; lane < 4; ++lane) {
#pragma HLS UNROLL
            std::int32_t realValue[4];
            std::int32_t imagValue[4];
#pragma HLS ARRAY_PARTITION variable=realValue complete
#pragma HLS ARRAY_PARTITION variable=imagValue complete
        channel_loop:
            for (int channel = 0; channel < 4; ++channel) {
#pragma HLS UNROLL
                const int word = lane * 4 + channel;
                ap_uint<32> packed = input.data.range(32 * word + 31, 32 * word);
                const std::int16_t xr = static_cast<std::int16_t>((ap_int<16>)packed.range(15, 0));
                const std::int16_t xi = static_cast<std::int16_t>((ap_int<16>)packed.range(31, 16));
                pir::calibrate(xr, xi, cal[channel],
                               realValue[channel], imagValue[channel]);
                power[channel] += (ap_int<64>)realValue[channel] * realValue[channel] +
                                  (ap_int<64>)imagValue[channel] * imagValue[channel];
            }
        pair_loop:
            for (int pair = 0; pair < 6; ++pair) {
#pragma HLS UNROLL
                const int first = pir::kFirst[pair];
                const int second = pir::kSecond[pair];
                crossReal[pair] += (ap_int<64>)realValue[first] * realValue[second] +
                                   (ap_int<64>)imagValue[first] * imagValue[second];
                crossImag[pair] += (ap_int<64>)imagValue[first] * realValue[second] -
                                   (ap_int<64>)realValue[first] * imagValue[second];
            }
        }
    }

    // --- raw accumulators: identical layout to doa_covariance_4ch_v4 ---------
output_loop:
    for (int index = 0; index < 16; ++index) {
#pragma HLS PIPELINE II=1
        ap_int<64> value;
        if (index < 4) {
            value = power[index];
        } else if (index < 10) {
            value = crossReal[index - 4];
        } else {
            value = crossImag[index - 10];
        }
        axis64_t output;
        output.data = (ap_uint<64>)value;
        output.keep = -1;
        output.strb = -1;
        output.last = (index == 15);
        m_axis.write(output);
    }

    // --- six CORDIC phases ---------------------------------------------------
    axis128_t phaseWord;
    phaseWord.data = 0;
    phaseWord.keep = -1;
    phaseWord.strb = -1;
    phaseWord.last = 1;
phase_loop:
    for (int pair = 0; pair < 6; ++pair) {
#pragma HLS PIPELINE II=1
        const std::int64_t y = (std::int64_t)crossImag[pair];
        const std::int64_t x = (std::int64_t)crossReal[pair];
        const ap_uint<16> bits = (ap_uint<16>)pir::atan2_q13(y, x);
        phaseWord.data.range(16 * pair + 15, 16 * pair) = bits;
    }
    phaseWord.data.range(111, 96) = (ap_uint<16>)frameTag;
    phaseWord.data.range(112, 112) = (ap_uint<1>)1;   // phases valid
    m_phase.write(phaseWord);
}
