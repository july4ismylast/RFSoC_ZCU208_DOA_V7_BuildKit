#include "doa_covariance_4ch_v4.hpp"
#include <iostream>

static ap_int<16> sample_real(int sample, int channel) {
    return (ap_int<16>)(((sample * (channel + 3) + 17 * channel) % 1021) - 510);
}

static ap_int<16> sample_imag(int sample, int channel) {
    return (ap_int<16>)(((sample * (channel + 5) + 29 * channel) % 997) - 498);
}

int main() {
    const int samples = 4096;
    hls::stream<axis512_t> input;
    hls::stream<axis64_t> output;
    long long power[4] = {0, 0, 0, 0};
    long long crossReal[6] = {0, 0, 0, 0, 0, 0};
    long long crossImag[6] = {0, 0, 0, 0, 0, 0};
    const int first[6] = {0, 0, 0, 1, 1, 2};
    const int second[6] = {1, 2, 3, 2, 3, 3};

    for (int beat = 0; beat < samples / 4; ++beat) {
        axis512_t word;
        word.data = 0;
        word.keep = -1;
        word.strb = -1;
        word.last = (beat == samples / 4 - 1);
        for (int lane = 0; lane < 4; ++lane) {
            const int sample = beat * 4 + lane;
            ap_int<16> re[4];
            ap_int<16> im[4];
            for (int channel = 0; channel < 4; ++channel) {
                re[channel] = sample_real(sample, channel);
                im[channel] = sample_imag(sample, channel);
                const int index = lane * 4 + channel;
                ap_uint<32> packed = 0;
                packed.range(15, 0) = (ap_uint<16>)re[channel];
                packed.range(31, 16) = (ap_uint<16>)im[channel];
                word.data.range(32 * index + 31, 32 * index) = packed;
                power[channel] += (long long)re[channel] * re[channel] +
                                  (long long)im[channel] * im[channel];
            }
            for (int pair = 0; pair < 6; ++pair) {
                const int a = first[pair];
                const int b = second[pair];
                crossReal[pair] += (long long)re[b] * re[a] +
                                   (long long)im[b] * im[a];
                crossImag[pair] += (long long)im[b] * re[a] -
                                   (long long)re[b] * im[a];
            }
        }
        input.write(word);
    }

    const ap_uint<32> identityQ2_14 = 0x00004000;
    doa_covariance_4ch_v4(input, output, identityQ2_14, identityQ2_14,
                          identityQ2_14, identityQ2_14, samples);

    long long expected[16];
    for (int channel = 0; channel < 4; ++channel)
        expected[channel] = power[channel];
    for (int pair = 0; pair < 6; ++pair) {
        expected[4 + pair] = crossReal[pair];
        expected[10 + pair] = crossImag[pair];
    }

    int failures = 0;
    for (int index = 0; index < 16; ++index) {
        axis64_t result = output.read();
        const long long actual = (long long)(ap_int<64>)result.data;
        if (actual != expected[index]) {
            std::cerr << "Mismatch output " << index << ": actual=" << actual
                      << " expected=" << expected[index] << std::endl;
            ++failures;
        }
        if ((index == 15) != (bool)result.last) {
            std::cerr << "Incorrect TLAST at output " << index << std::endl;
            ++failures;
        }
    }
    if (failures == 0)
        std::cout << "PASS: 4-sample/clock covariance core, all 16 outputs."
                  << std::endl;
    return failures;
}
