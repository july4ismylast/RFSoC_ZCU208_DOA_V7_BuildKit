#include "candidate_peak4.hpp"
#include <iostream>

int main() {
    hls::stream<axis256_candidate_t> input;
    hls::stream<axis192_candidate_t> output;
    const unsigned long long powers[8]={10,12,9,11,8,100,10,10};
    for (int beat=0; beat<2; ++beat) {
        axis256_candidate_t word;
        word.data=0; word.keep=-1; word.strb=-1; word.last=(beat==1);
        for (int lane=0; lane<4; ++lane)
            word.data.range(64*lane+63,64*lane)=powers[beat*4+lane];
        input.write(word);
        candidate_peak4(input,output,512); // peak must exceed 2.0 x frame average
    }
    if (output.empty()) return 1;
    axis192_candidate_t result=output.read();
    unsigned bin=(unsigned)result.data.range(15,0);
    bool valid=(bool)result.data[16];
    unsigned long long peak=(unsigned long long)result.data.range(95,32);
    unsigned long long average=(unsigned long long)result.data.range(159,96);
    int failures=(bin!=5 || !valid || peak!=100 || average!=21 || !result.last);
    if (!failures) std::cout << "PASS: candidate bin=5 peak=100 average=21" << std::endl;
    return failures;
}

