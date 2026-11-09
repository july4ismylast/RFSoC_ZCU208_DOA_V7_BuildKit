/* Automatic modulation classification on the ZynqMP R5F -- reference port.
 *
 * This file is the host-verifiable twin of two things:
 *   - scripts/modulation_clustering.py, the model measured in V07 section 18;
 *   - matlab_v7/classify_modulation.m, the MATLAB source that Embedded Coder
 *     turns into the library the R5 links (V07 section 20).
 *
 * All three must return the same label for the same burst. scripts/amc_port_check.py
 * generates the vectors, compiles this file on the host, and compares the labels
 * and the six features against the Python model; that comparison is the evidence.
 *
 * No dynamic allocation, no libm beyond sqrt/atan2/exp-free arithmetic, fixed
 * sizes, every loop bounded by AMC_MAX_SAMPLES. That is what the R5 needs and
 * what Embedded Coder needs to prove.
 *
 * Author: V07 build kit. Status: host-verified (G8a), NOT run on the RPU.
 */

#ifndef AMC_R5_AMC_H
#define AMC_R5_AMC_H

#ifdef __cplusplus
extern "C" {
#endif

#define AMC_FEATURES 6
#define AMC_CLASSES 5
#define AMC_MAX_SAMPLES 2048
#define AMC_MIN_SAMPLES 32

/* Sample rate of the burst, in samples per symbol (V07 sections 18, 20). */
#ifndef AMC_SPS
#define AMC_SPS 4
#endif

typedef enum {
    AMC_BPSK = 0,
    AMC_QPSK = 1,
    AMC_8PSK = 2,
    AMC_16QAM = 3,
    AMC_4FSK = 4
} amc_class;

/* Six features, in the order of V07 table 18.2:
 *   [0] |C40|  [1] C42  [2] sigma_ap  [3] gamma_max  [4] freq_std  [5] spike
 * Returns 0 on success, -1 if n is outside [AMC_MIN_SAMPLES, AMC_MAX_SAMPLES].
 */
int amc_features(const float *re, const float *im, int n, float *features);

/* Nearest class mean on the standardised features. Returns the class index and
 * writes the margin (runner-up distance minus best distance) to *margin. */
int amc_classify(const float *features, float *margin);

/* Convenience: features + classification in one call. */
int amc_run(const float *re, const float *im, int n, int *out_class,
            float *out_margin, float *features_out);

const char *amc_label(int class_index);

#ifdef __cplusplus
}
#endif

#endif /* AMC_R5_AMC_H */
