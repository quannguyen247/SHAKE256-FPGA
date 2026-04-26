*** SHAKE256 FPGA/IP Core — Professional README ***

**Author:** Nguyen Dong Quan

This repository provides a synthesizable Verilog implementation of the SHAKE256 sponge construction and the Keccak-f[1600] permutation, delivered as an IP core together with a verification environment. The codebase is intended for FPGA prototyping and research; it is provided as RTL/IP rather than a board-ready top-level design.

IMPORTANT: project status
-------------------------
- This repository exposes an IP-style core (module `shake256_sponge` and supporting modules under `Implementation/rtl/modules/`).
- The project does NOT include a production top-level wrapper for a specific board, and it does NOT include a board-specific XDC (pinout/clock constraints) required to generate a ready-to-program bitstream. Integrators must provide a top-level wrapper and XDC for their target board.

Repository layout
-----------------
Implementation/
- constraints/        — place board XDCs here (not provided)
- rtl/
  - modules/          — keccak permutation stages, sponge and padding modules
  - utils/            — defines and helper headers (`keccak_defs.vh`, `keccak_funcs.vh`)
- testbench/          — `tb_shake256_top.v` and supporting test files
- vectors/            — `test_vectors.py` and generated `.mem` files

What this repo contains
-----------------------
- Synthesizable Verilog RTL for the SHAKE256 core and supporting modules:
  - `shake256_sponge.v` — sponge controller with absorb/squeeze handshake (1088-bit rate)
  - `keccak_permutation_pipeline.v` — permutation pipeline wrapper
  - Stage modules (Theta/Rho/Pi/Chi/Iota) under `Implementation/rtl/modules/`
- Verification environment and KAT vector generator (`Implementation/vectors/test_vectors.py`).

What is intentionally not provided
----------------------------------
- Board-level top wrapper to adapt the 1088-bit datapath to physical pins
- Board-specific XDC constraints for any particular Artix-7 development board
- A pre-built bitstream or board programming scripts

Quick start (verification)
--------------------------
Prerequisites: Vivado (for xsim/synthesis) and Python 3.x.

1) Generate known-answer test vectors:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python Implementation\vectors\test_vectors.py
```

2) Run RTL simulation (Vivado xsim recommended):

- Open `Implementation/SHAKE256.xpr` in Vivado
- Set `tb_shake256_top.v` as the simulation top module
- Run Behavioral Simulation; the testbench writes results to `testbench/result_log.txt`.

Integration guidance — turning the IP into a board design
-------------------------------------------------------
Because the sponge rate is wide (1088 bits), you must provide a top-level wrapper when targeting real hardware:

• Serializer / Deserializer wrapper (bare FPGA I/O):
- Shift data in/out over a narrower external bus (for example 32/64-bit) and assemble/disassemble 1088-bit blocks.
- Provide control registers (start/done) and a small handshake FIFO between the serializer and the IP core.

• AXI4-Stream / AXI4-Lite wrapper (SoC integration):
- Wrap the core with an AXI4-Stream sink/source for data and an AXI4‑Lite register interface for control/status.

• Example integration checklist:
  1. Implement a serializer or AXI wrapper module.
  2. Create a top-level that instantiates the wrapper and `shake256_sponge`.
  3. Add board XDC: clocks, I/O pin assignments, IOSTANDARD and placement constraints.
  4. Validate with simulation (functional) before synthesis.

Module summary (short)
----------------------
`shake256_sponge` — main IP integration point:
- `clk, rst_n`
- `absorb_block_valid` (in), `absorb_block_data` (in, [1087:0])
- `absorb_block_ready` (out)
- `squeeze_data_valid` (out), `squeeze_data` (out, [1087:0])
- `squeeze_data_ready` (in), `start`/`done`, `num_input_blocks`, `num_output_blocks`.

`keccak_permutation_pipeline` — permutation engine:
- `clk, rst_n, in_valid, state_in[1599:0], out_valid, state_out[1599:0]`.

Verification & recommended workflows
-----------------------------------
- Use the included testbench and generated KAT vectors for deterministic functional verification.
- Export SAIF/VCD from simulation and import into Vivado Power Analysis for realistic power estimates.
- Add a CI/regression script to run the vector generator and a simulator, report PASS/FAIL automatically.

Known limitations and notes
--------------------------
- This repository provides an IP core, not a board-ready design. Integrators must create an appropriate wrapper and XDC for target hardware.
- The current testbench assumes synchronous handshake semantics; when integrating, ensure that upstream interfaces meet the core's setup/hold requirements.

License and references
----------------------
- See `LICENSE` for terms.
- Reference: FIPS 202 (SHA-3 family), Keccak specification and academic literature.

Contributions and contact
-------------------------
Issues and pull requests are welcome. For non-public queries, open an issue describing the topic and we can coordinate further.
