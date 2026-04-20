import hashlib
import sys
from pathlib import Path

R = Path(__file__).resolve().parent
IMPL = R.parent
VECTORS = IMPL / "vectors"

RATE = 136
MAX_OUT = 2
RANDOM_DEFAULT = 256
RNG_SEED = 0x1A2B3C4D
FIXED = 4
EXHAUSTIVE = RATE + 1
BASE = FIXED + EXHAUSTIVE


def xorshift32(s: int) -> int: 
    s &= 0xFFFFFFFF
    s ^= (s << 13) & 0xFFFFFFFF
    s ^= (s >> 17) & 0xFFFFFFFF
    s ^= (s << 5) & 0xFFFFFFFF
    return s

def add_case(cases: list, msg: bytes, out_blocks: int): #Tạo và thêm test case với padding chuẩn."""
    if not (1 <= out_blocks <= MAX_OUT):
        raise ValueError("out_blocks must be 1 or 2")
    if len(msg) > RATE:
        raise ValueError("msg too long")

    # Dùng ljust để đệm byte 0 vào cuối, đọc phát hiểu ngay thay vì cộng chuỗi
    msg_block = msg.ljust(RATE, b'\0')
    dlen = out_blocks * RATE
    
    # Sinh hash và đệm cho đủ MAX_OUT * RATE
    digest = hashlib.shake_256(msg).digest(dlen)
    out_buf = digest.ljust(MAX_OUT * RATE, b'\0')
    
    cases.append((len(msg), out_blocks, msg_block, out_buf))

def gen_cases(random_cases: int) -> list:
    cases = []
    
    # Fixed cases
    add_case(cases, b"", 1)
    add_case(cases, b"a", 2)
    add_case(cases, b"abc", 1)
    add_case(cases, bytes(range(RATE)), 2)

    # Exhaustive cases
    for mlen in range(EXHAUSTIVE):
        msg = bytes((j * 29 + mlen * 7) & 0xFF for j in range(mlen))
        add_case(cases, msg, 2 if len(cases) % 2 != 0 else 1)

    # Random cases
    s = RNG_SEED
    for _ in range(random_cases):
        s = xorshift32(s)
        mlen = s % EXHAUSTIVE
        
        s = xorshift32(s)
        out_blocks = 2 if (s & 1) else 1
        
        mb = bytearray()
        for _ in range(mlen):
            s = xorshift32(s)
            mb.append(s & 0xFF)
            
        add_case(cases, bytes(mb), out_blocks)

    return cases

def write_vectors(out_dir: Path, random_cases: int) -> list:
    out_dir.mkdir(parents=True, exist_ok=True)
    cases = gen_cases(random_cases)

    # Dùng list các file cần mở để code không bị thụt lề quá sâu
    with open(out_dir / "tv_msg_len.mem", "w") as f_len, \
         open(out_dir / "tv_num_out_blocks.mem", "w") as f_num, \
         open(out_dir / "tv_msg_block.mem", "w") as f_msg, \
         open(out_dir / "tv_kat_expected_block0.mem", "w") as f_out0, \
         open(out_dir / "tv_kat_expected_block1.mem", "w") as f_out1:

        for msg_len, num_out, msg_block, out_bytes in cases:
            f_len.write(f"{msg_len:02x}\n")
            f_num.write(f"{num_out:02x}\n")
            
            # [::-1].hex() là cách lật ngược byte và chuyển sang hex tự nhiên nhất của Python
            f_msg.write(f"{msg_block[::-1].hex()}\n")
            f_out0.write(f"{out_bytes[:RATE][::-1].hex()}\n")
            f_out1.write(f"{out_bytes[RATE:2*RATE][::-1].hex()}\n")

    return cases

def clear_vectors(out_dir: Path) -> None:
    if not out_dir.exists():
        print(f"No vector directory: {out_dir}")
        return
        
    script_name = Path(__file__).name
    removed = 0
    
    # Vòng lặp dọn dẹp đơn giản, rõ ràng, bỏ qua try/except thừa
    for p in out_dir.iterdir():
        if p.is_file() and p.name != script_name:
            p.unlink(missing_ok=True)
            removed += 1
            
    print(f"Cleared {removed} files in {out_dir}")

def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1].lower() == "clear":
        clear_vectors(VECTORS)
        return 0
        
    if len(sys.argv) > 1:
        total = int(sys.argv[1])
        if total < BASE:
            print(f"total must be >= {BASE}")
            return 2
        random_cases = total - BASE
    else:
        random_cases = RANDOM_DEFAULT

    cases = write_vectors(VECTORS, random_cases)
    print(f"Generated {len(cases)} vectors in {VECTORS}")
    return 0

if __name__ == "__main__":
    sys.exit(main())