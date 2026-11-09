#ifndef PIR_HOST_SHIM_AP_AXI_SDATA_H
#define PIR_HOST_SHIM_AP_AXI_SDATA_H
// Minimal host stand-in for the AXI4-Stream sideband struct.  Only the ports
// phase_interf_4ch.cpp actually touches are modelled: data, keep, strb, last.
#include "ap_int.h"

template <int Width, int Depth = 0, int Used = 0, int Type = 0>
struct ap_axiu {
    ap_uint<Width> data;
    ap_uint<(Width + 7) / 8> keep;
    ap_uint<(Width + 7) / 8> strb;
    ap_uint<1> last;
};

#endif
