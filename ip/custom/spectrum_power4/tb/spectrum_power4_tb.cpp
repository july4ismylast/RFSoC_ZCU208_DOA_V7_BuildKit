#include "spectrum_power4.hpp"
#include <iostream>

int main() {
    hls::stream<axis512_power_t> input;
    hls::stream<axis256_power_t> output;
    axis512_power_t word;
    word.data=0; word.keep=-1; word.strb=-1; word.last=1;
    unsigned long long expected[4]={0,0,0,0};
    for (int lane=0; lane<4; ++lane) {
        for (int channel=0; channel<4; ++channel) {
            ap_int<16> re=(lane+1)*100+channel*7;
            ap_int<16> im=-(lane+1)*40-channel*3;
            ap_uint<32> packed=0;
            packed.range(15,0)=(ap_uint<16>)re;
            packed.range(31,16)=(ap_uint<16>)im;
            const int index=lane*4+channel;
            word.data.range(32*index+31,32*index)=packed;
            expected[lane]+=(long long)re*re+(long long)im*im;
        }
    }
    input.write(word);
    spectrum_power4(input,output);
    axis256_power_t result=output.read();
    int failures=!result.last;
    for (int lane=0; lane<4; ++lane) {
        unsigned long long actual=(unsigned long long)result.data.range(64*lane+63,64*lane);
        if (actual!=expected[lane]) {
            std::cerr << "lane " << lane << " actual=" << actual << " expected=" << expected[lane] << std::endl;
            ++failures;
        }
    }
    if (!failures) std::cout << "PASS: four lanes x four channels spectrum power" << std::endl;
    return failures;
}

