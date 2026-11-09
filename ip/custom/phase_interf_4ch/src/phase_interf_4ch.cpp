#include "phase_interf_4ch.hpp"
#include "phase_interf_core.hpp"

// -----------------------------------------------------------------------------
// V07 per-bin phase interferometer (see V07_PHASE_INTERFEROMETRY.md).
//
// For every frame (frameSamples complex samples per channel) the block
// accumulates, from the calibrated lanes:
//
//   power[c]      = sum |X_c|^2
//   cross[p]      = sum X_b * conj(X_a)     for the six baselines below
//
// and then extracts six phases with a 16-iteration CORDIC.  The product order is
// deliberately the same as doa_covariance_4ch_v4, so the 16-word output is a
// drop-in replacement for that block and the PS can reuse
// estimate_doa_from_covariance_v7.m unchanged.  With A_n = exp(-j*k*p_n.u):
//
//   phase(S_ba) = -2*pi*f*(p_b - p_a).u/c
//
// so for a target at positive uy the baseline-0 phase (CH1->CH2, +y) is
// NEGATIVE, and the PS applies the leading minus of
// u = -(B'WB)^-1 * B'W*phase / k.
//
// Clock: ap_clk is the 250 MHz wideband fabric clock (4.0 ns), the channelizer's
// output domain -- see build_hls.tcl, which constrains WIDEBAND_CLOCK_PERIOD_NS.
// The phases are produced once per frame, not once per bin, so a single shared
// CORDIC datapath is enough (see the phase_loop comment below).
// -----------------------------------------------------------------------------

// .to_int()/.to_int64() are used instead of C-style casts on ap_int so the same
// source compiles both in Vitis HLS and against tb/host_shim (make host-kernel-check).
static std::int16_t signedHalf(ap_uint<32> packed, int lowBit) {
    return static_cast<std::int16_t>(((ap_int<16>)packed.range(lowBit + 15, lowBit)).to_int());
}

static pir::CalCoefficient unpackCal(ap_uint<32> packed) {
    pir::CalCoefficient cal;
    cal.re = signedHalf(packed, 0);
    cal.im = signedHalf(packed, 16);
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
                const std::int16_t xr = signedHalf(packed, 0);
                const std::int16_t xi = signedHalf(packed, 16);
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
                crossReal[pair] += (ap_int<64>)realValue[second] * realValue[first] +
                                   (ap_int<64>)imagValue[second] * imagValue[first];
                crossImag[pair] += (ap_int<64>)imagValue[second] * realValue[first] -
                                   (ap_int<64>)realValue[second] * imagValue[first];
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

    // --- six phases through one shared CORDIC --------------------------------
    axis128_t phaseWord;
    phaseWord.data = 0;
    phaseWord.keep = -1;
    phaseWord.strb = -1;
    phaseWord.last = 1;
// ONE shared CORDIC, deliberately sequential.  Pipelining this loop at II=1
// would need six fully unrolled 16-stage 64-bit CORDICs (six cascaded adder
// chains, ~16 levels deep) which cannot close 4.0 ns; the loop is instead run
// as a state machine that reuses a single normaliser+CORDIC datapath.  The
// cost is ~250 cycles once per frame.  For the channelised input this frame is
// 4096 samples of a ~2 MS/s bin, i.e. ~2 ms, so the phase pass is ~0.01 % of
// the frame time.  If this block is ever fed a continuous stream instead, the
// choice must be re-measured: six replications cost ~6x the CORDIC LUT.
phase_loop:
    for (int pair = 0; pair < 6; ++pair) {
#pragma HLS LOOP_TRIPCOUNT min=6 max=6 avg=6
        const std::int64_t y = crossImag[pair].to_int64();
        const std::int64_t x = crossReal[pair].to_int64();
        const ap_uint<16> bits = (ap_uint<16>)pir::atan2_q13(y, x);
        phaseWord.data.range(16 * pair + 15, 16 * pair) = bits;
    }
    phaseWord.data.range(111, 96) = (ap_uint<16>)frameTag;
    phaseWord.data.range(112, 112) = (ap_uint<1>)1;   // phases valid
    m_phase.write(phaseWord);
}
