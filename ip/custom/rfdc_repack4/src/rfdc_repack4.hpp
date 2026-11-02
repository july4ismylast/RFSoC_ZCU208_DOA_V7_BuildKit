#ifndef RFDC_REPACK4_HPP
#define RFDC_REPACK4_HPP

#include <ap_int.h>
#include <hls_stream.h>

// Stage V05 gearbox (see V05_RFDC_REPACK4_SPEC.md).
//
// Raw ap_uint streams are deliberate: the RFDC m*_axis interfaces carry only
// TDATA/TVALID/TREADY (no TKEEP/TSTRB/TLAST), so the HLS ports must not
// invent side-channel signals the RFDC cannot drive.
//
// Input beat : 128-bit, eight signed 16-bit component samples;
//              lane s (0 = earliest sample) in bits [16*s+15 : 16*s].
// Output beat: 256-bit, eight 32-bit complex words in the project-wide
//              packing {Q[31:16], I[15:0]}; word s in bits
//              [32*s+31 : 32*s] is the complex sample at the same instant
//              as input lane s of that channel's I and Q beats.
typedef hls::stream<ap_uint<128> > rfdc_axis128_t;
typedef hls::stream<ap_uint<256> > rfdc_axis256_t;

extern "C" void rfdc_repack4(
    rfdc_axis128_t& s_axis_ch0_i, rfdc_axis128_t& s_axis_ch0_q,
    rfdc_axis128_t& s_axis_ch1_i, rfdc_axis128_t& s_axis_ch1_q,
    rfdc_axis128_t& s_axis_ch2_i, rfdc_axis128_t& s_axis_ch2_q,
    rfdc_axis128_t& s_axis_ch3_i, rfdc_axis128_t& s_axis_ch3_q,
    rfdc_axis256_t& m_axis_ch0, rfdc_axis256_t& m_axis_ch1,
    rfdc_axis256_t& m_axis_ch2, rfdc_axis256_t& m_axis_ch3);

#endif
