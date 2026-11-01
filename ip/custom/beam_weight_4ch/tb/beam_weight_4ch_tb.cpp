#include "beam_weight_4ch.hpp"
#include <iostream>

int main() {
    hls::stream<axis512_beam_t> input;
    hls::stream<axis256_beam_t> output;
    axis512_beam_t word;
    word.data=0; word.keep=-1; word.strb=-1; word.last=1;
    for (int lane=0; lane<4; ++lane) {
        for (int channel=0; channel<4; ++channel) {
            ap_int<16> re=lane*100+channel+1;
            ap_int<16> im=-(lane*10+channel+1);
            ap_uint<32> packed=0;
            packed.range(15,0)=(ap_uint<16>)re;
            packed.range(31,16)=(ap_uint<16>)im;
            int index=lane*4+channel;
            word.data.range(32*index+31,32*index)=packed;
        }
    }
    input.write(word);
    const ap_uint<32> half=0x00004000;
    beam_weight_4ch(input,output,half,half,half,half);
    axis256_beam_t result=output.read();
    int failures=!result.last;
    for (int lane=0; lane<4; ++lane) {
        int expectedReal=(4*lane*100+10)/2;
        int expectedImag=-(4*lane*10+10)/2;
        int actualReal=(int)(ap_int<32>)result.data.range(64*lane+31,64*lane);
        int actualImag=(int)(ap_int<32>)result.data.range(64*lane+63,64*lane+32);
        if (actualReal!=expectedReal || actualImag!=expectedImag) ++failures;
    }
    if (!failures) std::cout << "PASS: four-lane complex beam monitor" << std::endl;
    return failures;
}
