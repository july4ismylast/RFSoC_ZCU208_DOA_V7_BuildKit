// -----------------------------------------------------------------------------
// Vitis HLS C-simulation testbench for phase_interf_4ch.
//
// The expected values are produced by pir::FrameAccumulator -- the same
// tool-independent core that `make host-check` verifies bit-exactly with g++.
// The test therefore compares the *kernel* (ap_int datapath, AXI packing) with
// the *core* (plain int64), which is the pair of implementations that could
// diverge.
//
// Frames exercised:
//   1. identity calibration, 4 beats (16 samples), deterministic samples
//   2. non-unity calibration, 1024 beats (4096 samples, the production frame)
//   3. a known phase step on the y and z pairs, to re-prove the sign convention
// -----------------------------------------------------------------------------
#include "phase_interf_4ch.hpp"
#include "phase_interf_core.hpp"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace {

int failures = 0;

void packBeat(axis512_t& beat, const std::int16_t real[4][4], const std::int16_t imag[4][4]) {
    beat.data = 0;
    beat.keep = -1;
    beat.strb = -1;
    beat.last = 1;
    for (int lane = 0; lane < 4; ++lane) {
        for (int channel = 0; channel < 4; ++channel) {
            const int word = lane * 4 + channel;
            ap_uint<32> packed = 0;
            packed.range(15, 0) = (ap_uint<16>)(ap_int<16>)real[lane][channel];
            packed.range(31, 16) = (ap_uint<16>)(ap_int<16>)imag[lane][channel];
            beat.data.range(32 * word + 31, 32 * word) = packed;
        }
    }
}

struct FrameResult {
    std::int64_t accumulators[16];
    std::int16_t phases[6];
    std::uint16_t tag;
};

FrameResult runFrame(const std::vector<std::vector<std::int16_t>>& realSamples,  // [channel][sample]
                     const std::vector<std::vector<std::int16_t>>& imagSamples,
                     int frameSamples,
                     const pir::CalCoefficient cal[4],
                     std::uint16_t tag,
                     bool verify) {
    const int beats = (frameSamples + 3) / 4;

    hls::stream<axis512_t> input;
    hls::stream<axis64_t> accumulators;
    hls::stream<axis128_t> phases;

    // --- reference: the host-verified core --------------------------------
    pir::FrameAccumulator reference;
    for (int beat = 0; beat < beats; ++beat) {
        std::int16_t real[4][4];
        std::int16_t imag[4][4];
        axis512_t packedBeat;
        for (int lane = 0; lane < 4; ++lane) {
            for (int channel = 0; channel < 4; ++channel) {
                const int index = beat * 4 + lane;
                real[lane][channel] = realSamples[channel][index];
                imag[lane][channel] = imagSamples[channel][index];
            }
        }
        packBeat(packedBeat, real, imag);
        input.write(packedBeat);
        for (int lane = 0; lane < 4; ++lane) {
            std::int16_t realLane[4], imagLane[4];
            for (int channel = 0; channel < 4; ++channel) {
                realLane[channel] = real[lane][channel];
                imagLane[channel] = imag[lane][channel];
            }
            reference.addLane(cal, realLane, imagLane);
        }
    }

    const ap_uint<32> calPack[4] = {
        ((ap_uint<32>)(ap_uint<16>)(ap_int<16>)cal[0].im) << 16 |
            (ap_uint<16>)(ap_int<16>)cal[0].re,
        ((ap_uint<32>)(ap_uint<16>)(ap_int<16>)cal[1].im) << 16 |
            (ap_uint<16>)(ap_int<16>)cal[1].re,
        ((ap_uint<32>)(ap_uint<16>)(ap_int<16>)cal[2].im) << 16 |
            (ap_uint<16>)(ap_int<16>)cal[2].re,
        ((ap_uint<32>)(ap_uint<16>)(ap_int<16>)cal[3].im) << 16 |
            (ap_uint<16>)(ap_int<16>)cal[3].re,
    };

    phase_interf_4ch(input, accumulators, phases,
                     calPack[0], calPack[1], calPack[2], calPack[3],
                     (ap_uint<16>)frameSamples, (ap_uint<16>)tag);

    FrameResult result{};
    for (int index = 0; index < 16; ++index) {
        axis64_t word = accumulators.read();
        result.accumulators[index] = static_cast<std::int64_t>(word.data.to_uint64());
        if (verify && index == 15 && word.last.to_uint() == 0) {
            std::printf("FAIL accumulator word 15 missing TLAST\n");
            ++failures;
        }
    }
    axis128_t phaseWord = phases.read();
    for (int pair = 0; pair < 6; ++pair) {
        ap_int<16> bits = phaseWord.data.range(16 * pair + 15, 16 * pair);
        result.phases[pair] = static_cast<std::int16_t>(bits.to_int());
    }
    result.tag = (std::uint16_t)phaseWord.data.range(111, 96);

    if (verify) {
        for (int channel = 0; channel < 4; ++channel) {
            const std::int64_t expected = reference.power(channel);
            if (result.accumulators[channel] != expected) {
                std::printf("FAIL power[%d]: %lld vs %lld\n", channel,
                            (long long)result.accumulators[channel], (long long)expected);
                ++failures;
            }
        }
        for (int pair = 0; pair < 6; ++pair) {
            const std::int64_t expectedRe = reference.crossReal(pair);
            const std::int64_t expectedIm = reference.crossImag(pair);
            if (result.accumulators[4 + pair] != expectedRe) {
                std::printf("FAIL crossReal[%d]: %lld vs %lld\n", pair,
                            (long long)result.accumulators[4 + pair], (long long)expectedRe);
                ++failures;
            }
            if (result.accumulators[10 + pair] != expectedIm) {
                std::printf("FAIL crossImag[%d]: %lld vs %lld\n", pair,
                            (long long)result.accumulators[10 + pair], (long long)expectedIm);
                ++failures;
            }
            const double referencePhase = std::atan2((double)expectedIm, (double)expectedRe);
            const double gotPhase = (double)result.phases[pair] / 8192.0;
            const double lsb = std::fabs(gotPhase - referencePhase) * 8192.0;
            if (lsb > 3.0) {
                std::printf("FAIL phase[%d]: %.5f vs %.5f rad (%.1f LSB)\n", pair,
                            gotPhase, referencePhase, lsb);
                ++failures;
            }
        }
        if (result.tag != tag) {
            std::printf("FAIL frame tag: %u vs %u\n", result.tag, tag);
            ++failures;
        }
    }
    return result;
}

}  // namespace

int main() {
    pir::CalCoefficient unity[4];
    for (int c = 0; c < 4; ++c) { unity[c].re = 1 << 14; unity[c].im = 0; }

    // ---- frame 1: 4 beats, deterministic, unity calibration ---------------
    {
        const int frameSamples = 16;
        std::vector<std::vector<std::int16_t>> realSamples(4, std::vector<std::int16_t>(frameSamples));
        std::vector<std::vector<std::int16_t>> imagSamples(4, std::vector<std::int16_t>(frameSamples));
        for (int channel = 0; channel < 4; ++channel) {
            for (int index = 0; index < frameSamples; ++index) {
                realSamples[channel][index] =
                    (std::int16_t)(1000 * (channel + 1) + 7 * index - 300);
                imagSamples[channel][index] =
                    (std::int16_t)(-400 * (channel + 1) + 3 * index + 50);
            }
        }
        runFrame(realSamples, imagSamples, frameSamples, unity, 7, true);
        std::printf("  frame 1 (16 samples, unity cal): accumulators and phases match core\n");
    }

    // ---- frame 2: production frame with non-unity calibration -------------
    {
        const int frameSamples = 4096;
        std::vector<std::vector<std::int16_t>> realSamples(4, std::vector<std::int16_t>(frameSamples));
        std::vector<std::vector<std::int16_t>> imagSamples(4, std::vector<std::int16_t>(frameSamples));
        unsigned state = 0x12345678u;
        for (int channel = 0; channel < 4; ++channel) {
            for (int index = 0; index < frameSamples; ++index) {
                state = state * 1664525u + 1013904223u;
                realSamples[channel][index] = (std::int16_t)((state >> 8) & 0xFFFF);
                imagSamples[channel][index] = (std::int16_t)((state >> 16) & 0xFFFF);
            }
        }
        pir::CalCoefficient cal[4] = {
            {(std::int16_t)(1 << 14), 0},
            {(std::int16_t)(1 << 13), (std::int16_t)(1 << 12)},
            {(std::int16_t)((1 << 14) - 300), (std::int16_t)(-900)},
            {(std::int16_t)(1 << 14), (std::int16_t)(1 << 11)},
        };
        runFrame(realSamples, imagSamples, frameSamples, cal, 4096, true);
        std::printf("  frame 2 (4096 samples, calibrated): accumulators and phases match core\n");
    }

    // ---- frame 3: physical sign convention, az > 0 and el < 0 -------------
    {
        const int frameSamples = 64;
        std::vector<std::vector<std::int16_t>> realSamples(4, std::vector<std::int16_t>(frameSamples));
        std::vector<std::vector<std::int16_t>> imagSamples(4, std::vector<std::int16_t>(frameSamples));
        const double f = 3.5e9;
        const double spacing = 0.025;
        const double lightSpeed = 299792458.0;
        const double azimuth = 20.0 * 3.14159265358979 / 180.0;
        const double elevation = -12.0 * 3.14159265358979 / 180.0;
        const double uy = std::cos(elevation) * std::sin(azimuth);
        const double uz = std::sin(elevation);
        const double half = spacing / 2.0;
        const double position[4][2] = {{-half, -half}, {+half, -half}, {-half, +half}, {+half, +half}};
        const double amplitude = 6000.0;
        for (int index = 0; index < frameSamples; ++index) {
            for (int channel = 0; channel < 4; ++channel) {
                const double projection = position[channel][0] * uy + position[channel][1] * uz;
                const double phase = -2.0 * 3.14159265358979 * f * projection / lightSpeed;
                realSamples[channel][index] = (std::int16_t)std::lround(amplitude * std::cos(phase));
                imagSamples[channel][index] = (std::int16_t)std::lround(amplitude * std::sin(phase));
            }
        }
        FrameResult result = runFrame(realSamples, imagSamples, frameSamples, unity, 3, true);
        const double expectedAz = -2.0 * 3.14159265358979 * f * spacing * uy / lightSpeed;
        const double expectedEl = -2.0 * 3.14159265358979 * f * spacing * uz / lightSpeed;
        const double azPhase = (double)result.phases[0] / 8192.0;
        const double elPhase = (double)result.phases[1] / 8192.0;
        std::printf("  frame 3 sign check: az %+.4f (expect %+.4f), el %+.4f (expect %+.4f)\n",
                    azPhase, expectedAz, elPhase, expectedEl);
        if (!(azPhase < 0.0 && std::fabs(azPhase - expectedAz) < 3.0 / 8192.0) ||
            !(elPhase > 0.0 && std::fabs(elPhase - expectedEl) < 3.0 / 8192.0)) {
            std::printf("FAIL sign convention on the az/el baselines\n");
            ++failures;
        }
    }

    if (failures == 0) {
        std::printf("PASS: phase_interf_4ch C-simulation (accumulators + CORDIC phases)\n");
        return 0;
    }
    std::printf("FAIL: %d check(s) failed\n", failures);
    return 1;
}
