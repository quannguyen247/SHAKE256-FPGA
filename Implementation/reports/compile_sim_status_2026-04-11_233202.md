# Compile and Simulation Status (2026-04-11 23:32:02)

## Environment checks

- GCC found: C:\msys64\ucrt64\bin\gcc.exe
- Vivado bin resolved: NO

## C reference build/run

- Build status: PASS
- Run status: PASS (exit 0)

Run output:

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

## HDL simulation attempt

- HDL sim status: BLOCKED (cannot locate Vivado bin with xvlog/xelab/xsim)
