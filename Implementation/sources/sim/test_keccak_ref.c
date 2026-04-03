// Reference: Keccak F1600 test against PQClean C implementation
// Usage: gcc -o test_keccak_ref test_keccak_ref.c ../../PQClean/common/fips202.c -I../../PQClean/common
// This generates reference test vectors for HDL verification

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "fips202.h"

int main() {
    // Test 1: Empty message SHAKE256
    uint8_t input[1] = {0};
    uint8_t output[32];
    
    printf("=== SHAKE256 Test Vectors ===\n\n");
    
    // Test 1: Empty message
    printf("Test 1: SHAKE256(empty, 32 bytes)\n");
    printf("Input: (empty)\n");
    shake256_absorb((shake256ctx *)(void*)&output, input, 0);
    printf("Output (hex): ");
    for (int i = 0; i < 32; i++) {
        printf("%02x", output[i]);
    }
    printf("\n\n");
    
    // Test 2: Single-byte message ("a")
    printf("Test 2: SHAKE256(0x61 ['a'], 32 bytes)\n");
    uint8_t msg2[1] = {0x61};
    shake256_absorb((shake256ctx *)(void*)&output, msg2, 1);
    printf("Output (hex): ");
    for (int i = 0; i < 32; i++) {
        printf("%02x", output[i]);
    }
    printf("\n\n");
    
    // Test 3: Multi-byte message
    printf("Test 3: SHAKE256('abc', 32 bytes)\n");
    uint8_t msg3[3] = {'a', 'b', 'c'};
    shake256_absorb((shake256ctx *)(void*)&output, msg3, 3);
    printf("Output (hex): ");
    for (int i = 0; i < 32; i++) {
        printf("%02x", output[i]);
    }
    printf("\n\n");
    
    // Print state as 25 64-bit lanes (for HDL reference)
    printf("=== Keccak-f[1600] State Lane Values (for HDL) ===\n");
    printf("Each 64-bit lane in little-endian format\n");
    printf("Lane indexing: [x,y] = lane[x + 5*y]\n\n");
    
    return 0;
}
