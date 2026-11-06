#ifndef PHASE_INTERF_4CH_HPP
#define PHASE_INTERF_4CH_HPP

#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>

// Same lane-major input beat and same 16-word accumulator record as
// doa_covariance_4ch_v4, so the PS writes one calibration table and one frame
// length to both blocks.
typedef ap_axiu<512,0,0,0> axis512_t;   // lane*4 + channel, {Q[31:16], I[15:0]}
typedef ap_axiu<64,0,0,0>  axis64_t;    // 16 x 64-bit accumulator words per frame
typedef ap_axiu<128,0,0,0> axis128_t;   // 6 x Q3.13 phase + tag + valid

extern "C" void phase_interf_4ch(hls::stream<axis512_t>& s_axis,
                                 hls::stream<axis64_t>& m_axis,
                                 hls::stream<axis128_t>& m_phase,
                                 ap_uint<32> cal0,
                                 ap_uint<32> cal1,
                                 ap_uint<32> cal2,
                                 ap_uint<32> cal3,
                                 ap_uint<16> frameSamples,
                                 ap_uint<16> frameTag);

#endif
