#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime
import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import List


SCRIPT_DIR = Path(__file__).resolve().parent
IMPL_DIR = SCRIPT_DIR.parent
LOGS_DIR = IMPL_DIR / "logs"
TESTBENCH_DIR = IMPL_DIR / "testbench"

SHAKE_RATE_BYTES = 136
MAX_OUT_BLOCKS = 2
DEFAULT_RANDOM_CASES = 256
RNG_SEED_INITIAL = 0x1A2B3C4D


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

	return cases


def main() -> int:
	parser = argparse.ArgumentParser(description="Generate deterministic SHAKE256 vectors for HDL testbenches.")
	parser.add_argument(
		"-o",
		"--output-dir",
		default=str(TESTBENCH_DIR / "generated"),
		help="Output directory for generated mem/vector files",
	)
	parser.add_argument(
		"-r",
		"--random-cases",
		type=int,
		default=DEFAULT_RANDOM_CASES,
		help="Number of deterministic pseudo-random cases",
	)
	args = parser.parse_args()

	LOGS_DIR.mkdir(parents=True, exist_ok=True)
	run_tag = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
	log_file = LOGS_DIR / f"test_vectors_{run_tag}.log"
	log_file.write_text(
		"SHAKE256 test vector generation\n"
		f"run_tag={run_tag}\n"
		f"output_dir={args.output_dir}\n"
		f"random_cases={args.random_cases}\n",
		encoding="utf-8",
	)

	if args.random_cases < 0:
		print("[FAIL] random-cases must be >= 0")
		with log_file.open("a", encoding="utf-8") as fp:
			fp.write("[FAIL] random-cases must be >= 0\n")
		print(f"[INFO] Logs: {log_file}")
		return 2

	out_dir = Path(args.output_dir)
	cases = write_vectors(out_dir, args.random_cases)
	out_two = sum(1 for tv in cases if tv.num_out_blocks == 2)

	print(f"Generated {len(cases)} vectors in {out_dir}")
	print(f"  num_out_blocks=1: {len(cases) - out_two}")
	print(f"  num_out_blocks=2: {out_two}")

	with log_file.open("a", encoding="utf-8") as fp:
		fp.write(f"Generated {len(cases)} vectors in {out_dir}\n")
		fp.write(f"num_out_blocks=1: {len(cases) - out_two}\n")
		fp.write(f"num_out_blocks=2: {out_two}\n")

	print(f"[INFO] Logs: {log_file}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
