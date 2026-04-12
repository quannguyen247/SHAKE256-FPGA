# SHAKE256 HDL Roadmap (PQClean-aligned)

## 1. Is PQClean a good reference for SHAKE256?

Short answer: YES.

- `PQClean/common/fips202.c` is a widely used software reference for Keccak-f[1600], SHAKE128, SHAKE256, and SHA3 variants.
- The code follows FIPS 202 parameters for SHAKE256:
  - rate = 136 bytes (1088 bits)
  - capacity = 64 bytes (512 bits)
  - domain separation suffix = 0x1F
- For hardware implementation, this is an excellent behavioral reference (golden model), especially for:
  - round constants
  - rotation offsets
  - absorb/squeeze flow
  - pad10*1 finalization with SHAKE suffix

Important: PQClean is software-oriented C code. HDL should map behavior, not line-by-line style.

## 2. Current implementation status in this repository

### Implemented and usable now

- Keccak round datapath in `sources/rtl/modules/keccak_round.v`
  - theta, rho, pi, chi, iota all present
- 6-round stage wrapper in `sources/rtl/modules/keccak_stage6.v`
- 4-stage pipeline (24 rounds total intent) in `sources/rtl/modules/keccak_permutation_pipeline.v`
- Sponge control skeleton in `sources/rtl/modules/shake256_sponge.v`
- Basic simulation files in `sources/sim/`

### Fixed in this update

- Corrected stage round index scheduling in `keccak_stage6.v`
  - now uses base round = stage_idx * 6
- Corrected canonical rho offsets in `keccak_round.v`
- Improved sponge permutation launch behavior in `shake256_sponge.v`
  - one launch pulse per permutation request (no repeated enqueue)
- Rewrote C reference vector utility in `sources/sim/test_keccak_ref.c`
  - now calls `shake256(...)` API correctly

### Still missing for a production SHAKE256 core

- Byte/bitstream input packer (unaligned writes -> 64-bit lanes)
- Explicit padding block builder in hardware (suffix 0x1F + pad10*1)
- Full verification scoreboard:
  - compare HDL output blocks against C golden vectors automatically
- Interface wrapper (AXI-Stream or AXI-Lite + FIFO)
- Throughput/resource report artifacts in `reports/`

## 3. C-to-HDL mapping guide

Use this mapping during implementation and presentation:

- `KeccakF1600_StatePermute` (C)
  -> `keccak_round` + `keccak_stage6` + `keccak_permutation_pipeline` (HDL)

- `keccak_absorb` (C)
  -> Sponge absorb FSM + rate XOR into state[1087:0] (HDL)

- `keccak_squeezeblocks` (C)
  -> Sponge squeeze FSM + output state[1087:0], permute between blocks (HDL)

- `shake256` one-shot API (C)
  -> top wrapper FSM: init, absorb blocks, finalize/pad, squeeze requested output length

## 4. Recommended folder organization (for thesis clarity)

Current structure is already a good start. For clearer growth and defense presentation, use this target layout:

- `Implementation/sources/rtl/core/`
  - pure Keccak datapath (`keccak_round`, stage wrappers, iterative/pipeline variants)
- `Implementation/sources/rtl/sponge/`
  - absorb, pad, squeeze controllers
- `Implementation/sources/rtl/interface/`
  - AXI/FIFO/register wrappers
- `Implementation/sources/rtl/top/`
  - integration top modules
- `Implementation/sources/sim/tb/`
  - testbenches only
- `Implementation/sources/sim/golden/`
  - C test-vector generators, known-answer vectors
- `Implementation/scripts/`
  - build, run_sim, lint, synth scripts
- `Implementation/reports/`
  - timing, utilization, throughput, verification summaries
- `Implementation/docs/`
  - architecture and verification documents

## 5. Beginner-friendly implementation flow

### Step 1: Lock conventions

- Define lane ordering: lane index = x + 5*y
- Define endianness: little-endian byte to 64-bit lane (same as `load64` in C)
- Define handshake style: valid/ready semantics before writing RTL

### Step 2: Verify one round only

- Build small testbench for one known input state and one round index
- Match lane outputs against software model
- Confirm RC and rho offsets first (most common bug source)

### Step 3: Verify full 24-round permutation

- Feed one state, wait for output, compare all 25 lanes against C model
- Test at least:
  - all-zero state
  - random state
  - patterned state

### Step 4: Add sponge absorb path

- XOR full 136-byte blocks into rate area
- Run permutation after each absorbed block
- Keep capacity part untouched except through permutation

### Step 5: Add SHAKE256 padding

- On final block, append suffix 0x1F
- Apply pad10*1 by setting MSB of last rate byte (byte 135 bit 7)
- Process final padded block through permutation

### Step 6: Add squeeze path

- Output 136-byte blocks from rate area
- If more output needed, permute then output next block
- Support non-multiple output lengths (tail bytes)

### Step 7: Build automated verification

- Use C utility to generate vectors (`test_keccak_ref.c`)
- Build self-checking testbench with pass/fail summary
- Keep regression list and expected hashes in files

### Step 8: Synthesis and report

- Record LUT/FF/BRAM/Fmax
- Compute throughput:
  - throughput ~= (rate_bits * fclk) / cycles_per_permutation
- Compare iterative vs pipeline architecture tradeoff

## 6. Suggested thesis presentation story

Use this sequence in slides/demo:

1. Problem and standard requirements (FIPS 202 SHAKE256)
2. C golden model baseline (PQClean)
3. HDL architecture choice (iterative vs 4-stage pipeline)
4. Module decomposition and signal-level flow
5. Verification strategy and vector matching
6. Synthesis results and tradeoffs
7. Remaining work and next optimization targets

## 7. External references worth citing

- FIPS 202 (NIST SHA-3 standard)
- Keccak team specification summary: https://keccak.team/keccak_specs_summary.html
- Keccak reference paper/spec: https://keccak.team/files/Keccak-reference-3.0.pdf
- OpenTitan KMAC/SHA3 hardware docs (for architecture ideas):
  - https://opentitan.org/book/hw/ip/kmac/doc/theory_of_operation.html
