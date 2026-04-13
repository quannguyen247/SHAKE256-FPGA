#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
IMPL_DIR = SCRIPT_DIR.parent
LOGS_DIR = IMPL_DIR / "logs"
TESTBENCH_DIR = IMPL_DIR / "sources" / "testbench"
RTL_DIR = IMPL_DIR / "sources" / "rtl"

VECTOR_FILES = [
    "tv_meta.vh",
    "tv_msg_len.mem",
    "tv_num_out_blocks.mem",
    "tv_msg_block.mem",
    "tv_exp_out_block0.mem",
    "tv_exp_out_block1.mem",
    "tv_manifest.txt",
]


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


def ensure_vectors_exist(generated_dir: Path) -> bool:
    return all((generated_dir / name).exists() for name in VECTOR_FILES)


def resolve_vivado_bin(hint: Optional[str]) -> Optional[Path]:
    if hint:
        candidate = Path(hint)
        if (candidate / "xvlog.bat").exists() or (candidate / "xvlog").exists():
            return candidate

    for exe in ("xvlog.bat", "xvlog"):
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
            if (bin_dir / "xvlog.bat").exists():
                nums = tuple(int(x) for x in re.findall(r"\d+", child.name))
                bins.append((nums, bin_dir))
        if bins:
            bins.sort(key=lambda x: x[0])
            return bins[-1][1]

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Run SHAKE256 full-coverage HDL simulation.")
    parser.add_argument("--vivado-bin", default="", help="Path to Vivado bin containing xvlog/xelab/xsim")
    parser.add_argument("--random-cases", type=int, default=256, help="Number of deterministic-random vectors")
    parser.add_argument("--skip-vector-gen", action="store_true", help="Skip PQClean vector generation step")
    args = parser.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    run_tag = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_dir = LOGS_DIR / f"simulation_{run_tag}"
    run_dir.mkdir(parents=True, exist_ok=True)
    log_file = run_dir / "simulation.log"
    generated_dir = run_dir / "generated"

    log_file.write_text(
        "SHAKE256 simulation run\n"
        f"run_tag={run_tag}\n"
        f"run_dir={run_dir}\n",
        encoding="utf-8",
    )

    vivado_bin = resolve_vivado_bin(args.vivado_bin if args.vivado_bin else None)
    if not vivado_bin:
        print("[BLOCKED] Cannot locate Vivado bin containing xvlog/xelab/xsim.")
        with log_file.open("a", encoding="utf-8") as fp:
            fp.write("[BLOCKED] Vivado bin not found\n")
        return 2

    env = os.environ.copy()
    env["PATH"] = str(vivado_bin) + os.pathsep + env.get("PATH", "")

    if not args.skip_vector_gen:
        vec_cmd = [
            sys.executable,
            str(SCRIPT_DIR / "test_vectors.py"),
            "--output-dir",
            str(generated_dir),
            "--random-cases",
            str(args.random_cases),
        ]
        rc, out = run_cmd(vec_cmd, cwd=SCRIPT_DIR)
        append_log(log_file, "test_vectors", vec_cmd, out)
        print(out, end="" if out.endswith("\n") else "\n")
        if rc != 0:
            print(f"[FAIL] Vector generation failed (exit {rc}).")
            print(f"[INFO] Logs: {log_file}")
            return 1
    else:
        # Fallback: reuse checked-in vectors if present.
        fallback_generated = TESTBENCH_DIR / "generated"
        if fallback_generated.exists():
            generated_dir.mkdir(parents=True, exist_ok=True)
            for name in VECTOR_FILES:
                src = fallback_generated / name
                if src.exists():
                    shutil.copy2(src, generated_dir / name)

    if not ensure_vectors_exist(generated_dir):
        print("[BLOCKED] Missing vector files. Run without --skip-vector-gen first.")
        with log_file.open("a", encoding="utf-8") as fp:
            fp.write("[BLOCKED] Missing vector files under generated directory\n")
        print(f"[INFO] Logs: {log_file}")
        return 2

    xvlog = str(vivado_bin / "xvlog.bat") if (vivado_bin / "xvlog.bat").exists() else str(vivado_bin / "xvlog")
    xelab = str(vivado_bin / "xelab.bat") if (vivado_bin / "xelab.bat").exists() else str(vivado_bin / "xelab")
    xsim = str(vivado_bin / "xsim.bat") if (vivado_bin / "xsim.bat").exists() else str(vivado_bin / "xsim")

    xvlog_cmd = [
        xvlog,
        "--relax",
        "-i",
        str(run_dir),
        "-i",
        str(TESTBENCH_DIR),
        "-i",
        str(RTL_DIR / "utils"),
        str(RTL_DIR / "modules" / "keccak_permutation_pipeline.v"),
        str(RTL_DIR / "modules" / "keccak_round.v"),
        str(RTL_DIR / "modules" / "shake256_pad_block.v"),
        str(RTL_DIR / "modules" / "shake256_sponge.v"),
        str(TESTBENCH_DIR / "tb_shake256_sponge_cov.v"),
    ]
    rc_c, out_c = run_cmd(xvlog_cmd, cwd=run_dir, env=env)
    append_log(log_file, "xvlog", xvlog_cmd, out_c)
    print(out_c, end="" if out_c.endswith("\n") else "\n")
    if rc_c != 0:
        print(f"[FAIL] xvlog failed (exit {rc_c}).")
        print(f"[INFO] Logs: {log_file}")
        return 1

    xelab_cmd = [xelab, "--relax", "tb_shake256_sponge_cov", "-s", "tb_cov"]
    rc_e, out_e = run_cmd(xelab_cmd, cwd=run_dir, env=env)
    append_log(log_file, "xelab", xelab_cmd, out_e)
    print(out_e, end="" if out_e.endswith("\n") else "\n")
    if rc_e != 0:
        print(f"[FAIL] xelab failed (exit {rc_e}).")
        print(f"[INFO] Logs: {log_file}")
        return 1

    xsim_cmd = [xsim, "tb_cov", "-runall"]
    rc_s, out_s = run_cmd(xsim_cmd, cwd=run_dir, env=env)
    append_log(log_file, "xsim", xsim_cmd, out_s)
    print(out_s, end="" if out_s.endswith("\n") else "\n")
    if rc_s != 0:
        print(f"[FAIL] xsim failed (exit {rc_s}).")
        print(f"[INFO] Logs: {log_file}")
        return 1
    if "SHAKE256 FULL-COVERAGE PASS" not in out_s:
        print("[FAIL] PASS marker not found in simulator output.")
        print(f"[INFO] Logs: {log_file}")
        return 1

    print("[PASS] Simulation completed successfully.")
    print(f"[INFO] Logs: {log_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
