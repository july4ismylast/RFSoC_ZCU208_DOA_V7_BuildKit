#ifndef BEAM_WEIGHT_4CH_HPP
#define BEAM_WEIGHT_4CH_HPP
#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>
typedef ap_axiu<512,0,0,0> axis512_beam_t;
typedef ap_axiu<256,0,0,0> axis256_beam_t;
extern "C" void beam_weight_4ch(hls::stream<axis512_beam_t>& s_axis,
                                hls::stream<axis256_beam_t>& m_axis,
                                ap_uint<32> w0, ap_uint<32> w1,
                                ap_uint<32> w2, ap_uint<32> w3);
#endif

