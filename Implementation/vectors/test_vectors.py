import hashlib, sys
from pathlib import Path

# Cau hinh tham so
VECTORS = Path(__file__).resolve().parent
RATE = 136
MAX_BLOCK = 4 
RNG_SEED = 0x1A2B3C4D
BASE_CASES = 6 + (RATE + 1) # FIXED (4) + XOF_PROOF (2) + EXHAUSTIVE (137)

# Xorshift32 PRNG tao test case
def xorshift32(s):
    s = (s ^ (s << 13)) & 0xFFFFFFFF
    s = (s ^ (s >> 17)) & 0xFFFFFFFF
    return (s ^ (s << 5)) & 0xFFFFFFFF

def gen_cases(random_cases):
    def make(msg: bytes, out_blocks: int):
        out_buf = hashlib.shake_256(msg).digest(out_blocks * RATE).ljust(MAX_BLOCK * RATE, b'\0')
        return msg, out_blocks, msg.ljust(RATE, b'\0'), out_buf

    # Truong hop co dinh
    yield make(b"", 1) 
    yield make(b"a", 2) 
    yield make(b"abc", 1) 
    yield make(bytes(range(RATE)), 2) 
    yield make(b"XOF_TEST_MAX", MAX_BLOCK) 
    yield make(b"XOF_TEST_MID", 3)

    # Cac truong hop vet can
    for m in range(RATE + 1):
        # Luân phiên yêu cầu số lượng Squeeze từ 1 đến MAX_BLOCK
        yield make(bytes((j * 29 + m * 7) & 0xFF for j in range(m)), (m % MAX_BLOCK) + 1)

    # Cac truong hop random
    s = RNG_SEED
    for _ in range(random_cases):
        s = xorshift32(s); mlen = s % (RATE + 1)
        s = xorshift32(s); out_blocks = (s % MAX_BLOCK) + 1 # Random squeeze tu 1 den MAX_BLOCK
        mb = bytearray()
        for _ in range(mlen):
            s = xorshift32(s); mb.append(s & 0xFF)
        yield make(bytes(mb), out_blocks)

def main():
    if len(sys.argv) > 1 and sys.argv[1].lower() == "clear":
        for p in VECTORS.glob("tv_*"): p.unlink()
        print("Cleared vectors."); return 0

    rnd_cases = max(0, int(sys.argv[1]) - BASE_CASES) if len(sys.argv) > 1 else 0
    cases = list(gen_cases(rnd_cases))
    
    VECTORS.mkdir(parents=True, exist_ok=True)
    
    # Ghi vao file .mem
    with open(VECTORS / "tv_all.mem", "w") as f:
        for msg, n_out, m_blk, o_blk in cases:
            out_hex = "".join(o_blk[i*RATE : (i+1)*RATE][::-1].hex() for i in range(MAX_BLOCK - 1, -1, -1))
            f.write(f"{out_hex}{m_blk[::-1].hex()}{n_out:02x}{len(msg):02x}\n")

    # Ghi vao file spec
    (VECTORS / "tv_spec.txt").write_text(
        f"tv_count={len(cases)}\nrate_bytes={RATE}\nmax_squeeze_blocks={MAX_BLOCK}\n"
        f"total_cases={len(cases)}\nfixed_cases=4\nxof_proof_cases=2\n"
        f"exhaustive_length_cases={RATE + 1}\nrandom_cases={rnd_cases}\n"
    )
    
    print(f"Generated {len(cases)} vectors. Spec: {VECTORS}/tv_spec.txt")
    return 0

if __name__ == "__main__":
    sys.exit(main())