# Keccak-f[1600] Reference Guide

## 1. Keccak-f[1600] Overview

### State Structure
- **Total bits**: 1600 bits
- **Organized as**: 25 lanes (5×5 grid)
- **Lane width**: 64 bits each
- **Lane indexing**: `[x, y]` where x,y ∈ [0,4]

```
State Layout (5×5×64):
Lane[0,0]  Lane[1,0]  Lane[2,0]  Lane[3,0]  Lane[4,0]
Lane[0,1]  Lane[1,1]  Lane[2,1]  Lane[3,1]  Lane[4,1]
Lane[0,2]  Lane[1,2]  Lane[2,2]  Lane[3,2]  Lane[4,2]
Lane[0,3]  Lane[1,3]  Lane[2,3]  Lane[3,3]  Lane[4,3]
Lane[0,4]  Lane[1,4]  Lane[2,4]  Lane[3,4]  Lane[4,4]
```

### Permutation: 24 Rounds
Each round consists of 5 steps executed sequentially:
1. **θ (Theta)** - Column parity diffusion
2. **ρ (Rho)** - Lane rotation (64-bit rotate)
3. **π (Pi)** - Lane permutation (rearrangement)
4. **χ (Chi)** - Non-linear substitution (Row mixing)
5. **ι (Iota)** - Round constant XOR

---

## 2. Step-by-Step Details

### Step θ (Theta) - Column Parity

**Purpose**: Diffuse column parity throughout state

**Algorithm** (C reference):
```c
// Compute column parities
BCa = A[x, 0] ^ A[x, 1] ^ A[x, 2] ^ A[x, 3] ^ A[x, 4]  // for all x

// Compute theta inputs
Da = BCa[4] ^ ROL(BCa[1], 1)  // for all a
De = BCe[4] ^ ROL(BCe[1], 1)
// ... (apply to all 5 columns)

// XOR theta input to state
A[x, y] = A[x, y] ^ D[x]  // for all x, y
```

**HDL Logic**: 
- 5 parallel XOR trees (5 inputs each)
- 5 parallel 64-bit rotate-left-1 operations
- 25 parallel XOR operations

---

### Step ρ (Rho) - Lane Rotation

**Purpose**: Rotate each lane by fixed offset

**Rotation Offsets** (from specification):
```
Offset[x,y] = ((x + 3y) * (x + 1)) / 2  (for all x,y ∈ [0,4])

Lookup table (precomputed):
[0,0]=0   [1,0]=1   [2,0]=62  [3,0]=28  [4,0]=27
[0,1]=36  [1,1]=44  [2,1]=6   [3,1]=55  [4,1]=20
[0,2]=3   [1,2]=10  [2,2]=43  [3,2]=25  [4,2]=39
[0,3]=41  [1,3]=45  [2,3]=15  [3,3]=21  [4,3]=8
[0,4]=18  [1,4]=2   [2,4]=61  [3,4]=56  [4,4]=14
```

**HDL Logic**:
```verilog
// Parallel rotation for all 25 lanes
rotated_lane[i] = lane[i] <<< rotation_offset[i]
```

---

### Step π (Pi) - Lane Permutation

**Purpose**: Rearrange lane positions

**Permutation Rule**:
```
A'[x, y] = A[x + 3y, x]   (mod 5)
```

**Lookup table (Lane rearrangement)**:
```
Position mapping:
(0,0) -> (0,0)   (1,0) -> (1,0)   (2,0) -> (2,0) ...
(0,1) -> (3,1)   (1,1) -> (4,1)   (2,1) -> (0,1) ...
```

**HDL Logic**:
```verilog
// 25 parallel mux selecting from 25 input lanes
output_lane[new_pos] = input_lane[old_pos]
```

---

### Step χ (Chi) - Non-linear Row Mixing

**Purpose**: Non-linear substitution on each row

**Algorithm** (for each row y):
```c
for (int y = 0; y < 5; y++) {
    for (int x = 0; x < 5; x++) {
        A'[x,y] = A[x,y] ^ ((~A[x+1,y]) & A[x+2,y])  // (mod 5)
    }
}
```

**HDL Logic** (per 64-bit lane, parallel):
```verilog
// For each bit position in the 64-bit lane
chi_out[x] = lane[x] ^ ((~lane[x+1]) & lane[x+2])  // x mod 5
```

---

### Step ι (Iota) - Round Constant XOR

**Purpose**: Break symmetry, add round-dependent entropy

**24 Round Constants** (64-bit each):
```
KeccakF_RoundConstants[24] = {
    0x0000000000000001, 0x0000000000008082,
    0x800000000000808a, 0x8000000080008000,
    0x000000000000808b, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009,
    0x000000000000008a, 0x0000000000000088,
    0x0000000080008009, 0x000000008000000a,
    0x000000008000808b, 0x800000000000008b,
    0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080,
    0x000000000000800a, 0x800000008000000a,
    0x8000000080008081, 0x8000000000008080,
    0x0000000080000001, 0x8000000080008008
}
```

**Algorithm**:
```c
A[0,0] ^= KeccakF_RoundConstants[round]  // Only lane [0,0]
```

**HDL Logic**:
```verilog
state[0] = state[0] ^ RC[round]  // XOR with round constant
```

---

## 3. SHAKE256 Sponge Construction

### Absorbing Phase
```
Input: message (variable length)
Rate r = 136 bytes (1088 bits)  // SHAKE256 rate
Capacity c = 512 bits (64 bytes)

For each 136-byte block:
  1. Pad message block to 136 bytes (SHAKE256 padding)
  2. XOR block with state[0:1087]
  3. Apply Keccak-f[1600] permutation
```

### Squeezing Phase
```
Output: digest (variable length, default 256 bits)

While output_length > 0:
  1. Extract state[0:min(rate, output_length)]
  2. If more output needed, apply permutation again
```

### SHA-3 Padding Rule (SHAKE256)
```
- Append byte 0x1F
- Pad with 0x00 to fill block (except last byte)
- Set bit 7 of last byte to 1 (becomes 0x80)
```

---

## 4. Architecture Options for FPGA

### Option A: Fully Parallel (All 24 rounds unrolled)
```
Latency: 1 cycle/permutation
Resources: 24× per-round logic
Throughput: MAX (1 Permutation per clock)
```

### Option B: Pipeline (4 stages, 6 rounds each)
```
Latency: 4 cycles/permutation
Resources: 4× stage logic (shared hardware)
Throughput: ~1 permutation per 1-2 clocks
```

### Option C: Iterative (Single round per cycle)
```
Latency: 24 cycles/permutation
Resources: MIN (1 round logic + counter)
Throughput: 1 permutation per 24 clocks
```

**RECOMMENDATION for Zynq 7000**: Option B (Pipeline 4 stages)
- **Clock**: ~100 MHz
- **Throughput**: ~6-12 Gbps
- **Resources**: ~15-25% LUT

---

## 5. HDL Implementation Checklist

- [ ] Define 1600-bit state register
- [ ] Implement 64-bit ROL (rotate left) operations
- [ ] Implement θ step (5 column parities + diffusion)
- [ ] Implement ρ step (lookup + rotate for 25 lanes)
- [ ] Implement π step (permutation mux)
- [ ] Implement χ step (non-linear mixing per row)
- [ ] Implement ι step (add round constant)
- [ ] Combine into single Keccak round module
- [ ] Instantiate 24 rounds (or pipeline registers)
- [ ] Add absorb/squeeze control logic (FSM)
- [ ] Add AXI-Lite interface wrapper

---

## 6. Key Numbers for Implementation

| Parameter | Value |
|-----------|-------|
| State width | 1600 bits (25 × 64-bit lanes) |
| Rate (SHAKE256) | 1088 bits (136 bytes) |
| Capacity | 512 bits |
| Rounds | 24 |
| Rotation offsets | 25 (lookup table) |
| Round constants | 24 (array) |
| Lane width | 64 bits |

---

## 7. Reference Files in Project

| File | Content |
|------|---------|
| `fips202.c` | Keccak-f[1600] implementation |
| `fips202.h` | API declarations |
| `sp800-185.c` | SHAKE256 wrapper logic |
| `KeccakF_RoundConstants[]` | RC table in fips202.c:64 |

