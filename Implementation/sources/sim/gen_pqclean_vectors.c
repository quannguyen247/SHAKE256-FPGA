// Generate deterministic SHAKE256 test vectors using PQClean fips202.c.
//
// Output files (under -o <dir>, default: generated):
//   - tv_meta.vh
//   - tv_msg_len.mem
//   - tv_num_out_blocks.mem
//   - tv_msg_block.mem
//   - tv_exp_out_block0.mem
//   - tv_exp_out_block1.mem
//   - tv_manifest.txt

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#endif

#include "fips202.h"

#define SHAKE_RATE_BYTES 136u
#define MAX_OUT_BLOCKS 2u
#define DEFAULT_RANDOM_CASES 256u

typedef struct {
    uint8_t msg_len;
    uint8_t num_out_blocks;
    uint8_t msg_block[SHAKE_RATE_BYTES];
    uint8_t out_bytes[MAX_OUT_BLOCKS * SHAKE_RATE_BYTES];
} vector_case_t;

static uint32_t xorshift32(uint32_t *state) {
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

static int ensure_directory(const char *path) {
#ifdef _WIN32
    if (_mkdir(path) == 0 || errno == EEXIST) {
        return 0;
    }
#else
    if (mkdir(path, 0755) == 0 || errno == EEXIST) {
        return 0;
    }
#endif
    return -1;
}

static void write_hex_reversed(FILE *fp, const uint8_t *bytes, size_t len) {
    size_t i;
    for (i = len; i > 0; i--) {
        fprintf(fp, "%02x", bytes[i - 1]);
    }
    fprintf(fp, "\n");
}

static void add_case(vector_case_t *cases,
                     size_t idx,
                     const uint8_t *msg,
                     size_t mlen,
                     uint8_t out_blocks) {
    vector_case_t *tv = &cases[idx];
    size_t out_len = (size_t)out_blocks * SHAKE_RATE_BYTES;

    memset(tv, 0, sizeof(*tv));
    tv->msg_len = (uint8_t)mlen;
    tv->num_out_blocks = out_blocks;

    if (mlen > 0 && msg != NULL) {
        memcpy(tv->msg_block, msg, mlen);
    }

    shake256(tv->out_bytes, out_len, msg, mlen);
}

static uint8_t pick_out_blocks(size_t index) {
    return (index & 1u) ? 2u : 1u;
}

static void usage(const char *argv0) {
    fprintf(stderr, "Usage: %s [-o output_dir] [-r random_cases]\n", argv0);
}

int main(int argc, char **argv) {
    const char *out_dir = "generated";
    size_t random_cases = DEFAULT_RANDOM_CASES;
    size_t deterministic_cases = 4u + (SHAKE_RATE_BYTES + 1u);
    size_t total_cases;
    vector_case_t *cases = NULL;
    uint8_t msg_buf[SHAKE_RATE_BYTES];
    uint32_t seed = 0x1A2B3C4Du;
    size_t idx = 0;
    size_t i;
    size_t out_two_count = 0;
    char path[512];
    FILE *fp_meta = NULL;
    FILE *fp_len = NULL;
    FILE *fp_num_out = NULL;
    FILE *fp_msg = NULL;
    FILE *fp_out0 = NULL;
    FILE *fp_out1 = NULL;
    FILE *fp_manifest = NULL;

    for (i = 1; i < (size_t)argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            if ((i + 1u) >= (size_t)argc) {
                usage(argv[0]);
                return 2;
            }
            out_dir = argv[++i];
        } else if (strcmp(argv[i], "-r") == 0) {
            char *endptr = NULL;
            unsigned long parsed;
            if ((i + 1u) >= (size_t)argc) {
                usage(argv[0]);
                return 2;
            }
            parsed = strtoul(argv[++i], &endptr, 10);
            if (endptr == NULL || *endptr != '\0') {
                fprintf(stderr, "Invalid random case count: %s\n", argv[i]);
                return 2;
            }
            random_cases = (size_t)parsed;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    total_cases = deterministic_cases + random_cases;
    if (total_cases == 0u) {
        fprintf(stderr, "No vectors to generate.\n");
        return 2;
    }

    if (ensure_directory(out_dir) != 0) {
        fprintf(stderr, "Cannot create output directory %s (errno=%d)\n", out_dir, errno);
        return 1;
    }

    cases = (vector_case_t *)calloc(total_cases, sizeof(vector_case_t));
    if (cases == NULL) {
        fprintf(stderr, "Out of memory allocating %zu vectors\n", total_cases);
        return 1;
    }

    // Fixed known-answer style messages.
    add_case(cases, idx++, NULL, 0u, 1u);

    msg_buf[0] = 0x61u;  // "a"
    add_case(cases, idx++, msg_buf, 1u, 2u);

    msg_buf[0] = 0x61u;  // "abc"
    msg_buf[1] = 0x62u;
    msg_buf[2] = 0x63u;
    add_case(cases, idx++, msg_buf, 3u, 1u);

    for (i = 0; i < SHAKE_RATE_BYTES; i++) {
        msg_buf[i] = (uint8_t)i;  // 00..87
    }
    add_case(cases, idx++, msg_buf, SHAKE_RATE_BYTES, 2u);

    // Deterministic exhaustive lengths [0..136].
    for (i = 0; i <= SHAKE_RATE_BYTES; i++) {
        size_t j;
        uint8_t out_blocks = pick_out_blocks(idx);
        for (j = 0; j < i; j++) {
            msg_buf[j] = (uint8_t)((j * 29u + i * 7u) & 0xFFu);
        }
        add_case(cases, idx++, msg_buf, i, out_blocks);
    }

    // Deterministic pseudo-random message corpus.
    for (i = 0; i < random_cases; i++) {
        size_t j;
        size_t mlen = (size_t)(xorshift32(&seed) % (SHAKE_RATE_BYTES + 1u));
        uint8_t out_blocks = (xorshift32(&seed) & 1u) ? 2u : 1u;

        for (j = 0; j < mlen; j++) {
            msg_buf[j] = (uint8_t)(xorshift32(&seed) & 0xFFu);
        }
        add_case(cases, idx++, msg_buf, mlen, out_blocks);
    }

    if (idx != total_cases) {
        fprintf(stderr, "Internal vector count mismatch: idx=%zu total=%zu\n", idx, total_cases);
        free(cases);
        return 1;
    }

    for (i = 0; i < total_cases; i++) {
        if (cases[i].num_out_blocks == 2u) {
            out_two_count++;
        }
    }

    snprintf(path, sizeof(path), "%s/tv_meta.vh", out_dir);
    fp_meta = fopen(path, "w");
    if (fp_meta == NULL) {
        fprintf(stderr, "Cannot write %s\n", path);
        free(cases);
        return 1;
    }
    fprintf(fp_meta, "`ifndef TV_META_VH\n");
    fprintf(fp_meta, "`define TV_META_VH\n");
    fprintf(fp_meta, "`define TV_COUNT %zu\n", total_cases);
    fprintf(fp_meta, "`endif\n");
    fclose(fp_meta);

    snprintf(path, sizeof(path), "%s/tv_msg_len.mem", out_dir);
    fp_len = fopen(path, "w");
    snprintf(path, sizeof(path), "%s/tv_num_out_blocks.mem", out_dir);
    fp_num_out = fopen(path, "w");
    snprintf(path, sizeof(path), "%s/tv_msg_block.mem", out_dir);
    fp_msg = fopen(path, "w");
    snprintf(path, sizeof(path), "%s/tv_exp_out_block0.mem", out_dir);
    fp_out0 = fopen(path, "w");
    snprintf(path, sizeof(path), "%s/tv_exp_out_block1.mem", out_dir);
    fp_out1 = fopen(path, "w");

    if (fp_len == NULL || fp_num_out == NULL || fp_msg == NULL || fp_out0 == NULL || fp_out1 == NULL) {
        fprintf(stderr, "Cannot open one or more mem output files in %s\n", out_dir);
        if (fp_len) fclose(fp_len);
        if (fp_num_out) fclose(fp_num_out);
        if (fp_msg) fclose(fp_msg);
        if (fp_out0) fclose(fp_out0);
        if (fp_out1) fclose(fp_out1);
        free(cases);
        return 1;
    }

    for (i = 0; i < total_cases; i++) {
        fprintf(fp_len, "%02x\n", cases[i].msg_len);
        fprintf(fp_num_out, "%02x\n", cases[i].num_out_blocks);
        write_hex_reversed(fp_msg, cases[i].msg_block, SHAKE_RATE_BYTES);
        write_hex_reversed(fp_out0, &cases[i].out_bytes[0], SHAKE_RATE_BYTES);
        write_hex_reversed(fp_out1, &cases[i].out_bytes[SHAKE_RATE_BYTES], SHAKE_RATE_BYTES);
    }

    fclose(fp_len);
    fclose(fp_num_out);
    fclose(fp_msg);
    fclose(fp_out0);
    fclose(fp_out1);

    snprintf(path, sizeof(path), "%s/tv_manifest.txt", out_dir);
    fp_manifest = fopen(path, "w");
    if (fp_manifest == NULL) {
        fprintf(stderr, "Cannot write %s\n", path);
        free(cases);
        return 1;
    }

    fprintf(fp_manifest, "SHAKE256 vector corpus generated from PQClean fips202.c\n");
    fprintf(fp_manifest, "rate_bytes=%u\n", SHAKE_RATE_BYTES);
    fprintf(fp_manifest, "total_cases=%zu\n", total_cases);
    fprintf(fp_manifest, "fixed_cases=4\n");
    fprintf(fp_manifest, "exhaustive_length_cases=%u\n", SHAKE_RATE_BYTES + 1u);
    fprintf(fp_manifest, "random_cases=%zu\n", random_cases);
    fprintf(fp_manifest, "num_out_blocks_eq_1=%zu\n", total_cases - out_two_count);
    fprintf(fp_manifest, "num_out_blocks_eq_2=%zu\n", out_two_count);
    fprintf(fp_manifest, "rng_seed_initial=0x1A2B3C4D\n");
    fclose(fp_manifest);

    printf("Generated %zu vectors in %s\n", total_cases, out_dir);
    printf("  num_out_blocks=1: %zu\n", total_cases - out_two_count);
    printf("  num_out_blocks=2: %zu\n", out_two_count);

    free(cases);
    return 0;
}
