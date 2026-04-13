#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
IMPL_DIR = SCRIPT_DIR.parent
LOGS_DIR = IMPL_DIR / "logs"
PROJECT_FILE = (IMPL_DIR / "SHAKE256.xpr").resolve()


def run_cmd(cmd: List[str], cwd: Optional[Path] = None, env: Optional[Dict[str, str]] = None) -> Tuple[int, str]:
    result = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        shell=False,
    )
    return result.returncode, result.stdout


def append_log(log_file: Path, title: str, cmd: List[str], out: str) -> None:
    with log_file.open("a", encoding="utf-8") as fp:
        fp.write(f"\n[{title}]\n")
        fp.write("$ " + " ".join(cmd) + "\n")
        fp.write(out)
        if not out.endswith("\n"):
            fp.write("\n")


def build_tcl(jobs: int, to_step: str) -> str:
    proj = PROJECT_FILE.as_posix()
    safe_step = to_step.replace("\"", "")
    return f"""set proj_path [file normalize {{{proj}}}]
puts \"OPEN_PROJECT=$proj_path\"
open_project $proj_path

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
reset_run impl_1

launch_runs impl_1 -to_step {safe_step} -jobs {jobs}
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts \"IMPL_STATUS=$impl_status\"

set bit_files [glob -nocomplain [file normalize [file join [file dirname $proj_path] SHAKE256.runs impl_1 *.bit]]]
if {{[llength $bit_files] > 0}} {{
    puts \"BIT_PATH=[lindex $bit_files 0]\"
}}

close_project

if {{[string match \"*ERROR*\" $impl_status]}} {{
    exit 1
}}
exit 0
"""


def resolve_vivado_bin(hint: Optional[str]) -> Optional[Path]:
    if hint:
        candidate = Path(hint)
        if (candidate / "vivado.bat").exists() or (candidate / "vivado").exists():
            return candidate

    for exe in ("vivado.bat", "vivado"):
        found = shutil.which(exe)
        if found:
            return Path(found).parent

    amd_root = Path("C:/AMDDesignTools")
    if amd_root.exists():
        bins: List[Tuple[Tuple[int, ...], Path]] = []
        for child in amd_root.iterdir():
            if not child.is_dir():
                continue
            bin_dir = child / "Vivado" / "bin"
            if (bin_dir / "vivado.bat").exists():
                nums = tuple(int(x) for x in re.findall(r"\d+", child.name))
                bins.append((nums, bin_dir))
        if bins:
            bins.sort(key=lambda x: x[0])
            return bins[-1][1]

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Run implementation only for SHAKE256 Vivado project.")
    parser.add_argument("--vivado-bin", default="", help="Path to Vivado bin containing vivado executable")
    parser.add_argument("--jobs", type=int, default=8, help="Parallel jobs for Vivado run")
    parser.add_argument(
        "--to-step",
        default="write_bitstream",
        help="Implementation step target passed to Tcl launch_runs -to_step",
    )
    args = parser.parse_args()

    if not PROJECT_FILE.exists():
        print(f"[BLOCKED] Missing Vivado project: {PROJECT_FILE}")
        return 2

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    run_tag = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = LOGS_DIR / f"implementation_{run_tag}"
    run_dir.mkdir(parents=True, exist_ok=True)
    log_file = run_dir / "implementation.log"
    log_file.write_text(
        "SHAKE256 implementation run\n"
        f"run_tag={run_tag}\n"
        f"run_dir={run_dir}\n",
        encoding="utf-8",
    )

    vivado_bin = resolve_vivado_bin(args.vivado_bin if args.vivado_bin else None)
    if not vivado_bin:
        print("[BLOCKED] Cannot locate Vivado bin containing vivado executable.")
        return 2

    vivado = str(vivado_bin / "vivado.bat") if (vivado_bin / "vivado.bat").exists() else str(vivado_bin / "vivado")

    env = os.environ.copy()
    env["PATH"] = str(vivado_bin) + os.pathsep + env.get("PATH", "")

    tcl_content = build_tcl(args.jobs, args.to_step)
    with tempfile.NamedTemporaryFile(mode="w", suffix=".tcl", delete=False, encoding="ascii", dir=run_dir) as fp:
        fp.write(tcl_content)
        tcl_path = Path(fp.name)

    cmd = [vivado, "-mode", "batch", "-source", str(tcl_path)]
    rc, out = run_cmd(cmd, cwd=run_dir, env=env)
    append_log(log_file, "vivado", cmd, out)
    try:
        tcl_path.unlink(missing_ok=True)
    except OSError:
        pass

    print(out, end="" if out.endswith("\n") else "\n")

    if rc == 0:
        print("[PASS] Implementation completed successfully.")
        print(f"[INFO] Logs: {log_file}")
        return 0

    print(f"[FAIL] Implementation failed (exit {rc}).")
    print(f"[INFO] Logs: {log_file}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
