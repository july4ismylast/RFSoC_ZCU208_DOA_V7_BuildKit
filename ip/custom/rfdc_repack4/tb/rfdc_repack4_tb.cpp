#include "rfdc_repack4.hpp"

#include <cstdint>
#include <iostream>

// Bit-exact packing test: every 16-bit lane carries a unique, recognisable
// pattern (beat, channel, I/Q, lane), so any lane swap, I/Q swap, channel
// swap or beat slip fails loudly instead of silently degrading coherence.
static std::uint16_t pattern(int beat, int channel, int is_q, int lane) {
    return static_cast<std::uint16_t>(
        0x8000u | (static_cast<unsigned>(beat & 0x3F) << 9) |
        (static_cast<unsigned>(channel & 0x3) << 7) |
        (static_cast<unsigned>(is_q & 0x1) << 6) |
        static_cast<unsigned>(lane & 0x3F));
}

int main() {
    rfdc_axis128_t in_i[4];
    rfdc_axis128_t in_q[4];
    rfdc_axis256_t out[4];
    rfdc_axis128_t* in_i_p[4] = {&in_i[0], &in_i[1], &in_i[2], &in_i[3]};
    rfdc_axis128_t* in_q_p[4] = {&in_q[0], &in_q[1], &in_q[2], &in_q[3]};
    rfdc_axis256_t* out_p[4] = {&out[0], &out[1], &out[2], &out[3]};

    const int beats = 5;
    int failures = 0;

    for (int beat = 0; beat < beats; ++beat) {
        for (int channel = 0; channel < 4; ++channel) {
            ap_uint<128> i_beat = 0;
            ap_uint<128> q_beat = 0;
            for (int lane = 0; lane < 8; ++lane) {
                i_beat.range(16 * lane + 15, 16 * lane) =
                    pattern(beat, channel, 0, lane);
                q_beat.range(16 * lane + 15, 16 * lane) =
                    pattern(beat, channel, 1, lane);
            }
            in_i[channel].write(i_beat);
            in_q[channel].write(q_beat);
        }

        rfdc_repack4(*in_i_p[0], *in_q_p[0], *in_i_p[1], *in_q_p[1],
                     *in_i_p[2], *in_q_p[2], *in_i_p[3], *in_q_p[3],
                     *out_p[0], *out_p[1], *out_p[2], *out_p[3]);

        for (int channel = 0; channel < 4; ++channel) {
            if (out[channel].empty()) {
                std::cerr << "beat " << beat << " channel " << channel
                          << ": missing output beat" << std::endl;
                ++failures;
                continue;
            }
            const ap_uint<256> packed = out[channel].read();
            for (int lane = 0; lane < 8; ++lane) {
                const std::uint16_t got_i = static_cast<std::uint16_t>(
                    packed.range(32 * lane + 15, 32 * lane));
                const std::uint16_t got_q = static_cast<std::uint16_t>(
                    packed.range(32 * lane + 31, 32 * lane + 16));
                const std::uint16_t exp_i = pattern(beat, channel, 0, lane);
                const std::uint16_t exp_q = pattern(beat, channel, 1, lane);
                if (got_i != exp_i || got_q != exp_q) {
                    std::cerr << "beat " << beat << " channel " << channel
                              << " lane " << lane << ": got I=0x" << std::hex
                              << got_i << " Q=0x" << got_q << " expected I=0x"
                              << exp_i << " Q=0x" << exp_q << std::dec
                              << std::endl;
                    ++failures;
                }
            }
        }
    }

    for (int channel = 0; channel < 4; ++channel) {
        if (!out[channel].empty()) {
            std::cerr << "channel " << channel << ": extra output beat"
                      << std::endl;
            ++failures;
        }
    }

    if (failures == 0) {
        std::cout << "PASS: rfdc_repack4 SSR-8 I/Q packing, "
                  << beats << " beats x 4 channels x 8 lanes" << std::endl;
    }
    return failures;
}
