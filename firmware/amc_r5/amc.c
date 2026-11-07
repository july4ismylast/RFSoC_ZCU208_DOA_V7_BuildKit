/* Automatic modulation classification on the ZynqMP R5F -- reference port.
 * See amc.h for the contract and V07 section 20 for the architecture.
 *
 * Fixed sizes, bounded loops, one static twiddle table, no malloc. The
 * accumulator is double by default because the host comparison is exact; compile
 * with -DAMC_SINGLE_ACC to get the all-single version the R5F FPU actually runs
 * (it has no double-precision unit), and scripts/amc_port_check.py reports what
 * that costs in labels.
 */

#include "amc.h"
#include "amc_model.h"

#include <math.h>

#ifdef AMC_SINGLE_ACC
typedef float amc_acc;
#else
typedef double amc_acc;
#endif

#ifndef AMC_PI
#define AMC_PI 3.14159265358979323846
#endif

#define AMC_MAX_FFT 2048

static amc_acc cos_table[AMC_MAX_FFT / 2];
static amc_acc sin_table[AMC_MAX_FFT / 2];
static int table_n = 0;

/* ------------------------------------------------------------------ tables */

static int build_tables(int n)
{
    int k;
    if (n <= 0 || n > AMC_MAX_FFT) {
        return -1;
    }
    if (table_n == n) {
        return 0;
    }
    for (k = 0; k < n / 2; ++k) {
        amc_acc angle = (amc_acc)(-2.0 * AMC_PI * (double)k / (double)n);
        cos_table[k] = (amc_acc)cos((double)angle);
        sin_table[k] = (amc_acc)sin((double)angle);
    }
    table_n = n;
    return 0;
}

/* Complex radix-2 FFT, in place, on two arrays. */
static void fft_complex(amc_acc *re, amc_acc *im, int n)
{
    int i, j, k, length;
    if (build_tables(n) != 0) {
        return;                       /* n > AMC_MAX_FFT: caller rejected it */
    }
    j = 0;
    for (i = 1; i < n; ++i) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) {
            j ^= bit;
        }
        j ^= bit;
        if (i < j) {
            amc_acc tr = re[i], ti = im[i];
            re[i] = re[j];
            im[i] = im[j];
            re[j] = tr;
            im[j] = ti;
        }
    }
    for (length = 2; length <= n; length <<= 1) {
        int half = length >> 1;
        int step = n / length;
        for (i = 0; i < n; i += length) {
            for (k = 0; k < half; ++k) {
                amc_acc wr = cos_table[k * step];
                amc_acc wi = sin_table[k * step];
                int a = i + k;
                int b = i + k + half;
                amc_acc tr = wr * re[b] - wi * im[b];
                amc_acc ti = wr * im[b] + wi * re[b];
                re[b] = re[a] - tr;
                im[b] = im[a] - ti;
                re[a] += tr;
                im[a] += ti;
            }
        }
    }
}

/* ---------------------------------------------------------------- features */

int amc_features(const float *re, const float *im, int n, float *features)
{
    static amc_acc amplitude[AMC_MAX_FFT];
    static amc_acc fft_re[AMC_MAX_FFT];
    static amc_acc fft_im[AMC_MAX_FFT];
    static amc_acc phase[AMC_MAX_FFT];
    amc_acc power = 0.0, mean_a = 0.0, mean_a2 = 0.0, mean_a4 = 0.0;
    amc_acc m4r = 0.0, m4i = 0.0, c20r = 0.0, c20i = 0.0;
    amc_acc c40r, c40i, c40, c42, sigma_ap, gamma_max;
    amc_acc step_mean = 0.0, step_var = 0.0, freq_std, spike = 0.0;
    int i, count;

    if (re == 0 || im == 0 || features == 0) {
        return -1;
    }
    if (n < AMC_MIN_SAMPLES || n > AMC_MAX_FFT) {
        return -1;
    }

    /* order-1 and order-2 statistics, then the complex moments */
    for (i = 0; i < n; ++i) {
        amc_acc xr = (amc_acc)re[i];
        amc_acc xi = (amc_acc)im[i];
        amc_acc p2 = xr * xr + xi * xi;
        amc_acc x2r = xr * xr - xi * xi;
        amc_acc x2i = 2.0 * xr * xi;
        amc_acc x4r = x2r * x2r - x2i * x2i;
        amc_acc x4i = 2.0 * x2r * x2i;
        amc_acc a = (amc_acc)sqrt((double)p2);
        power += p2;
        mean_a += a;
        mean_a2 += p2;
        mean_a4 += p2 * p2;
        m4r += x4r;
        m4i += x4i;
        c20r += x2r;
        c20i += x2i;
        amplitude[i] = a;
    }
    power /= (amc_acc)n;
    mean_a /= (amc_acc)n;
    mean_a2 /= (amc_acc)n;
    mean_a4 /= (amc_acc)n;
    m4r /= (amc_acc)n;
    m4i /= (amc_acc)n;
    c20r /= (amc_acc)n;
    c20i /= (amc_acc)n;

    if (power <= 0.0 || mean_a <= 0.0) {
        return -1;
    }

    /* [0] |C40| -- exactly the expression scripts/modulation_clustering.py uses */
    {
        amc_acc n20r = c20r / power;
        amc_acc n20i = c20i / power;
        amc_acc sqr = n20r * n20r - n20i * n20i;
        amc_acc sqi = 2.0 * n20r * n20i;
        c40r = (m4r - 3.0 * sqr) / power;
        c40i = (m4i - 3.0 * sqi) / power;
        c40 = (amc_acc)sqrt((double)(c40r * c40r + c40i * c40i));
    }
    /* [1] C42 = E|x|^4 / (E|x|^2)^2 */
    c42 = mean_a4 / (power * power);

    /* [2] sigma_ap = std(|x|) / mean(|x|) */
    {
        amc_acc var = mean_a2 - mean_a * mean_a;
        if (var < 0.0) {
            var = 0.0;
        }
        sigma_ap = (amc_acc)sqrt((double)var) / mean_a;
    }

    /* [3] gamma_max = max |FFT(a/mean(a) - 1)|^2 / n */
    for (i = 0; i < n; ++i) {
        fft_re[i] = amplitude[i] / mean_a - 1.0;
        fft_im[i] = 0.0;
    }
    fft_complex(fft_re, fft_im, n);
    {
        amc_acc best = 0.0;
        for (i = 0; i < n; ++i) {
            amc_acc value = fft_re[i] * fft_re[i] + fft_im[i] * fft_im[i];
            if (value > best) {
                best = value;
            }
        }
        gamma_max = best / (amc_acc)n;
    }

    /* [4] and [5] from the unwrapped phase increment */
    phase[0] = (amc_acc)atan2((double)im[0], (double)re[0]);
    for (i = 1; i < n; ++i) {
        amc_acc previous = (amc_acc)atan2((double)im[i - 1], (double)re[i - 1]);
        amc_acc delta = (amc_acc)atan2((double)im[i], (double)re[i]) - previous;
        while (delta > AMC_PI) {
            delta -= (amc_acc)(2.0 * AMC_PI);
        }
        while (delta < -AMC_PI) {
            delta += (amc_acc)(2.0 * AMC_PI);
        }
        phase[i] = phase[i - 1] + delta;
    }
    count = n - 1;
    for (i = 1; i < n; ++i) {
        amc_acc step = (phase[i] - phase[i - 1]) / (amc_acc)(2.0 * AMC_PI);
        step_mean += step;
    }
    step_mean /= (amc_acc)count;
    for (i = 1; i < n; ++i) {
        amc_acc step = (phase[i] - phase[i - 1]) / (amc_acc)(2.0 * AMC_PI);
        amc_acc diff = step - step_mean;
        step_var += diff * diff;
        if (fabs((double)(step * (amc_acc)AMC_SPS)) > 0.25) {
            spike += 1.0;
        }
    }
    step_var /= (amc_acc)count;
    freq_std = (amc_acc)sqrt((double)step_var) * (amc_acc)AMC_SPS;
    spike /= (amc_acc)count;

    features[0] = (float)c40;
    features[1] = (float)c42;
    features[2] = (float)sigma_ap;
    features[3] = (float)gamma_max;
    features[4] = (float)freq_std;
    features[5] = (float)spike;
    return 0;
}

int amc_classify(const float *features, float *margin)
{
    int c, f;
    int best = 0;
    double best_distance = 0.0, second = 0.0;

    for (c = 0; c < AMC_CLASSES; ++c) {
        double distance = 0.0;
        for (f = 0; f < AMC_FEATURES; ++f) {
            double z = ((double)features[f] - AMC_CENTRE[f]) / AMC_SPREAD[f];
            double delta = z - AMC_MEANS[c][f];
            distance += delta * delta;
        }
        distance = sqrt(distance);
        if (c == 0 || distance < best_distance) {
            second = best_distance;
            best_distance = distance;
            best = c;
        } else if (distance < second) {
            second = distance;
        }
    }
    if (margin != 0) {
        *margin = (float)(second - best_distance);
    }
    return best;
}

int amc_run(const float *re, const float *im, int n, int *out_class,
            float *out_margin, float *features_out)
{
    float local[AMC_FEATURES];
    int status = amc_features(re, im, n, features_out != 0 ? features_out : local);
    if (status != 0) {
        return status;
    }
    *out_class = amc_classify(features_out != 0 ? features_out : local, out_margin);
    return 0;
}

const char *amc_label(int class_index)
{
    if (class_index < 0 || class_index >= AMC_CLASSES) {
        return "?";
    }
    return AMC_LABELS[class_index];
}
