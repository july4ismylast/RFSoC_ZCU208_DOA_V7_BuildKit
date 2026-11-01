#ifndef DOA_COVARIANCE_4CH_V4_HPP
#define DOA_COVARIANCE_4CH_V4_HPP

#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>

typedef ap_axiu<512,0,0,0> axis512_t;
typedef ap_axiu<64,0,0,0> axis64_t;

extern "C" void doa_covariance_4ch_v4(hls::stream<axis512_t>& s_axis,
                                        hls::stream<axis64_t>& m_axis,
                                        ap_uint<32> cal0,
                                        ap_uint<32> cal1,
                                        ap_uint<32> cal2,
                                        ap_uint<32> cal3,
                                        ap_uint<16> frameSamples);

#endif
