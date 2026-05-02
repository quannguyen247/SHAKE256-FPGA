# SHAKE256 FPGA / IP Core

SHAKE256 FPGA is a synthesizable Verilog RTL implementation of the SHAKE256 sponge construction and the Keccak-f[1600] permutation. It is delivered as an IP-style core with a verification environment and a Python vector generator.

The repository is organized as an out-of-context (OOC) Vivado project, so it is intended for standalone RTL synthesis, simulation, and integration into a larger system. It is not a board-ready design with a complete board-specific wrapper and pinout.

## Key Facts

- Top design: [Implementation/rtl/modules/shake256_sponge.v](Implementation/rtl/modules/shake256_sponge.v)
- Top testbench: [Implementation/testbench/tb_shake256_top.v](Implementation/testbench/tb_shake256_top.v)
- Vector generator: [Implementation/vectors/test_vectors.py](Implementation/vectors/test_vectors.py)
- Vivado version: 2025.2.1 (64-bit)
- Target part in the project: `xc7a100tcsg324-1`
- Synthesis mode: out-of-context (OOC)
- Verification: the current regression flow has been run successfully in both behavioral simulation and post-implementation timing simulation

## Project Status

This repository provides an IP core for SHAKE256 research, verification, and reuse. It intentionally does not ship with:

- a production board wrapper
- board-specific pinout constraints
- a ready-to-program bitstream for a particular FPGA board

The constraint file [Implementation/constraints/shake256.xdc](Implementation/constraints/shake256.xdc) currently defines a 5 ns clock and switching-activity assumptions for analysis. It is not a board pinout file.

## Directory Layout

- [Implementation/rtl/modules/](Implementation/rtl/modules/) - core RTL modules
- [Implementation/rtl/utils/](Implementation/rtl/utils/) - shared Verilog defines and helper functions
- [Implementation/testbench/](Implementation/testbench/) - top-level testbench and simulation logs
- [Implementation/vectors/](Implementation/vectors/) - vector generator and generated test files
- [Implementation/constraints/](Implementation/constraints/) - Vivado XDC constraints
- [Implementation/SHAKE256.xpr](Implementation/SHAKE256.xpr) - Vivado project file
- [Implementation/SHAKE256.runs/](Implementation/SHAKE256.runs/) - synthesis and implementation runs
- [Implementation/SHAKE256.sim/](Implementation/SHAKE256.sim/) - simulation outputs

## RTL Architecture

### `shake256_sponge.v`

The top design module [Implementation/rtl/modules/shake256_sponge.v](Implementation/rtl/modules/shake256_sponge.v) controls the full SHAKE256 flow with a simple handshake interface:

- `start` / `done`
- `input_blocks` / `output_blocks`
- `absorb_valid` / `absorb_ready`
- `squeeze_valid` / `squeeze_ready`
- 1088-bit absorb and squeeze data paths

Internal control flow:

1. `ST_IDLE` - wait for `start`
2. `ST_ABSORB` - accept padded absorb blocks and XOR them into the Keccak state
3. `ST_START` - launch the permutation pipeline
4. `ST_PERMUTE` - run the Keccak-f[1600] permutation
5. `ST_SQUEEZE` - present 1088-bit rate data
6. `ST_DONE` - finish the transaction and return to idle

### `keccak_permutation_pipeline.v`

The Keccak-f[1600] permutation is implemented as a 2-stage pipeline:

- Stage 1: `theta + rho + pi`
- Stage 2: `chi + iota`

This pipeline operates on the full 1600-bit Keccak state, which is 25 lanes of 64 bits each. The design follows the 24-round Keccak-f[1600] schedule.

### `keccak_theta_rho_pi_stage.v`

This stage performs the first three Keccak steps:

- `theta` - column parity and state diffusion
- `rho` - lane rotations
- `pi` - lane permutation

### `keccak_chi_iota_stage.v`

This stage performs the final two Keccak steps:

- `chi` - non-linear row mixing
- `iota` - XOR of the round constant into lane `A[0,0]`

### `shake256_pad_block.v`

The padding helper [Implementation/rtl/modules/shake256_pad_block.v](Implementation/rtl/modules/shake256_pad_block.v) builds SHAKE256 multi-rate padded blocks:

- inserts the `0x1F` domain-separation byte
- sets the final `0x80` bit
- raises `need_block2` when the message fills the full 136-byte rate block

## Test Vector Generation

The vector generator [Implementation/vectors/test_vectors.py](Implementation/vectors/test_vectors.py) uses Python's `hashlib.shake_256` as the reference model.

### How to run

```powershell
python Implementation/vectors/test_vectors.py
python Implementation/vectors/test_vectors.py clear
python Implementation/vectors/test_vectors.py 1000
```

### Script behavior

- No argument: generate the default vector set.
- `clear`: delete generated `tv_*` files in [Implementation/vectors/](Implementation/vectors/), including `tv_all.mem` and `tv_spec.txt`.
- Integer argument `N`: keep the 143 base cases and add random test cases until the total count reaches `N` when `N > 143`.

The default base set contains 143 cases:

- 4 fixed cases
- 2 XOF proof cases
- 137 exhaustive message-length cases covering lengths 0 through 136 bytes

For example, `python Implementation/vectors/test_vectors.py 1000` generates 1000 total cases by appending random cases after the 143 base cases.

### Generated files

- `tv_all.mem` - hex-encoded test data for `$readmemh`
- `tv_spec.txt` - metadata used by the testbench

The metadata file currently records fields such as:

- `tv_count`
- `rate_bytes`
- `max_squeeze_blocks`
- `fixed_cases`
- `xof_proof_cases`
- `exhaustive_length_cases`
- `random_cases`

The testbench reads `tv_spec.txt` to learn how many test cases to execute and uses `tv_all.mem` as the source of expected input and output data.

## Testbench

The top testbench [Implementation/testbench/tb_shake256_top.v](Implementation/testbench/tb_shake256_top.v) instantiates the SHAKE256 sponge core and the padding helper, then executes the generated test vectors one by one.

It:

- instantiates `shake256_sponge`
- instantiates `shake256_pad_block`
- reads `tv_spec.txt` and `tv_all.mem`
- runs each case sequentially
- writes the simulation report to `Implementation/testbench/result.log`

Current verification parameters include:

- `TIMEOUT_CYCLES = 1836` per test case
- `MAX_BUFFER = 1024`
- support for multi-block absorb and multi-block squeeze flows

## Vivado Flow

1. Open [Implementation/SHAKE256.xpr](Implementation/SHAKE256.xpr)
2. Set `tb_shake256_top` as the simulation top
3. Run Behavioral Simulation for functional verification
4. Run Implementation and Post-Implementation Timing Simulation for timing validation

The current Vivado project is configured with:

- Product Version: Vivado 2025.2.1 (64-bit)
- Design top: `shake256_sponge`
- Simulation top: `tb_shake256_top`
- Synthesis mode: `out_of_context`

## Notes

- This repository is IP-style RTL, not a complete board-level design.
- If you want to integrate it into a real FPGA system, you should add your own wrapper, serializer/deserializer, or bus interface.
- The current vector set and testbench are designed for deterministic regression and easy re-run of results.

## License

This project is licensed under the [Apache License 2.0](LICENSE).