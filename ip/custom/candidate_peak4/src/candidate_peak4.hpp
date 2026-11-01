#ifndef CANDIDATE_PEAK4_HPP
#define CANDIDATE_PEAK4_HPP
#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>
typedef ap_axiu<256,0,0,0> axis256_candidate_t;
typedef ap_axiu<192,0,0,0> axis192_candidate_t;
extern "C" void candidate_peak4(hls::stream<axis256_candidate_t>& s_axis,
                                hls::stream<axis192_candidate_t>& m_axis,
                                ap_uint<16> thresholdQ8_8);
#endif

