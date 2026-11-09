/* Host harness for firmware/amc_r5: reads a vector file, prints what the
 * firmware core decided for every burst, so scripts/amc_port_check.py can
 * compare it with the Python model.
 *
 * File layout (little endian, written by scripts/amc_export.py):
 *   int32 magic 0x414D4331 ("AMC1"), int32 count, int32 n_samples,
 *   int32 n_features,
 *   count * n_samples * 2 float32   (re, im interleaved per sample),
 *   count * n_features     float32  (the Python features, for comparison),
 *   count                  int32    (the true class index)
 *
 * stdout: one line per burst,
 *   index truth firmware margin f0 f1 f2 f3 f4 f5
 * The Python side re-derives its own label from the reference features in the
 * same file, so the comparison is firmware-against-model, not firmware-against-
 * itself.
 */

#include "amc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAGIC 0x414D4331

int main(int argc, char **argv)
{
    FILE *handle;
    int header[4];
    int count, n, nf, i, k;
    float *samples;
    float *reference;
    int *truth;

    if (argc < 2) {
        fprintf(stderr, "usage: %s vectors.bin\n", argv[0]);
        return 2;
    }
    handle = fopen(argv[1], "rb");
    if (handle == NULL) {
        fprintf(stderr, "cannot open %s\n", argv[1]);
        return 2;
    }
    if (fread(header, sizeof(int), 4, handle) != 4 || header[0] != MAGIC) {
        fprintf(stderr, "bad header\n");
        fclose(handle);
        return 2;
    }
    count = header[1];
    n = header[2];
    nf = header[3];
    if (count <= 0 || n < AMC_MIN_SAMPLES || n > AMC_MAX_SAMPLES
            || nf != AMC_FEATURES) {
        fprintf(stderr, "bad sizes: count=%d n=%d nf=%d\n", count, n, nf);
        fclose(handle);
        return 2;
    }
    samples = (float *)malloc(sizeof(float) * (size_t)count * (size_t)n * 2);
    reference = (float *)malloc(sizeof(float) * (size_t)count * (size_t)nf);
    truth = (int *)malloc(sizeof(int) * (size_t)count);
    if (samples == NULL || reference == NULL || truth == NULL) {
        fprintf(stderr, "out of memory\n");
        fclose(handle);
        return 2;
    }
    if (fread(samples, sizeof(float), (size_t)count * (size_t)n * 2, handle)
            != (size_t)count * (size_t)n * 2) {
        fprintf(stderr, "short sample block\n");
        fclose(handle);
        return 2;
    }
    if (fread(reference, sizeof(float), (size_t)count * (size_t)nf, handle)
            != (size_t)count * (size_t)nf) {
        fprintf(stderr, "short feature block\n");
        fclose(handle);
        return 2;
    }
    if (fread(truth, sizeof(int), (size_t)count, handle) != (size_t)count) {
        fprintf(stderr, "short truth block\n");
        fclose(handle);
        return 2;
    }
    fclose(handle);

    for (i = 0; i < count; ++i) {
        float features[AMC_FEATURES];
        int decided;
        float margin = 0.0f;
        const float *burst = samples + (size_t)i * (size_t)n * 2;
        float re[AMC_MAX_SAMPLES];
        float im[AMC_MAX_SAMPLES];
        for (k = 0; k < n; ++k) {
            re[k] = burst[2 * k];
            im[k] = burst[2 * k + 1];
        }
        if (amc_run(re, im, n, &decided, &margin, features) != 0) {
            printf("%d FAIL\n", i);
            continue;
        }
        printf("%d %d %d %.6f", i, truth[i], decided, (double)margin);
        for (k = 0; k < AMC_FEATURES; ++k) {
            printf(" %.6f", (double)features[k]);
        }
        printf("\n");
    }
    free(samples);
    free(reference);
    free(truth);
    return 0;
}
