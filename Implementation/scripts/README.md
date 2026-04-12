# Script Usage

## 1) Run full flow (C reference + HDL sim attempt)

From `Implementation/scripts`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_ref_and_sim.ps1
```

## 2) Run only C reference checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_ref_and_sim.ps1 -SkipHdl
```

## 3) If Vivado is installed but not in PATH

Pass explicit Vivado bin path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_ref_and_sim.ps1 -VivadoBin "D:\Xilinx\Vivado\2025.1\bin"
```

## 4) Output report

Each run writes a timestamped markdown report to:

- `Implementation/reports/compile_sim_status_YYYY-MM-DD_HHMMSS.md`

The report includes:

- environment checks
- C build/run result and digest comparisons
- HDL compile/elaborate/sim status (or blocking reason)

## 5) One-click IP verification (recommended for thesis demo)

This flow generates a deterministic PQClean vector corpus, runs C reference checks,
then runs HDL full-coverage simulation and prints a final PASS/FAIL verdict.

From `Implementation/scripts`:

```powershell
python .\verify_ip.py
```

Or double-click/run:

```bat
verify_ip.bat
```

Optional arguments:

```powershell
python .\verify_ip.py --random-cases 512
python .\verify_ip.py --vivado-bin "C:\AMDDesignTools\2025.2\Vivado\bin"
```

Output reports:

- `Implementation/reports/verify_ip_status_YYYY-MM-DD_HHMMSS.md`
- `Implementation/reports/verify_ip_latest.md`

Exit code:

- `0` = PASS
- `1` = FAIL
- `2` = BLOCKED (missing tools)
