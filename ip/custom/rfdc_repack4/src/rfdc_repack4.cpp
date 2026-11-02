#include "rfdc_repack4.hpp"

// Pair one I beat and one Q beat into eight time-ordered complex words.
// Pure wiring: no arithmetic, no state, no rate change.
static ap_uint<256> pack_iq_ssr8(ap_uint<128> i_beat, ap_uint<128> q_beat) {
#pragma HLS INLINE
    ap_uint<256> packed = 0;
pack_lane:
    for (int lane = 0; lane < 8; ++lane) {
#pragma HLS UNROLL
        packed.range(32 * lane + 15, 32 * lane) =
            i_beat.range(16 * lane + 15, 16 * lane);
        packed.range(32 * lane + 31, 32 * lane + 16) =
            q_beat.range(16 * lane + 15, 16 * lane);
    }
    return packed;
}

extern "C" void rfdc_repack4(
    rfdc_axis128_t& s_axis_ch0_i, rfdc_axis128_t& s_axis_ch0_q,
    rfdc_axis128_t& s_axis_ch1_i, rfdc_axis128_t& s_axis_ch1_q,
    rfdc_axis128_t& s_axis_ch2_i, rfdc_axis128_t& s_axis_ch2_q,
    rfdc_axis128_t& s_axis_ch3_i, rfdc_axis128_t& s_axis_ch3_q,
    rfdc_axis256_t& m_axis_ch0, rfdc_axis256_t& m_axis_ch1,
    rfdc_axis256_t& m_axis_ch2, rfdc_axis256_t& m_axis_ch3) {
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch0_i
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch0_q
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch1_i
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch1_q
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch2_i
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch2_q
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch3_i
#pragma HLS INTERFACE axis register_mode=both port=s_axis_ch3_q
#pragma HLS INTERFACE axis register_mode=both port=m_axis_ch0
#pragma HLS INTERFACE axis register_mode=both port=m_axis_ch1
#pragma HLS INTERFACE axis register_mode=both port=m_axis_ch2
#pragma HLS INTERFACE axis register_mode=both port=m_axis_ch3
#pragma HLS INTERFACE ap_ctrl_none port=return
#pragma HLS PIPELINE II=1

    // Beat-join semantics: output beat n of every channel is formed from
    // input beat n of that channel's I and Q streams.  Sample-level
    // alignment between channels/tiles is established by MTS before this
    // block; the gearbox preserves beat order and never drops or reorders.
    const ap_uint<128> ch0_i = s_axis_ch0_i.read();
    const ap_uint<128> ch0_q = s_axis_ch0_q.read();
    const ap_uint<128> ch1_i = s_axis_ch1_i.read();
    const ap_uint<128> ch1_q = s_axis_ch1_q.read();
    const ap_uint<128> ch2_i = s_axis_ch2_i.read();
    const ap_uint<128> ch2_q = s_axis_ch2_q.read();
    const ap_uint<128> ch3_i = s_axis_ch3_i.read();
    const ap_uint<128> ch3_q = s_axis_ch3_q.read();

    m_axis_ch0.write(pack_iq_ssr8(ch0_i, ch0_q));
    m_axis_ch1.write(pack_iq_ssr8(ch1_i, ch1_q));
    m_axis_ch2.write(pack_iq_ssr8(ch2_i, ch2_q));
    m_axis_ch3.write(pack_iq_ssr8(ch3_i, ch3_q));
}
