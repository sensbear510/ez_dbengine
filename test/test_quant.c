#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "ez_quant.h"

/* Helper function: Compute Cosine Similarity between two vectors */
static f32 compute_cosine_similarity(const f32 *a, const f32 *b, u32 dim) {
    f64 dot = 0.0, norm_a = 0.0, norm_b = 0.0;
    for (u32 i = 0; i < dim; i++) {
        dot += (f64)a[i] * (f64)b[i];
        norm_a += (f64)a[i] * (f64)a[i];
        norm_b += (f64)b[i] * (f64)b[i];
    }
    return (f32)(dot / (sqrt(norm_a) * sqrt(norm_b) + 1e-9));
}

/* Helper function: Compute Mean Squared Error (MSE) */
static f32 compute_mse(const f32 *a, const f32 *b, u32 dim) {
    f64 sum_err = 0.0;
    for (u32 i = 0; i < dim; i++) {
        f64 diff = (f64)a[i] - (f64)b[i];
        sum_err += diff * diff;
    }
    return (f32)(sum_err / dim);
}

int main(void) {
    u32 dim = 1024; /* 1024-dimensional feature vector */
    f32 raw_vector[1024];
    f32 decomp_vector[1024];
    u8  packed_buffer[512]; /* 1024 / 2 = 512 Bytes */
    f32 min_val = 0.0f, max_val = 0.0f;

    printf("===================================================\n");
    printf("  ez_dbengine: TurboQuants Vector Module Test\n");
    printf("===================================================\n\n");

    /* 1. Generate synthetic 1024-dim AI feature vector */
    for (u32 i = 0; i < dim; i++) {
        raw_vector[i] = (f32)(sin(i * 0.1) + cos(i * 0.03) * 0.5);
    }

    u32 raw_bytes = dim * sizeof(f32); /* 4096 Bytes */
    u32 compressed_bytes = sizeof(packed_buffer) + sizeof(f32) * 2; /* 512B + 8B = 520 Bytes */

    printf("1. Input Vector Dimension : %u (float32)\n", dim);
    printf("   - Raw Memory Size      : %u Bytes\n", raw_bytes);
    printf("   - Target Compressed    : %u Bytes (4-bit + Min/Max Header)\n", compressed_bytes);
    printf("   - Compression Ratio    : %.2f : 1 (%.1f%% Space Saved!)\n\n",
           (f32)raw_bytes / compressed_bytes,
           (1.0f - (f32)compressed_bytes / raw_bytes) * 100.0f);

    /* 2. Execute direct 4-bit affine compression */
    EZ_STATUS st1 = ez_quant_compress_f32_4bit(raw_vector, dim, packed_buffer, &min_val, &max_val);
    if (st1 != EZ_SUCCESS) {
        printf("[ERROR] Compression failed with code: %d\n", st1);
        return 1;
    }

    /* 3. Execute direct 4-bit affine decompression */
    EZ_STATUS st2 = ez_quant_decompress_4bit_f32(packed_buffer, min_val, max_val, dim, decomp_vector);
    if (st2 != EZ_SUCCESS) {
        printf("[ERROR] Decompression failed with code: %d\n", st2);
        return 1;
    }

    /* 4. Quality and fidelity evaluation */
    f32 cos_sim = compute_cosine_similarity(raw_vector, decomp_vector, dim);
    f32 mse = compute_mse(raw_vector, decomp_vector, dim);

    printf("2. Quality Assessment:\n");
    printf("   - Min Boundary Scalar  : %.6f\n", min_val);
    printf("   - Max Boundary Scalar  : %.6f\n", max_val);
    printf("   - Mean Squared Error   : %.6f (MSE)\n", mse);
    printf("   - Cosine Similarity    : %.6f (%.2f%% Fidelity)\n\n", 
           cos_sim, cos_sim * 100.0f);

    if (cos_sim >= 0.98f) {
        printf("[PASS] TurboQuants algorithm verification SUCCESSFUL!\n");
    } else {
        printf("[WARN] Fidelity below threshold.\n");
    }

    return 0;
}