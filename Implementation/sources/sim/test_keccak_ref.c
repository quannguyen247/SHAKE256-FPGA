// SHAKE256 reference vectors from PQClean's fips202.c implementation.
//
// Build (MinGW/clang):
//   gcc -O2 -std=c11 -o test_keccak_ref test_keccak_ref.c ../../PQClean/common/fips202.c -I../../PQClean/common
//
// Output format is intended for HDL scoreboard comparison.

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "fips202.h"

static void print_hex(const uint8_t *buf, size_t len) {
    size_t i;
    for (i = 0; i < len; i++) {
        printf("%02x", buf[i]);
    }
}

static void to_hex(const uint8_t *buf, size_t len, char *hex) {
    static const char lut[] = "0123456789abcdef";
    size_t i;

    for (i = 0; i < len; i++) {
        hex[2 * i] = lut[(buf[i] >> 4) & 0x0F];
        hex[(2 * i) + 1] = lut[buf[i] & 0x0F];
    }
    hex[2 * len] = '\0';
}

static int run_case(const char *name, const uint8_t *msg, size_t mlen, const char *expected_hex) {
    uint8_t out[32];
    char out_hex[65];
    int pass;

    memset(out, 0, sizeof(out));

    shake256(out, sizeof(out), msg, mlen);
    to_hex(out, sizeof(out), out_hex);
    pass = (strcmp(out_hex, expected_hex) == 0);

    printf("%s\n", name);
    printf("  inlen: %zu bytes\n", mlen);
    printf("  out32: ");
    print_hex(out, sizeof(out));
    printf("\n");
    printf("  expect: %s\n", expected_hex);
    printf("  result: %s\n", pass ? "PASS" : "FAIL");
    printf("\n\n");

    return pass ? 0 : 1;
}

int main(void) {
    static const uint8_t msg_a[] = {0x61};
    static const uint8_t msg_abc[] = {0x61, 0x62, 0x63};
    static const char *exp0 = "46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f";
    static const char *exp1 = "867e2cb04f5a04dcbd592501a5e8fe9ceaafca50255626ca736c138042530ba4";
    static const char *exp2 = "483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739";
    static const char *exp3 = "b7ff4073b3f5a8eabd6e17705ca7f6761a31058f9df781a6a47e3a3063b9d67a";

    uint8_t msg_136[136];
    size_t i;
    int fail_count = 0;

    for (i = 0; i < sizeof(msg_136); i++) {
        msg_136[i] = (uint8_t)i;
    }

    printf("=== SHAKE256 Reference (PQClean fips202.c) ===\n\n");

    fail_count += run_case("Case 0: empty message", NULL, 0, exp0);
    fail_count += run_case("Case 1: single-byte message 'a'", msg_a, sizeof(msg_a), exp1);
    fail_count += run_case("Case 2: message 'abc'", msg_abc, sizeof(msg_abc), exp2);
    fail_count += run_case("Case 3: 136-byte incremental pattern 00..87", msg_136, sizeof(msg_136), exp3);

    if (fail_count == 0) {
        printf("All reference checks PASSED.\n");
        return 0;
    }

    printf("Reference checks FAILED: %d case(s).\n", fail_count);
    return 1;
}
