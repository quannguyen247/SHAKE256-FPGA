#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List


SCRIPT_DIR = Path(__file__).resolve().parent
IMPL_DIR = SCRIPT_DIR.parent
LOGS_DIR = IMPL_DIR / "logs"
VECTORS_DIR = IMPL_DIR / "vectors"

SHAKE_RATE_BYTES = 136
MAX_OUT_BLOCKS = 2
DEFAULT_RANDOM_CASES = 256
RNG_SEED_INITIAL = 0x1A2B3C4D
FIXED_CASES = 4
EXHAUSTIVE_LENGTH_CASES = SHAKE_RATE_BYTES + 1
BASE_CASES = FIXED_CASES + EXHAUSTIVE_LENGTH_CASES
DEFAULT_TOTAL_CASES = BASE_CASES + DEFAULT_RANDOM_CASES
DEFAULT_TB_FILE = IMPL_DIR / "testbench" / "tb_shake256_top.v"


@dataclass
class VectorCase:
	msg_len: int
	num_out_blocks: int
	msg_block: bytes
	out_bytes: bytes


def xorshift32(state: int) -> tuple[int, int]:
	x = state & 0xFFFFFFFF
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= (x >> 17) & 0xFFFFFFFF
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	return x, x


def reverse_hex_line(data: bytes) -> str:
	return "".join(f"{b:02x}" for b in reversed(data))


def add_case(cases: List[VectorCase], msg: bytes, out_blocks: int) -> None:
	if out_blocks < 1 or out_blocks > MAX_OUT_BLOCKS:
		raise ValueError("out_blocks must be 1 or 2")
	if len(msg) > SHAKE_RATE_BYTES:
		raise ValueError("msg too long")

	msg_block = msg + bytes(SHAKE_RATE_BYTES - len(msg))

	digest_len = out_blocks * SHAKE_RATE_BYTES
	digest = hashlib.shake_256(msg).digest(digest_len)

	out_buf = bytearray(MAX_OUT_BLOCKS * SHAKE_RATE_BYTES)
	out_buf[:digest_len] = digest

	cases.append(
		VectorCase(
			msg_len=len(msg),
			num_out_blocks=out_blocks,
			msg_block=msg_block,
			out_bytes=bytes(out_buf),
		)
	)


def generate_cases(random_cases: int) -> List[VectorCase]:
	cases: List[VectorCase] = []

	# Fixed known-answer style messages.
	add_case(cases, b"", 1)
	add_case(cases, b"a", 2)
	add_case(cases, b"abc", 1)
	add_case(cases, bytes(range(SHAKE_RATE_BYTES)), 2)

	# Deterministic exhaustive lengths [0..136].
	for mlen in range(SHAKE_RATE_BYTES + 1):
		msg = bytes(((j * 29 + mlen * 7) & 0xFF) for j in range(mlen))
		out_blocks = 2 if (len(cases) & 1) else 1
		add_case(cases, msg, out_blocks)

	# Deterministic pseudo-random message corpus.
	seed = RNG_SEED_INITIAL
	for _ in range(random_cases):
		seed, r0 = xorshift32(seed)
		mlen = r0 % (SHAKE_RATE_BYTES + 1)

		seed, r1 = xorshift32(seed)
		out_blocks = 2 if (r1 & 1) else 1

		msg = bytearray()
		for _ in range(mlen):
			seed, r2 = xorshift32(seed)
			msg.append(r2 & 0xFF)

		add_case(cases, bytes(msg), out_blocks)

	return cases


def total_cases_from_random(random_cases: int) -> int:
	return BASE_CASES + random_cases


def random_cases_from_total(total_cases: int) -> int:
	if total_cases < BASE_CASES:
		raise ValueError(
			f"total-cases must be >= {BASE_CASES} "
			f"(fixed={FIXED_CASES} + exhaustive={EXHAUSTIVE_LENGTH_CASES})"
		)
	return total_cases - BASE_CASES


def prompt_total_cases(default_total: int) -> int:
	prompt = (
		"Enter desired total vector count "
		f"[min {BASE_CASES}, default {default_total}]: "
	)
	while True:
		raw = input(prompt).strip()
		if raw == "":
			return default_total
		if not raw.isdigit():
			print("[WARN] Please enter a non-negative integer.")
			continue
		total = int(raw)
		if total < BASE_CASES:
			print(
				f"[WARN] total must be >= {BASE_CASES} "
				f"(fixed={FIXED_CASES} + exhaustive={EXHAUSTIVE_LENGTH_CASES})."
			)
			continue
		return total


def prompt_non_negative_int(prompt: str, default_value: int) -> int:
	while True:
		raw = input(f"{prompt} [default {default_value}]: ").strip()
		if raw == "":
			return default_value
		if not raw.isdigit():
			print("[WARN] Please enter a non-negative integer.")
			continue
		return int(raw)


def prompt_yes_no(prompt: str, default: bool = False) -> bool:
	default_text = "Y/n" if default else "y/N"
	while True:
		raw = input(f"{prompt} [{default_text}]: ").strip().lower()
		if raw == "":
			return default
		if raw in ("y", "yes"):
			return True
		if raw in ("n", "no"):
			return False
		print("[WARN] Please answer y or n.")


def run_menu(default_output_dir: Path, default_tb_file: Path) -> tuple[int, Path, bool, Path]:
	print("=== SHAKE256 Vector Generator Menu ===")
	print(f"Base deterministic cases: {BASE_CASES} (fixed={FIXED_CASES} + exhaustive={EXHAUSTIVE_LENGTH_CASES})")
	print("Choose generation mode:")
	print("  1) Default set (recommended)")
	print("  2) Enter exact total vector count")
	print("  3) Enter random-case count directly")
	print("  4) Exit")

	while True:
		choice = input("Select option [1-4, default 1]: ").strip()
		if choice == "":
			choice = "1"

		if choice == "1":
			random_cases = DEFAULT_RANDOM_CASES
			break
		if choice == "2":
			total_cases = prompt_total_cases(DEFAULT_TOTAL_CASES)
			random_cases = random_cases_from_total(total_cases)
			break
		if choice == "3":
			random_cases = prompt_non_negative_int("Enter random-case count", DEFAULT_RANDOM_CASES)
			break
		if choice == "4":
			raise KeyboardInterrupt()

		print("[WARN] Invalid option. Please choose 1, 2, 3, or 4.")

	output_raw = input(f"Output directory [default {default_output_dir}]: ").strip()
	output_dir = Path(output_raw) if output_raw else default_output_dir

	sync_tb_count = prompt_yes_no("Sync testbench `define TV_COUNT to generated total?", default=False)
	tb_file = default_tb_file
	if sync_tb_count:
		tb_raw = input(f"Testbench file [default {default_tb_file}]: ").strip()
		tb_file = Path(tb_raw) if tb_raw else default_tb_file

	return random_cases, output_dir, sync_tb_count, tb_file


def sync_tb_tv_count(tb_file: Path, total_cases: int) -> bool:
	if not tb_file.exists():
		raise FileNotFoundError(f"testbench file not found: {tb_file}")

	text = tb_file.read_text(encoding="utf-8")
	pattern = r"(^\s*`define\s+TV_COUNT\s+)\d+(\s*$)"
	updated, replacements = re.subn(
		pattern,
		rf"\g<1>{total_cases}\g<2>",
		text,
		count=1,
		flags=re.MULTILINE,
	)

	if replacements == 0:
		raise ValueError(f"Cannot find `define TV_COUNT in {tb_file}")

	if updated != text:
		tb_file.write_text(updated, encoding="utf-8")
		return True
	return False


def write_vectors(output_dir: Path, random_cases: int) -> List[VectorCase]:
	output_dir.mkdir(parents=True, exist_ok=True)
	cases = generate_cases(random_cases)

	out_two_count = sum(1 for tv in cases if tv.num_out_blocks == 2)

	(output_dir / "tv_meta.vh").write_text(
		"`ifndef TV_META_VH\n"
		"`define TV_META_VH\n"
		f"`define TV_COUNT {len(cases)}\n"
		"`endif\n",
		encoding="ascii",
	)

	with (output_dir / "tv_msg_len.mem").open("w", encoding="ascii") as fp_len, \
		(output_dir / "tv_num_out_blocks.mem").open("w", encoding="ascii") as fp_num, \
		(output_dir / "tv_msg_block.mem").open("w", encoding="ascii") as fp_msg, \
		(output_dir / "tv_exp_out_block0.mem").open("w", encoding="ascii") as fp_out0, \
		(output_dir / "tv_exp_out_block1.mem").open("w", encoding="ascii") as fp_out1:

		for tv in cases:
			fp_len.write(f"{tv.msg_len:02x}\n")
			fp_num.write(f"{tv.num_out_blocks:02x}\n")
			fp_msg.write(reverse_hex_line(tv.msg_block) + "\n")

			out0 = tv.out_bytes[:SHAKE_RATE_BYTES]
			out1 = tv.out_bytes[SHAKE_RATE_BYTES : 2 * SHAKE_RATE_BYTES]
			fp_out0.write(reverse_hex_line(out0) + "\n")
			fp_out1.write(reverse_hex_line(out1) + "\n")

	(output_dir / "tv_manifest.txt").write_text(
		"SHAKE256 vector corpus generated from Python hashlib.shake_256\n"
		f"rate_bytes={SHAKE_RATE_BYTES}\n"
		f"total_cases={len(cases)}\n"
		"fixed_cases=4\n"
		f"exhaustive_length_cases={SHAKE_RATE_BYTES + 1}\n"
		f"random_cases={random_cases}\n"
		f"num_out_blocks_eq_1={len(cases) - out_two_count}\n"
		f"num_out_blocks_eq_2={out_two_count}\n"
		f"rng_seed_initial=0x{RNG_SEED_INITIAL:08X}\n",
		encoding="ascii",
	)

	# Keep compatibility with top-level testbench file-name convention.
	(output_dir / "tv_kat_expected_block0.mem").write_text(
		(output_dir / "tv_exp_out_block0.mem").read_text(encoding="ascii"),
		encoding="ascii",
	)
	(output_dir / "tv_kat_expected_block1.mem").write_text(
		(output_dir / "tv_exp_out_block1.mem").read_text(encoding="ascii"),
		encoding="ascii",
	)

	return cases


def main() -> int:
	parser = argparse.ArgumentParser(description="Generate deterministic SHAKE256 vectors for HDL testbenches.")
	parser.add_argument(
		"-o",
		"--output-dir",
		default=str(VECTORS_DIR),
		help="Output directory for generated mem/vector files",
	)
	parser.add_argument(
		"-r",
		"--random-cases",
		type=int,
		default=None,
		help="Number of deterministic pseudo-random cases",
	)
	parser.add_argument(
		"-t",
		"--total-cases",
		type=int,
		default=None,
		help=(
			"Exact total number of vectors to generate "
			f"(must be >= {BASE_CASES}; random_cases = total_cases - {BASE_CASES})"
		),
	)
	parser.add_argument(
		"-i",
		"--interactive",
		action="store_true",
		help="Prompt for desired total number of vectors in CLI",
	)
	parser.add_argument(
		"--sync-tb-count",
		action="store_true",
		help="Update `define TV_COUNT in testbench file to match generated total cases",
	)
	parser.add_argument(
		"--tb-file",
		default=str(DEFAULT_TB_FILE),
		help="Testbench file path used with --sync-tb-count",
	)
	parser.add_argument(
		"--menu",
		action="store_true",
		help="Force interactive menu mode",
	)
	parser.add_argument(
		"--no-menu",
		action="store_true",
		help="Disable menu mode and use CLI arguments only",
	)
	args = parser.parse_args()

	if args.menu and args.no_menu:
		print("[FAIL] Use either --menu or --no-menu, not both.")
		return 2

	menu_mode = args.menu or (not args.no_menu and len(sys.argv) == 1)

	if menu_mode:
		try:
			random_cases, out_dir, sync_tb_count, tb_path = run_menu(
				VECTORS_DIR,
				Path(args.tb_file),
			)
		except KeyboardInterrupt:
			print("[INFO] Cancelled by user.")
			return 130
		target_total = total_cases_from_random(random_cases)
	else:
		sync_tb_count = args.sync_tb_count
		tb_path = Path(args.tb_file)
		out_dir = Path(args.output_dir)

		if args.total_cases is not None and args.random_cases is not None:
			print("[FAIL] Use either --total-cases or --random-cases, not both.")
			return 2

		if args.interactive and args.total_cases is not None:
			print("[FAIL] Use either --interactive or --total-cases, not both.")
			return 2

		if args.interactive and args.random_cases is not None:
			print("[FAIL] Use either --interactive or --random-cases, not both.")
			return 2

		if args.interactive:
			target_total = prompt_total_cases(DEFAULT_TOTAL_CASES)
			random_cases = random_cases_from_total(target_total)
		elif args.total_cases is not None:
			if args.total_cases < 0:
				print("[FAIL] total-cases must be >= 0")
				return 2
			try:
				random_cases = random_cases_from_total(args.total_cases)
			except ValueError as exc:
				print(f"[FAIL] {exc}")
				return 2
		else:
			random_cases = args.random_cases if args.random_cases is not None else DEFAULT_RANDOM_CASES

		target_total = total_cases_from_random(random_cases)

	if random_cases < 0:
		print("[FAIL] random-cases must be >= 0")
		return 2

	LOGS_DIR.mkdir(parents=True, exist_ok=True)
	run_tag = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
	log_file = LOGS_DIR / f"test_vectors_{run_tag}.log"
	log_file.write_text(
		"SHAKE256 test vector generation\n"
		f"run_tag={run_tag}\n"
		f"output_dir={out_dir}\n"
		f"random_cases={random_cases}\n"
		f"total_cases={target_total}\n"
		f"sync_tb_count={sync_tb_count}\n"
		f"tb_file={tb_path}\n"
		f"menu_mode={menu_mode}\n",
		encoding="utf-8",
	)

	cases = write_vectors(out_dir, random_cases)
	out_two = sum(1 for tv in cases if tv.num_out_blocks == 2)

	if sync_tb_count:
		try:
			changed = sync_tb_tv_count(tb_path, len(cases))
		except (FileNotFoundError, ValueError) as exc:
			print(f"[FAIL] {exc}")
			with log_file.open("a", encoding="utf-8") as fp:
				fp.write(f"[FAIL] {exc}\n")
			print(f"[INFO] Logs: {log_file}")
			return 2
		status = "updated" if changed else "already-matching"
		print(f"[INFO] sync_tb_count: {status} ({tb_path})")
		with log_file.open("a", encoding="utf-8") as fp:
			fp.write(f"sync_tb_count={status}\n")
			fp.write(f"tb_file={tb_path}\n")

	print(f"Generated {len(cases)} vectors in {out_dir}")
	print(f"  num_out_blocks=1: {len(cases) - out_two}")
	print(f"  num_out_blocks=2: {out_two}")
	print(f"  total_cases: {len(cases)}")
	print(f"  random_cases: {random_cases}")

	with log_file.open("a", encoding="utf-8") as fp:
		fp.write(f"Generated {len(cases)} vectors in {out_dir}\n")
		fp.write(f"num_out_blocks=1: {len(cases) - out_two}\n")
		fp.write(f"num_out_blocks=2: {out_two}\n")
		fp.write(f"total_cases={len(cases)}\n")
		fp.write(f"random_cases={random_cases}\n")

	print(f"[INFO] Logs: {log_file}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
