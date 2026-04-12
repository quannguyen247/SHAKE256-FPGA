# SHAKE256 IP Verification Report (2026-04-12_164219)

## Environment check

- Status: **PASS**

```text
gcc found: C:\msys64\ucrt64\bin\gcc.EXE
```

## Generate PQClean vectors

- Status: **PASS**

```text

Generated 397 vectors in generated
  num_out_blocks=1: 201
  num_out_blocks=2: 196
```

## C reference sanity

- Status: **PASS**

```text

=== SHAKE256 Reference (PQClean fips202.c) ===

Case 0: empty message
  inlen: 0 bytes
  out32: 46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f
  expect: 46b9dd2b0ba88d13233b3feb743eeb243fcd52ea62b81b82b50c27646ed5762f
  result: PASS


Case 1: single-byte message 'a'
  inlen: 1 bytes
  out32: 867e2cb04f5a04dcbd592501a5e8fe9ceaafca50255626ca736c138042530ba4
  expect: 867e2cb04f5a04dcbd592501a5e8fe9ceaafca50255626ca736c138042530ba4
  result: PASS


Case 2: message 'abc'
  inlen: 3 bytes
  out32: 483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739
  expect: 483366601360a8771c6863080cc4114d8db44530f8f1e1ee4f94ea37e78b5739
  result: PASS


Case 3: 136-byte incremental pattern 00..87
  inlen: 136 bytes
  out32: b7ff4073b3f5a8eabd6e17705ca7f6761a31058f9df781a6a47e3a3063b9d67a
  expect: b7ff4073b3f5a8eabd6e17705ca7f6761a31058f9df781a6a47e3a3063b9d67a
  result: PASS


All reference checks PASSED.
```

## HDL full-coverage simulation

- Status: **PASS**

```text
INFO: [VRFC 10-2263] Analyzing Verilog file "C:/Users/Quan/Desktop/SHAKE256/Implementation/sources/rtl/modules/keccak_permutation_pipeline.v" into library work
INFO: [VRFC 10-311] analyzing module keccak_permutation_pipeline
INFO: [VRFC 10-2263] Analyzing Verilog file "C:/Users/Quan/Desktop/SHAKE256/Implementation/sources/rtl/modules/keccak_round.v" into library work
INFO: [VRFC 10-311] analyzing module keccak_round
INFO: [VRFC 10-2263] Analyzing Verilog file "C:/Users/Quan/Desktop/SHAKE256/Implementation/sources/rtl/modules/shake256_pad_block.v" into library work
INFO: [VRFC 10-311] analyzing module shake256_pad_block
INFO: [VRFC 10-2263] Analyzing Verilog file "C:/Users/Quan/Desktop/SHAKE256/Implementation/sources/rtl/modules/shake256_sponge.v" into library work
INFO: [VRFC 10-311] analyzing module shake256_sponge
INFO: [VRFC 10-2263] Analyzing Verilog file "C:/Users/Quan/Desktop/SHAKE256/Implementation/sources/sim/tb_shake256_sponge_cov.v" into library work
INFO: [VRFC 10-311] analyzing module tb_shake256_sponge_cov

Vivado Simulator v2025.2.1
Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
Running: C:/AMDDesignTools/2025.2.1/Vivado/bin/unwrapped/win64.o/xelab.exe --relax tb_shake256_sponge_cov -s tb_cov 
Multi-threading is on. Using 10 slave threads.
Starting static elaboration
Pass Through NonSizing Optimizer
Completed static elaboration
Starting simulation data flow analysis
Completed simulation data flow analysis
Time Resolution for simulation is 1ps
Compiling module work.keccak_round
Compiling module work.keccak_permutation_pipeline
Compiling module work.shake256_sponge
Compiling module work.shake256_pad_block
Compiling module work.tb_shake256_sponge_cov
Built simulation snapshot tb_cov


****** xsim v2025.2.1 (64-bit)
  **** SW Build 6403652 on Thu Mar 19 19:48:24 GMT 2026
  **** IP Build 6403511 on Thu Mar 19 12:41:45 MDT 2026
  **** SharedData Build 6403650 on Thu Mar 19 14:02:13 MDT 2026
  **** Start of session at: Sun Apr 12 16:42:23 2026
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
    ** Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.

source xsim.dir/tb_cov/xsim_script.tcl
# xsim {tb_cov} -autoloadwcfg -runall
Time resolution is 1 ps
run -all
=== SHAKE256 Full-Coverage Vector Test ===
Vector count: 397
=== SHAKE256 FULL-COVERAGE PASS (397 cases) ===
$finish called at time : 184540 ns : File "C:/Users/Quan/Desktop/SHAKE256/Implementation/sources/sim/tb_shake256_sponge_cov.v" Line 243
exit
INFO: [Common 17-206] Exiting xsim at Sun Apr 12 16:42:25 2026...
```

## Final verdict

**PASS** - SHAKE256 IP matches PQClean vectors for the executed corpus.
