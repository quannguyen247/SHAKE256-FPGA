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
MAX_IN_BLOCKS = 4
MAX_OUT_BLOCKS = 4
MAX_MSG_BYTES = (MAX_IN_BLOCKS * SHAKE_RATE_BYTES) - 1

FIXED_CASES = 6
BOUNDARY_LENGTHS = [
	0,
	1,
	2,
	3,
	SHAKE_RATE_BYTES - 1,
	SHAKE_RATE_BYTES,
	SHAKE_RATE_BYTES + 1,
	(2 * SHAKE_RATE_BYTES) - 1,
	2 * SHAKE_RATE_BYTES,
	(2 * SHAKE_RATE_BYTES) + 1,
	MAX_MSG_BYTES,
]
BOUNDARY_CASES = len(BOUNDARY_LENGTHS)
DEFAULT_RANDOM_CASES = 256
RNG_SEED_INITIAL = 0x1A2B3C4D
BASE_CASES = FIXED_CASES + BOUNDARY_CASES
DEFAULT_TOTAL_CASES = BASE_CASES + DEFAULT_RANDOM_CASES
DEFAULT_TB_FILE = IMPL_DIR / "testbench" / "tb_shake256_top.v"


@dataclass
class VectorCase:
	msg_len: int
	num_input_blocks: int
	num_out_blocks: int
	msg_hex: str
	absorb_blocks: List[bytes]
	out_blocks: List[bytes]


def xorshift32(state: int) -> tuple[int, int]:
	x = state & 0xFFFFFFFF
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= (x >> 17) & 0xFFFFFFFF
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	return x, x


def reverse_hex_line(data: bytes) -> str:
	return "".join(f"{b:02x}" for b in reversed(data))


def build_absorb_blocks(msg: bytes) -> tuple[List[bytes], int]:
	if len(msg) > MAX_MSG_BYTES:
		raise ValueError(f"msg too long (>{MAX_MSG_BYTES} bytes)")

	raw_blocks: List[bytes] = []
	full_blocks = len(msg) // SHAKE_RATE_BYTES
	rem = len(msg) % SHAKE_RATE_BYTES

	for i in range(full_blocks):
		start = i * SHAKE_RATE_BYTES
		raw_blocks.append(msg[start : start + SHAKE_RATE_BYTES])

	tail = msg[full_blocks * SHAKE_RATE_BYTES :]
	if rem == 0:
		pad = bytearray(SHAKE_RATE_BYTES)
		pad[0] ^= 0x1F
		pad[SHAKE_RATE_BYTES - 1] ^= 0x80
		raw_blocks.append(bytes(pad))
	else:
		pad = bytearray(SHAKE_RATE_BYTES)
		pad[:rem] = tail
		pad[rem] ^= 0x1F
		pad[SHAKE_RATE_BYTES - 1] ^= 0x80
		raw_blocks.append(bytes(pad))

	num_input_blocks = len(raw_blocks)
	if num_input_blocks < 1 or num_input_blocks > MAX_IN_BLOCKS:
		raise ValueError(
			f"num_input_blocks out of range ({num_input_blocks}), "
			f"supported: 1..{MAX_IN_BLOCKS}"
		)

	padded_blocks = raw_blocks + [bytes(SHAKE_RATE_BYTES)] * (MAX_IN_BLOCKS - num_input_blocks)
	return padded_blocks, num_input_blocks


def split_output_blocks(digest: bytes) -> List[bytes]:
	blocks: List[bytes] = []
	for i in range(MAX_OUT_BLOCKS):
		start = i * SHAKE_RATE_BYTES
		chunk = digest[start : start + SHAKE_RATE_BYTES]
		if len(chunk) < SHAKE_RATE_BYTES:
			chunk = chunk + bytes(SHAKE_RATE_BYTES - len(chunk))
		blocks.append(chunk)
	return blocks


def add_case(cases: List[VectorCase], msg: bytes, out_blocks: int) -> None:
	if out_blocks < 1 or out_blocks > MAX_OUT_BLOCKS:
		raise ValueError(f"out_blocks must be 1..{MAX_OUT_BLOCKS}")

	absorb_blocks, num_input_blocks = build_absorb_blocks(msg)

	digest_len = out_blocks * SHAKE_RATE_BYTES
	digest = hashlib.shake_256(msg).digest(digest_len)
	out_blocks_buf = split_output_blocks(digest)

	cases.append(
		VectorCase(
			msg_len=len(msg),
			num_input_blocks=num_input_blocks,
			num_out_blocks=out_blocks,
			msg_hex=msg.hex(),
			absorb_blocks=out_blocks_buf if False else absorb_blocks,
			out_blocks=out_blocks_buf,
		)
	)


def generate_cases(random_cases: int) -> List[VectorCase]:
	cases: List[VectorCase] = []

	# Fixed known-answer style messages.
	add_case(cases, b"", 1)
	add_case(cases, b"a", 2)
	add_case(cases, b"abc", 3)
	add_case(cases, bytes((i & 0xFF) for i in range(SHAKE_RATE_BYTES)), 2)
	add_case(cases, bytes(((i * 3) + 5) & 0xFF for i in range(2 * SHAKE_RATE_BYTES)), 3)
	add_case(cases, bytes(((i * 7) + 1) & 0xFF for i in range(MAX_MSG_BYTES)), 4)

	# Deterministic boundary lengths around block and padding edges.
	for mlen in BOUNDARY_LENGTHS:
		msg = bytes(((j * 29 + mlen * 7) & 0xFF) for j in range(mlen))
		out_blocks = (len(cases) % MAX_OUT_BLOCKS) + 1
		add_case(cases, msg, out_blocks)

	# Deterministic pseudo-random message corpus.
	seed = RNG_SEED_INITIAL
	for _ in range(random_cases):
		seed, r0 = xorshift32(seed)
		mlen = r0 % (MAX_MSG_BYTES + 1)

		seed, r1 = xorshift32(seed)
		out_blocks = (r1 % MAX_OUT_BLOCKS) + 1

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
			f"(fixed={FIXED_CASES} + boundary={BOUNDARY_CASES})"
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
				f"(fixed={FIXED_CASES} + boundary={BOUNDARY_CASES})."
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
	print(f"Base deterministic cases: {BASE_CASES} (fixed={FIXED_CASES} + boundary={BOUNDARY_CASES})")
	print(f"Coverage profile: msg_len 0..{MAX_MSG_BYTES} bytes, out_blocks 1..{MAX_OUT_BLOCKS}")
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

	out_block_counts = [sum(1 for tv in cases if tv.num_out_blocks == i) for i in range(1, MAX_OUT_BLOCKS + 1)]
	in_block_counts = [sum(1 for tv in cases if tv.num_input_blocks == i) for i in range(1, MAX_IN_BLOCKS + 1)]

	(output_dir / "tv_meta.vh").write_text(
		"`ifndef TV_META_VH\n"
		"`define TV_META_VH\n"
		f"`define TV_COUNT {len(cases)}\n"
		f"`define TV_MAX_IN_BLOCKS {MAX_IN_BLOCKS}\n"
		f"`define TV_MAX_OUT_BLOCKS {MAX_OUT_BLOCKS}\n"
		"`endif\n",
		encoding="ascii",
	)

	with (output_dir / "tv_msg_len.mem").open("w", encoding="ascii") as fp_len, \
		(output_dir / "tv_msg_hex.mem").open("w", encoding="ascii") as fp_msg_hex, \
		(output_dir / "tv_num_in_blocks.mem").open("w", encoding="ascii") as fp_nin, \
		(output_dir / "tv_num_out_blocks.mem").open("w", encoding="ascii") as fp_nout, \
		(output_dir / "tv_msg_block.mem").open("w", encoding="ascii") as fp_msg_legacy, \
		(output_dir / "tv_absorb_block0.mem").open("w", encoding="ascii") as fp_abs0, \
		(output_dir / "tv_absorb_block1.mem").open("w", encoding="ascii") as fp_abs1, \
		(output_dir / "tv_absorb_block2.mem").open("w", encoding="ascii") as fp_abs2, \
		(output_dir / "tv_absorb_block3.mem").open("w", encoding="ascii") as fp_abs3, \
		(output_dir / "tv_exp_out_block0.mem").open("w", encoding="ascii") as fp_out0, \
		(output_dir / "tv_exp_out_block1.mem").open("w", encoding="ascii") as fp_out1, \
		(output_dir / "tv_exp_out_block2.mem").open("w", encoding="ascii") as fp_out2, \
		(output_dir / "tv_exp_out_block3.mem").open("w", encoding="ascii") as fp_out3, \
		(output_dir / "tv_kat_expected_block0.mem").open("w", encoding="ascii") as fp_kat0, \
		(output_dir / "tv_kat_expected_block1.mem").open("w", encoding="ascii") as fp_kat1, \
		(output_dir / "tv_kat_expected_block2.mem").open("w", encoding="ascii") as fp_kat2, \
		(output_dir / "tv_kat_expected_block3.mem").open("w", encoding="ascii") as fp_kat3:

		for tv in cases:
			fp_len.write(f"{tv.msg_len:04x}\n")
			fp_msg_hex.write(tv.msg_hex + "\n")
			fp_nin.write(f"{tv.num_input_blocks:02x}\n")
			fp_nout.write(f"{tv.num_out_blocks:02x}\n")

			fp_msg_legacy.write(reverse_hex_line(tv.absorb_blocks[0]) + "\n")
			fp_abs0.write(reverse_hex_line(tv.absorb_blocks[0]) + "\n")
			fp_abs1.write(reverse_hex_line(tv.absorb_blocks[1]) + "\n")
			fp_abs2.write(reverse_hex_line(tv.absorb_blocks[2]) + "\n")
			fp_abs3.write(reverse_hex_line(tv.absorb_blocks[3]) + "\n")

			fp_out0.write(reverse_hex_line(tv.out_blocks[0]) + "\n")
			fp_out1.write(reverse_hex_line(tv.out_blocks[1]) + "\n")
			fp_out2.write(reverse_hex_line(tv.out_blocks[2]) + "\n")
			fp_out3.write(reverse_hex_line(tv.out_blocks[3]) + "\n")

			fp_kat0.write(reverse_hex_line(tv.out_blocks[0]) + "\n")
			fp_kat1.write(reverse_hex_line(tv.out_blocks[1]) + "\n")
			fp_kat2.write(reverse_hex_line(tv.out_blocks[2]) + "\n")
			fp_kat3.write(reverse_hex_line(tv.out_blocks[3]) + "\n")

	(output_dir / "tv_manifest.txt").write_text(
		"SHAKE256 vector corpus generated from Python hashlib.shake_256\n"
		f"rate_bytes={SHAKE_RATE_BYTES}\n"
		f"max_msg_bytes={MAX_MSG_BYTES}\n"
		f"max_input_blocks={MAX_IN_BLOCKS}\n"
		f"max_output_blocks={MAX_OUT_BLOCKS}\n"
		f"total_cases={len(cases)}\n"
		f"fixed_cases={FIXED_CASES}\n"
		f"boundary_cases={BOUNDARY_CASES}\n"
		f"boundary_lengths={','.join(str(v) for v in BOUNDARY_LENGTHS)}\n"
		f"random_cases={random_cases}\n"
		f"num_in_blocks_eq_1={in_block_counts[0]}\n"
		f"num_in_blocks_eq_2={in_block_counts[1]}\n"
		f"num_in_blocks_eq_3={in_block_counts[2]}\n"
		f"num_in_blocks_eq_4={in_block_counts[3]}\n"
		f"num_out_blocks_eq_1={out_block_counts[0]}\n"
		f"num_out_blocks_eq_2={out_block_counts[1]}\n"
		f"num_out_blocks_eq_3={out_block_counts[2]}\n"
		f"num_out_blocks_eq_4={out_block_counts[3]}\n"
		f"rng_seed_initial=0x{RNG_SEED_INITIAL:08X}\n",
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
	out_counts = [sum(1 for tv in cases if tv.num_out_blocks == i) for i in range(1, MAX_OUT_BLOCKS + 1)]
	in_counts = [sum(1 for tv in cases if tv.num_input_blocks == i) for i in range(1, MAX_IN_BLOCKS + 1)]

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
	for i in range(1, MAX_IN_BLOCKS + 1):
		print(f"  num_input_blocks={i}: {in_counts[i - 1]}")
	for i in range(1, MAX_OUT_BLOCKS + 1):
		print(f"  num_out_blocks={i}: {out_counts[i - 1]}")
	print(f"  total_cases: {len(cases)}")
	print(f"  random_cases: {random_cases}")

	with log_file.open("a", encoding="utf-8") as fp:
		fp.write(f"Generated {len(cases)} vectors in {out_dir}\n")
		for i in range(1, MAX_IN_BLOCKS + 1):
			fp.write(f"num_input_blocks={i}: {in_counts[i - 1]}\n")
		for i in range(1, MAX_OUT_BLOCKS + 1):
			fp.write(f"num_out_blocks={i}: {out_counts[i - 1]}\n")
		fp.write(f"total_cases={len(cases)}\n")
		fp.write(f"random_cases={random_cases}\n")

	print(f"[INFO] Logs: {log_file}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
