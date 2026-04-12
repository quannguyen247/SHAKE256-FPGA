# Compile and Simulation Status (2026-04-11)

## Environment checks

- GCC found: `C:\msys64\ucrt64\bin\gcc.exe`
- Vivado tools in PATH: not found (`xvlog`, `xelab`, `xsim`)
- Alternative simulator in PATH: not found (`iverilog`, `vvp`)

## C reference build/run (SUCCESS)

Command context: `Implementation/sources/sim`

Build:

- `gcc -O2 -std=c11 -Wall -Wextra -o test_keccak_ref.exe test_keccak_ref.c ../../../PQClean/common/fips202.c -I../../../PQClean/common`

Run output:

- Case 0 (empty, 32 bytes):
  - `46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f`
- Case 1 (`"a"`, 32 bytes):
  - `867e2cb04f5a04dcbd592501a5e8fe9ceaafca50255626ca736c138042530ba4`
- Case 2 (`"abc"`, 32 bytes):
  - `483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739`
- Case 3 (`00..87`, 136-byte message, 32 bytes out):
  - `b7ff4073b3f5a8eabd6e17705ca7f6761a31058f9df781a6a47e3a3063b9d67a`

## HDL simulation attempt (BLOCKED)

Command context: `Implementation/SHAKE256.sim/sim_1/behav/xsim`

- `compile.bat` failed: `xvlog` not recognized
- `elaborate.bat` failed: `xelab` not recognized

Conclusion:

- Software golden model flow is now operational.
- HDL compile/sim in this shell still needs Vivado toolchain available in PATH (or absolute tool paths in scripts).
