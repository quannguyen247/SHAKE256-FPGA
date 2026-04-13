# SHAKE256 FPGA Project

This repository contains a SHAKE256 hardware implementation (Vivado RTL flow)
and a PQClean software reference baseline.

## 1) Structure

- `Implementation/`
  - `SHAKE256.xpr`: Vivado project
  - `rtl/`: SHAKE256/Keccak RTL modules
  - `testbench/`: Verilog testbenches
  - `logs/`: all runtime logs and simulation artifacts
  - `scripts/`: run scripts (Python only)
  - `reports/`: generated logs and status reports
  - `docs/`: design and roadmap documents
- `PQClean/common/fips202.c`: software reference for Keccak/SHAKE

## 2) Scripts policy

The `Implementation/scripts` folder contains Python runners:

- `simulation.py`
- `synthesis.py`
- `implementation.py`
- `test_vectors.py`
- `run_all.py`

All scripts write logs to `Implementation/logs/`.

## 3) Prerequisites

- Windows
- Python 3.10+
- GCC in PATH (required for vector generation in simulation)
- Vivado in PATH, or pass `--vivado-bin`

## 4) Usage

From repository root:

```powershell
cd Implementation\scripts
```

### 4.1 Run simulation

```powershell
python .\simulation.py
```

Useful options:

```powershell
python .\simulation.py --random-cases 512
python .\simulation.py --vivado-bin "C:\AMDDesignTools\2025.2\Vivado\bin"
```

Note: simulation always generates fresh vectors before compile/elab/run.

### 4.2 Run synthesis

```powershell
python .\synthesis.py
python .\synthesis.py --jobs 8
python .\synthesis.py --vivado-bin "C:\AMDDesignTools\2025.2\Vivado\bin"
```

### 4.3 Run implementation

```powershell
python .\implementation.py
python .\implementation.py --jobs 8
python .\implementation.py --to-step write_bitstream
python .\implementation.py --vivado-bin "C:\AMDDesignTools\2025.2\Vivado\bin"
```

### 4.4 Generate vectors only

```powershell
python .\test_vectors.py
python .\test_vectors.py --random-cases 512
python .\test_vectors.py --output-dir "C:\path\to\generated"
```

### 4.5 Run all steps

```powershell
python .\run_all.py
```

Useful options:

```powershell
python .\run_all.py --random-cases 512 --jobs 8
python .\run_all.py --skip-simulation
python .\run_all.py --skip-synthesis
python .\run_all.py --skip-implementation
python .\run_all.py --vivado-bin "C:\AMDDesignTools\2025.2\Vivado\bin"
```

## 5) Output and status

- Simulation prints PASS/FAIL in terminal.
- Synthesis/implementation status is printed from Vivado run status.
- All command logs and tool artifacts are written under:
  - `Implementation/logs/`
  - per-run subfolders are auto-created (for example: `simulation_YYYYMMDD_HHMMSS`)
- Bitstream (if generated) is under:
  - `Implementation/SHAKE256.runs/impl_1/`

Exit code convention:

- `0`: PASS
- `1`: FAIL
- `2`: BLOCKED (missing required tools/project)

## 6) Troubleshooting

- `gcc not found`
  - Install MSYS2/MinGW GCC and add to PATH.
- `Cannot locate Vivado`
  - Pass `--vivado-bin` explicitly.
- Vivado project missing
  - Check `Implementation/SHAKE256.xpr` exists.

