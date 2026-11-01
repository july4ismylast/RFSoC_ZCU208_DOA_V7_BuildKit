#ifndef SPECTRUM_POWER4_HPP
#define SPECTRUM_POWER4_HPP
#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>
typedef ap_axiu<512,0,0,0> axis512_power_t;
typedef ap_axiu<256,0,0,0> axis256_power_t;
extern "C" void spectrum_power4(hls::stream<axis512_power_t>& s_axis,
                                hls::stream<axis256_power_t>& m_axis);
#endif

