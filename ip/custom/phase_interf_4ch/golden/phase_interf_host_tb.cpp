// -----------------------------------------------------------------------------
// phase_interf_host_tb.cpp -- host (g++) test of the exact production core.
//
// Compiles src/phase_interf_core.hpp with no Xilinx headers so the arithmetic
// checked here is bit-identical to what Vitis HLS synthesises.  This is the
// G1 gate of V07_PHASE_INTERFEROMETRY.md section 8.
//
//   make host-check
// -----------------------------------------------------------------------------
#include "phase_interf_core.hpp"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <random>

namespace {

int failures = 0;

void check(bool condition, const char* what) {
    if (!condition) {
        std::printf("FAIL %s\n", what);
        ++failures;
    }
}

double q13_to_rad(std::int16_t value) { return static_cast<double>(value) / 8192.0; }

// ---------------------------------------------------------------------------
// 1. CORDIC table is the true arctangent table
// ---------------------------------------------------------------------------
void testTable() {
    for (int i = 0; i < pir::kCordicIters; ++i) {
        const double expected = std::atan(std::ldexp(1.0, -i)) * 1073741824.0;  // Q2.30
        const long rounded = std::lround(expected);
        if (std::llabs(rounded - pir::kAtanQ30[i]) > 1) {
            std::printf("FAIL table[%d]: %d vs %ld\n", i, pir::kAtanQ30[i], rounded);
            ++failures;
        }
    }
    std::printf("  cordic table: 16 entries match atan(2^-i)*2^30 within 1 LSB\n");
}

// ---------------------------------------------------------------------------
// 2. CORDIC atan2 accuracy: max error <= 2 LSB of Q3.13 over 0..2pi
// ---------------------------------------------------------------------------
void testCordicAccuracy() {
    const int kSteps = 4096;
    int worstLsb = 0;
    double worstPhi = 0.0;
    for (int step = 0; step < kSteps; ++step) {
        const double phi = -M_PI + 2.0 * M_PI * step / kSteps;
        // sweep several magnitudes, including the 48-bit accumulator range
        for (int magnitude = 1; magnitude <= (1 << 24); magnitude <<= 4) {
            const double x = std::cos(phi) * magnitude;
            const double y = std::sin(phi) * magnitude;
            const std::int16_t got = pir::atan2_q13(static_cast<std::int64_t>(std::llround(y)),
                                                    static_cast<std::int64_t>(std::llround(x)));
            const double reference = std::atan2(std::llround(y), std::llround(x));
            const int lsb = static_cast<int>(std::llround(std::fabs(q13_to_rad(got) - reference) * 8192.0));
            if (lsb > worstLsb) { worstLsb = lsb; worstPhi = phi; }
        }
    }
    std::printf("  cordic atan2: worst error %d LSB (Q3.13) at phi=%.3f rad over %d angles\n",
                worstLsb, worstPhi, kSteps);
    check(worstLsb <= 2, "cordic atan2 error <= 2 LSB");
}

// ---------------------------------------------------------------------------
// 3. quadrant coverage and exact axis cases
// ---------------------------------------------------------------------------
void testQuadrants() {
    const std::int64_t r = 1 << 20;
    const double cases[8][3] = {  // {y, x, expected rad}
        {0, r, 0.0}, {r, 0, M_PI / 2}, {0, -r, M_PI}, {-r, 0, -M_PI / 2},
        {r, r, M_PI / 4}, {-r, r, -M_PI / 4}, {r, -r, 3 * M_PI / 4}, {-r, -r, -3 * M_PI / 4},
    };
    for (const auto& test : cases) {
        const std::int16_t got = pir::atan2_q13(static_cast<std::int64_t>(test[0]),
                                                static_cast<std::int64_t>(test[1]));
        const int lsb = static_cast<int>(std::llround(std::fabs(q13_to_rad(got) - test[2]) * 8192.0));
        if (lsb > 3) {
            std::printf("FAIL quadrant y=%.0f x=%.0f: got %.4f want %.4f rad\n",
                        test[0], test[1], q13_to_rad(got), test[2]);
            ++failures;
        }
    }
    std::printf("  quadrants: 8 axis/diagonal cases within 3 LSB\n");
}

// ---------------------------------------------------------------------------
// 4. Cross-spectrum sign convention (must match doa_covariance_4ch_v4)
//
//    Physically, A_n = exp(-j*2*pi*f*(p_n . u)/c).  For a target at positive uy,
//    channel 2 lags channel 1, so the accumulated S_ba = X_b*conj(X_a) has a
//    NEGATIVE phase.  The test feeds the exact per-channel phasors of a target
//    at az = +20 deg, el = -12 deg (so uy > 0 but uz < 0, which makes one
//    baseline phase negative and the other positive) and requires
//
//        phase(baseline 0) = -2*pi*f*d*uy/c  < 0
//        phase(baseline 1) = -2*pi*f*d*uz/c  > 0
//
//    If this test is "fixed" by flipping a sign, the PS would report mirrored
//    angles together with estimate_doa_from_covariance_v7.m.
// ---------------------------------------------------------------------------
void testSignConvention() {
    pir::CalCoefficient unity[pir::kChannels];
    for (int c = 0; c < pir::kChannels; ++c) { unity[c].re = 1 << 14; unity[c].im = 0; }

    const double f = 3.5e9;
    const double spacing = 0.025;
    const double lightSpeed = 299792458.0;
    const double azimuth = 20.0 * M_PI / 180.0;
    const double elevation = -12.0 * M_PI / 180.0;
    const double uy = std::cos(elevation) * std::sin(azimuth);   // > 0
    const double uz = std::sin(elevation);                       // < 0

    // positions are +-spacing/2 in y and z (same 2x2 as the MATLAB reference)
    const double half = spacing / 2.0;
    const double position[4][2] = {{-half, -half}, {+half, -half}, {-half, +half}, {+half, +half}};
    const double amplitude = 7000.0;

    pir::FrameAccumulator frame;
    for (int lane = 0; lane < 64; ++lane) {
        std::int16_t real[pir::kChannels];
        std::int16_t imag[pir::kChannels];
        for (int c = 0; c < pir::kChannels; ++c) {
            const double projection = position[c][0] * uy + position[c][1] * uz;
            const double phase = -2.0 * M_PI * f * projection / lightSpeed;
            real[c] = static_cast<std::int16_t>(std::lround(amplitude * std::cos(phase)));
            imag[c] = static_cast<std::int16_t>(std::lround(amplitude * std::sin(phase)));
        }
        frame.addLane(unity, real, imag);
    }

    std::int16_t phases[pir::kBaselines];
    frame.phases(phases);
    const double expectedAz = -2.0 * M_PI * f * spacing * uy / lightSpeed;
    const double expectedEl = -2.0 * M_PI * f * spacing * uz / lightSpeed;
    const double azPhase = q13_to_rad(phases[0]);
    const double elPhase = q13_to_rad(phases[1]);
    std::printf("  sign convention: az %+.4f rad (expect %+.4f), el %+.4f rad (expect %+.4f)\n",
                azPhase, expectedAz, elPhase, expectedEl);
    check(azPhase < 0.0 && std::fabs(azPhase - expectedAz) < 3.0 / 8192.0,
          "az baseline phase negative and equal to -2*pi*f*d*uy/c");
    check(elPhase > 0.0 && std::fabs(elPhase - expectedEl) < 3.0 / 8192.0,
          "el baseline phase positive and equal to -2*pi*f*d*uz/c");
}

// ---------------------------------------------------------------------------
// 5. Frame accumulation against an independent double-precision reference
// ---------------------------------------------------------------------------
void testAccumulation() {
    std::mt19937 rng(20261106);
    std::uniform_int_distribution<int> sample(-32768, 32767);
    std::uniform_int_distribution<int> coeff(-(1 << 15), (1 << 15) - 1);

    pir::CalCoefficient cal[pir::kChannels];
    for (int c = 0; c < pir::kChannels; ++c) {
        cal[c].re = static_cast<std::int16_t>(coeff(rng));
        cal[c].im = static_cast<std::int16_t>(coeff(rng));
    }

    const int kBeats = 1024;                       // 4096 samples per channel
    pir::FrameAccumulator frame;
    double refPower[pir::kChannels] = {0, 0, 0, 0};
    double refRe[pir::kBaselines] = {0, 0, 0, 0, 0, 0};
    double refIm[pir::kBaselines] = {0, 0, 0, 0, 0, 0};

    for (int beat = 0; beat < kBeats; ++beat) {
        std::int16_t real[pir::kChannels];
        std::int16_t imag[pir::kChannels];
        for (int c = 0; c < pir::kChannels; ++c) {
            real[c] = static_cast<std::int16_t>(sample(rng));
            imag[c] = static_cast<std::int16_t>(sample(rng));
        }
        frame.addLane(cal, real, imag);

        double re[pir::kChannels];
        double im[pir::kChannels];
        for (int c = 0; c < pir::kChannels; ++c) {
            const double pr = static_cast<double>(real[c]) * cal[c].re -
                              static_cast<double>(imag[c]) * cal[c].im;
            const double pi = static_cast<double>(real[c]) * cal[c].im +
                              static_cast<double>(imag[c]) * cal[c].re;
            // integer >>14 truncation, reproduced exactly
            re[c] = std::floor(pr / 16384.0);
            im[c] = std::floor(pi / 16384.0);
            refPower[c] += re[c] * re[c] + im[c] * im[c];
        }
        for (int p = 0; p < pir::kBaselines; ++p) {
            const int a = pir::kFirst[p];
            const int b = pir::kSecond[p];
            // same product order as the core and doa_covariance_4ch_v4:
            // S_ba = X_b * conj(X_a)
            refRe[p] += re[b] * re[a] + im[b] * im[a];
            refIm[p] += im[b] * re[a] - re[b] * im[a];
        }
    }

    int worst = 0;
    for (int c = 0; c < pir::kChannels; ++c) {
        const double delta = std::fabs(static_cast<double>(frame.power(c)) - refPower[c]);
        if (delta > 0.5) { std::printf("FAIL power[%d] delta %.1f\n", c, delta); ++failures; }
        worst = delta > worst ? static_cast<int>(delta) : worst;
    }
    for (int p = 0; p < pir::kBaselines; ++p) {
        const double dr = std::fabs(static_cast<double>(frame.crossReal(p)) - refRe[p]);
        const double di = std::fabs(static_cast<double>(frame.crossImag(p)) - refIm[p]);
        if (dr > 0.5 || di > 0.5) {
            std::printf("FAIL cross[%d] delta re %.1f im %.1f\n", p, dr, di);
            ++failures;
        }
    }
    std::printf("  accumulation: 4 powers + 6 cross-spectra match the double reference\n");

    std::int16_t phases[pir::kBaselines];
    frame.phases(phases);
    int worstLsb = 0;
    for (int p = 0; p < pir::kBaselines; ++p) {
        const double reference = std::atan2(refIm[p], refRe[p]);
        const int lsb = static_cast<int>(std::llround(std::fabs(q13_to_rad(phases[p]) - reference) * 8192.0));
        worstLsb = lsb > worstLsb ? lsb : worstLsb;
    }
    std::printf("  frame phases: worst error %d LSB vs double-precision atan2\n", worstLsb);
    check(worstLsb <= 3, "frame phase error <= 3 LSB");
}

// ---------------------------------------------------------------------------
// 6. Accumulator width claim (int64 is enough for the documented worst case)
// ---------------------------------------------------------------------------
void testWidth() {
    const int bits = pir::FrameAccumulator::worstCaseBits(4096);
    std::printf("  accumulator width: worst case %d bits for 4096 samples -> int64 ok\n", bits);
    check(bits <= 63, "worst-case accumulator fits in 64 bits");

    // and prove it empirically with the largest legal inputs
    pir::CalCoefficient cal[pir::kChannels];
    for (int c = 0; c < pir::kChannels; ++c) { cal[c].re = 32767; cal[c].im = 32767; }
    pir::FrameAccumulator frame;
    std::int16_t real[pir::kChannels];
    std::int16_t imag[pir::kChannels];
    for (int c = 0; c < pir::kChannels; ++c) { real[c] = -32768; imag[c] = -32768; }
    for (int beat = 0; beat < 1024; ++beat) { frame.addLane(cal, real, imag); }
    const double maxPower = static_cast<double>(frame.power(0));
    std::printf("  saturation probe: power = %.3e (%.1f bits, max legal input, 4096 samples)\n",
                maxPower, std::log2(maxPower));
    check(maxPower > 0.0, "extreme input does not wrap negative");
}

}  // namespace

int main() {
    std::printf("PHASE_INTERF_4CH HOST CORE TEST (bit-exact with the HLS kernel)\n");
    testTable();
    testCordicAccuracy();
    testQuadrants();
    testSignConvention();
    testAccumulation();
    testWidth();
    if (failures == 0) {
        std::printf("PASS: phase_interf_core (CORDIC, sign convention, accumulation, width)\n");
        return 0;
    }
    std::printf("FAIL: %d check(s) failed\n", failures);
    return 1;
}
