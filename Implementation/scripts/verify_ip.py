#!/usr/bin/env python3
"""
One-click SHAKE256 IP verification runner.

Flow:
1) Build + run PQClean vector generator (gen_pqclean_vectors.c)
2) Build + run PQClean reference checker (test_keccak_ref.c)
3) Compile + run Vivado xsim full-coverage HDL testbench (tb_shake256_sponge_cov.v)
4) Emit a markdown report with PASS/FAIL summary
"""

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
REPO_DIR = IMPL_DIR.parent
SIM_DIR = IMPL_DIR / "sources" / "sim"
RTL_DIR = IMPL_DIR / "sources" / "rtl"
REPORTS_DIR = IMPL_DIR / "reports"
PQCOMMON_DIR = REPO_DIR / "PQClean" / "common"


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


def add_report(lines: List[str], title: str, status: str, details: str) -> None:
    lines.append(f"## {title}")
    lines.append("")
    lines.append(f"- Status: **{status}**")
    lines.append("")
    if details.strip():
        lines.append("```text")
        lines.append(details.rstrip())
        lines.append("```")
    lines.append("")


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify SHAKE256 IP against PQClean vectors.")
    parser.add_argument("--vivado-bin", default="", help="Path to Vivado bin containing xvlog/xelab/xsim")
    parser.add_argument("--random-cases", type=int, default=256, help="Number of extra deterministic-random vectors")
    args = parser.parse_args()

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    report_path = REPORTS_DIR / f"verify_ip_status_{ts}.md"

    report_lines: List[str] = []
    report_lines.append(f"# SHAKE256 IP Verification Report ({ts})")
    report_lines.append("")

    overall_pass = True
    overall_blocked = False

    gcc = shutil.which("gcc")
    if not gcc:
        add_report(
            report_lines,
            "Environment check",
            "BLOCKED",
            "gcc was not found in PATH. Install MinGW/MSYS2 gcc to run the verification flow.",
        )
        overall_blocked = True
    else:
        add_report(report_lines, "Environment check", "PASS", f"gcc found: {gcc}")

    # Step 1: build + run vector generator
    gen_exe = SIM_DIR / "gen_pqclean_vectors.exe"
    gen_cmd = [
        gcc if gcc else "gcc",
        "-O2",
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-o",
        str(gen_exe),
        "gen_pqclean_vectors.c",
        str(PQCOMMON_DIR / "fips202.c"),
        f"-I{PQCOMMON_DIR}",
    ]

    if overall_blocked:
        add_report(report_lines, "Generate PQClean vectors", "BLOCKED", "Skipped due to missing gcc.")
        overall_pass = False
    else:
        rc, out = run_cmd(gen_cmd, cwd=SIM_DIR)
        if rc != 0:
            add_report(report_lines, "Generate PQClean vectors", "FAIL", out)
            overall_pass = False
        else:
            rc_run, out_run = run_cmd(
                [str(gen_exe), "-o", "generated", "-r", str(args.random_cases)],
                cwd=SIM_DIR,
            )
            if rc_run != 0:
                add_report(report_lines, "Generate PQClean vectors", "FAIL", out_run)
                overall_pass = False
            else:
                add_report(report_lines, "Generate PQClean vectors", "PASS", out + "\n" + out_run)

    # Step 2: build + run C reference check
    cref_exe = SIM_DIR / "test_keccak_ref.exe"
    cref_cmd = [
        gcc if gcc else "gcc",
        "-O2",
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-o",
        str(cref_exe),
        "test_keccak_ref.c",
        str(PQCOMMON_DIR / "fips202.c"),
        f"-I{PQCOMMON_DIR}",
    ]

    if overall_blocked:
        add_report(report_lines, "C reference sanity", "BLOCKED", "Skipped due to missing gcc.")
        overall_pass = False
    else:
        rc, out = run_cmd(cref_cmd, cwd=SIM_DIR)
        if rc != 0:
            add_report(report_lines, "C reference sanity", "FAIL", out)
            overall_pass = False
        else:
            rc_run, out_run = run_cmd([str(cref_exe)], cwd=SIM_DIR)
            if rc_run != 0:
                add_report(report_lines, "C reference sanity", "FAIL", out + "\n" + out_run)
                overall_pass = False
            else:
                add_report(report_lines, "C reference sanity", "PASS", out + "\n" + out_run)

    # Step 3: HDL full-coverage simulation
    vivado_bin = resolve_vivado_bin(args.vivado_bin if args.vivado_bin else None)
    if not vivado_bin:
        add_report(
            report_lines,
            "HDL full-coverage simulation",
            "BLOCKED",
            "Cannot locate Vivado bin containing xvlog/xelab/xsim.",
        )
        overall_pass = False
        overall_blocked = True
    else:
        env = os.environ.copy()
        env["PATH"] = str(vivado_bin) + os.pathsep + env.get("PATH", "")

        xvlog = str(vivado_bin / "xvlog.bat") if (vivado_bin / "xvlog.bat").exists() else str(vivado_bin / "xvlog")
        xelab = str(vivado_bin / "xelab.bat") if (vivado_bin / "xelab.bat").exists() else str(vivado_bin / "xelab")
        xsim = str(vivado_bin / "xsim.bat") if (vivado_bin / "xsim.bat").exists() else str(vivado_bin / "xsim")

        xvlog_cmd = [
            xvlog,
            "--relax",
            "-i",
            str(SIM_DIR),
            "-i",
            str(RTL_DIR / "utils"),
            str(RTL_DIR / "modules" / "keccak_permutation_pipeline.v"),
            str(RTL_DIR / "modules" / "keccak_round.v"),
            str(RTL_DIR / "modules" / "shake256_pad_block.v"),
            str(RTL_DIR / "modules" / "shake256_sponge.v"),
            str(SIM_DIR / "tb_shake256_sponge_cov.v"),
        ]
        rc_c, out_c = run_cmd(xvlog_cmd, cwd=SIM_DIR, env=env)

        if rc_c != 0:
            add_report(report_lines, "HDL full-coverage simulation", "FAIL", out_c)
            overall_pass = False
        else:
            xelab_cmd = [xelab, "--relax", "tb_shake256_sponge_cov", "-s", "tb_cov"]
            rc_e, out_e = run_cmd(xelab_cmd, cwd=SIM_DIR, env=env)
            if rc_e != 0:
                add_report(report_lines, "HDL full-coverage simulation", "FAIL", out_c + "\n" + out_e)
                overall_pass = False
            else:
                xsim_cmd = [xsim, "tb_cov", "-runall"]
                rc_s, out_s = run_cmd(xsim_cmd, cwd=SIM_DIR, env=env)
                details = out_c + "\n" + out_e + "\n" + out_s
                if rc_s != 0:
                    add_report(report_lines, "HDL full-coverage simulation", "FAIL", details)
                    overall_pass = False
                elif "SHAKE256 FULL-COVERAGE PASS" not in out_s:
                    add_report(
                        report_lines,
                        "HDL full-coverage simulation",
                        "FAIL",
                        details + "\n\nPASS marker not found in simulator output.",
                    )
                    overall_pass = False
                else:
                    add_report(report_lines, "HDL full-coverage simulation", "PASS", details)

    if overall_pass:
        report_lines.append("## Final verdict")
        report_lines.append("")
        report_lines.append("**PASS** - SHAKE256 IP matches PQClean vectors for the executed corpus.")
        exit_code = 0
    elif overall_blocked:
        report_lines.append("## Final verdict")
        report_lines.append("")
        report_lines.append("**BLOCKED** - verification flow could not fully run due to missing tools.")
        exit_code = 2
    else:
        report_lines.append("## Final verdict")
        report_lines.append("")
        report_lines.append("**FAIL** - at least one verification stage failed.")
        exit_code = 1

    report_path.write_text("\n".join(report_lines) + "\n", encoding="ascii", errors="ignore")
    latest_path = REPORTS_DIR / "verify_ip_latest.md"
    latest_path.write_text("\n".join(report_lines) + "\n", encoding="ascii", errors="ignore")

    print(f"Report: {report_path}")
    print(f"Latest: {latest_path}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
