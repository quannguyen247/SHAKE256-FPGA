# SHAKE256 HDL QoR Review and Repipeline Notes (2026-04-11)

## 1) Observed symptom
- Reported synthesis footprint: about 80000 LUT and 10000 FF (LUT:FF around 8:1).
- This ratio strongly indicates large combinational replication and deep logic cones.

## 2) Root-cause analysis
- Previous permutation core used 4 pipeline stages x 6 rounds per stage.
- Total instantiated datapath was still 24 Keccak rounds in hardware, not time-multiplexed.
- Each stage had 6-round combinational depth, so critical path crossed multiple theta/rho-pi/chi/iota blocks.
- Resulting behavior:
  - Very high LUT usage (24x round logic replication).
  - Lower FF growth than LUT because registers existed mostly at stage boundaries.
  - Timing closure pressure due to long combinational path per stage.

## 3) Implemented architecture change
- Replaced permutation implementation with iterative 1-round-per-cycle architecture in:
  - `Implementation/sources/rtl/modules/keccak_permutation_pipeline.v`
- New behavior:
  - Single `keccak_round` instance reused over 24 cycles.
  - Internal state register + round counter + busy flag + done pulse.
  - Input handshake remains `in_valid` pulse; output remains `out_valid` pulse.
- Expected QoR impact:
  - Major LUT reduction versus unrolled 24-round datapath.
  - Critical path reduced to one Keccak round combinational depth.
  - FF use now centered on 1600-bit state registers and control logic.

## 4) Verification updates
- Existing permutation TB was strengthened:
  - `Implementation/sources/sim/tb_shake256_pipeline.v`
  - Added known zero-state lane[0] check and latency window check for iterative operation.
- Added end-to-end sponge KAT TB:
  - `Implementation/sources/sim/tb_shake256_sponge.v`
  - Covers 4 vectors (empty, "a", "abc", 136-byte pattern).
  - First 32 output bytes compare against PQClean known-answer values.
  - Includes full-block padding case requiring two absorb blocks.

## 5) Reference alignment
- C reference remains passing for all 4 SHAKE256 vectors via:
  - `Implementation/sources/sim/test_keccak_ref.c`
- Outputs match expected values from PQClean `fips202.c` test vectors.

## 6) Current limitations
- HDL simulator commands are still unavailable in current shell PATH (`xvlog`, `xelab`, `xsim`, `iverilog`, `verilator` not found).
- Because of toolchain availability, HDL run-time simulation and fresh synthesis numbers are not included in this report.

## 7) Recommended next synthesis experiments
1. Run post-change synthesis with same constraints and top to quantify LUT/FF/Fmax delta.
2. If throughput target is higher, evaluate controlled unroll factors (e.g., 2 or 4 rounds/cycle) as tradeoff points.
3. Add an explicit `in_ready` signal for permutation core if upstream ever drives back-to-back requests.
4. Keep current KAT sponge TB as mandatory regression gate before every QoR iteration.
