#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import re
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

def clear_vectors(output_dir: Path) -> None:
	script_path = Path(__file__).resolve()
	if not output_dir.exists():
		print(f"No vector directory: {output_dir}")
		return
	removed = 0
	for p in output_dir.glob("*"):
		if not p.is_file():
			continue
		# Never delete Python source or compiled bytecode
		if p.suffix in (".py", ".pyc", ".pyo"):
			continue
		# Never delete the running script (resolve symlinks)
		try:
			if p.resolve() == script_path:
				continue
		except Exception:
			# If resolve fails, skip to be safe
			continue
		# Only delete generator output files (tv_* and known manifest/meta names)
		if not (p.name.startswith("tv_") or p.name in ("tv_manifest.txt", "tv_meta.vh")):
			continue
		try:
			p.unlink()
			removed += 1
		except Exception:
			pass
	print(f"Cleared {removed} files in {output_dir}")

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
	print("=== SHAKE256 Vector Generator ===")
	while True:
		print("\n1) Start\n2) Clear vectors\n3) Exit")
		choice = input("Choose [1-3]: ").strip()
		if choice == "1":
			total = prompt_total_cases(DEFAULT_TOTAL_CASES)
			out_dir_raw = input(f"Output directory [default {VECTORS_DIR}]: ").strip()
			out_dir = Path(out_dir_raw) if out_dir_raw else VECTORS_DIR
			random_cases = random_cases_from_total(total)
			print(f"Generating {total} vectors (random_cases={random_cases})...")
			cases = write_vectors(out_dir, random_cases)
			try:
				changed = sync_tb_tv_count(DEFAULT_TB_FILE, len(cases))
				print(f"Testbench TV_COUNT {'updated' if changed else 'already-matching'}: {DEFAULT_TB_FILE}")
			except Exception as e:
				print(f"Warning: failed to sync testbench: {e}")
			print(f"Done. Generated {len(cases)} vectors in {out_dir}")
		elif choice == "2":
			# Delete without confirmation per user request
			clear_vectors(VECTORS_DIR)
		elif choice == "3":
			print("Exit.")
			return 0
		else:
			print("Invalid choice.")

if __name__ == "__main__":
	raise SystemExit(main())