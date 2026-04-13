#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime
import subprocess
import sys
from pathlib import Path
from typing import List


SCRIPT_DIR = Path(__file__).resolve().parent
IMPL_DIR = SCRIPT_DIR.parent
LOGS_DIR = IMPL_DIR / "logs"


def run_step(name: str, cmd: List[str], log_file: Path) -> int:
    print(f"\n===== {name} =====")
    print(" ".join(cmd))

    result = subprocess.run(
        cmd,
        cwd=str(SCRIPT_DIR),
        shell=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    output = result.stdout
    print(output, end="" if output.endswith("\n") else "\n")

    with log_file.open("a", encoding="utf-8") as fp:
        fp.write(f"\n===== {name} =====\n")
        fp.write("$ " + " ".join(cmd) + "\n")
        fp.write(output)
        if not output.endswith("\n"):
            fp.write("\n")

    if result.returncode != 0:
        print(f"[FAIL] {name} failed with exit code {result.returncode}.")
        return result.returncode
    print(f"[PASS] {name} completed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run simulation, synthesis, and implementation in sequence.")

    parser.add_argument("--vivado-bin", default="", help="Vivado bin path applied to all steps")
    parser.add_argument("--jobs", type=int, default=8, help="Parallel jobs used for synthesis/implementation")

    parser.add_argument("--random-cases", type=int, default=256, help="Simulation random vector count")
    parser.add_argument("--skip-vector-gen", action="store_true", help="Skip simulation vector generation")

    parser.add_argument("--impl-to-step", default="write_bitstream", help="Implementation target step")

    parser.add_argument("--skip-simulation", action="store_true", help="Skip simulation step")
    parser.add_argument("--skip-synthesis", action="store_true", help="Skip synthesis step")
    parser.add_argument("--skip-implementation", action="store_true", help="Skip implementation step")

    args = parser.parse_args()

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    run_tag = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    run_log = LOGS_DIR / f"run_all_{run_tag}.log"
    run_log.write_text(
        "SHAKE256 run_all orchestration\n"
        f"run_tag={run_tag}\n",
        encoding="utf-8",
    )

    py = sys.executable

    if not args.skip_simulation:
        sim_cmd = [
            py,
            str(SCRIPT_DIR / "simulation.py"),
            "--random-cases",
            str(args.random_cases),
        ]
        if args.vivado_bin:
            sim_cmd.extend(["--vivado-bin", args.vivado_bin])
        if args.skip_vector_gen:
            sim_cmd.append("--skip-vector-gen")

        rc = run_step("Simulation", sim_cmd, run_log)
        if rc != 0:
            print(f"[INFO] Logs: {run_log}")
            return rc

    if not args.skip_synthesis:
        synth_cmd = [
            py,
            str(SCRIPT_DIR / "synthesis.py"),
            "--jobs",
            str(args.jobs),
        ]
        if args.vivado_bin:
            synth_cmd.extend(["--vivado-bin", args.vivado_bin])

        rc = run_step("Synthesis", synth_cmd, run_log)
        if rc != 0:
            print(f"[INFO] Logs: {run_log}")
            return rc

    if not args.skip_implementation:
        impl_cmd = [
            py,
            str(SCRIPT_DIR / "implementation.py"),
            "--jobs",
            str(args.jobs),
            "--to-step",
            str(args.impl_to_step),
        ]
        if args.vivado_bin:
            impl_cmd.extend(["--vivado-bin", args.vivado_bin])

        rc = run_step("Implementation", impl_cmd, run_log)
        if rc != 0:
            print(f"[INFO] Logs: {run_log}")
            return rc

    print("\n[PASS] run_all flow completed.")
    print(f"[INFO] Logs: {run_log}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
