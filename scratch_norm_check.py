import random

FP32, BF16, FP8 = 0, 1, 2
MASK28 = (1 << 28) - 1

def bits(v, hi, lo):
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)

def orred(v, hi, lo):
    return 1 if bits(v, hi, lo) != 0 else 0

# ---------------------------------------------------------------------------
# rtl_sim : line-by-line mirror of Normalizer.sv
# ---------------------------------------------------------------------------
def rtl_sim(fmt, operandX):
    prop7  = 1 if fmt != FP8 else 0
    prop14 = 1 if fmt == FP32 else 0
    prop20 = 1 if fmt != FP8 else 0

    level5 = operandX & MASK28

    def shl(v, s):
        return (v << s) & MASK28

    def assemble(e3, e2, e1, e0, sh, cur):
        out = 0
        out |= (bits(sh,27,21) if e3 else bits(cur,27,21)) << 21
        out |= (bits(sh,20,14) if e2 else bits(cur,20,14)) << 14
        out |= (bits(sh,13,7)  if e1 else bits(cur,13,7))  << 7
        out |= (bits(sh,6,0)   if e0 else bits(cur,6,0))
        return out

    def zero_range(v, hi, lo):
        m = ((1 << (hi - lo + 1)) - 1) << lo
        return v & ~m & MASK28

    # stage 16 (FP32 only)
    e16_3 = (1 if fmt == FP32 else 0) & (1 - orred(level5,27,12))
    e16_2 = e16_3; e16_1 = e16_3; e16_0 = e16_3
    sh = shl(level5,16)
    level4 = assemble(e16_3,e16_2,e16_1,e16_0,sh,level5)

    # stage 8
    e8_3 = (1 if fmt != FP8 else 0) & (1 - orred(level4,27,20))
    e8_2 = e8_3
    if fmt == FP32:   e8_1 = 1 - orred(level4,27,20)
    elif fmt == BF16: e8_1 = 1 - orred(level4,11,4)
    else:             e8_1 = 0
    e8_0 = e8_1
    sh = shl(level4,8)
    if not prop14: sh = zero_range(sh,21,14)
    level3 = assemble(e8_3,e8_2,e8_1,e8_0,sh,level4)

    # stage 4
    e4_3 = 1 - orred(level3,27,24)
    e4_2 = (1 - orred(level3,20,17)) if fmt == FP8 else (1 - orred(level3,27,24))
    if fmt == FP32:   e4_1 = 1 - orred(level3,27,24)
    elif fmt == BF16: e4_1 = 1 - orred(level3,11,8)
    else:             e4_1 = 1 - orred(level3,13,10)
    if fmt == FP32:   e4_0 = 1 - orred(level3,27,24)
    elif fmt == BF16: e4_0 = 1 - orred(level3,11,8)
    else:             e4_0 = 1 - orred(level3,6,3)
    sh = shl(level3,4)
    if not prop7:  sh = zero_range(sh,10,7)
    if not prop14: sh = zero_range(sh,17,14)
    if not prop20: sh = zero_range(sh,24,21)
    level2 = assemble(e4_3,e4_2,e4_1,e4_0,sh,level3)

    # stage 2
    e2_3 = 1 - orred(level2,27,26)
    e2_2 = (1 - orred(level2,20,19)) if fmt == FP8 else (1 - orred(level2,27,26))
    if fmt == FP32:   e2_1 = 1 - orred(level2,27,26)
    elif fmt == BF16: e2_1 = 1 - orred(level2,11,10)
    else:             e2_1 = 1 - orred(level2,13,12)
    if fmt == FP32:   e2_0 = 1 - orred(level2,27,26)
    elif fmt == BF16: e2_0 = 1 - orred(level2,11,10)
    else:             e2_0 = 1 - orred(level2,6,5)
    sh = shl(level2,2)
    if not prop7:  sh = zero_range(sh,8,7)
    if not prop14: sh = zero_range(sh,15,14)
    if not prop20: sh = zero_range(sh,22,21)
    level1 = assemble(e2_3,e2_2,e2_1,e2_0,sh,level2)

    # stage 1
    e1_3 = 1 - bits(level1,27,27)
    e1_2 = (1 - bits(level1,20,20)) if fmt == FP8 else (1 - bits(level1,27,27))
    if fmt == FP32:   e1_1 = 1 - bits(level1,27,27)
    elif fmt == BF16: e1_1 = 1 - bits(level1,11,11)
    else:             e1_1 = 1 - bits(level1,13,13)
    if fmt == FP32:   e1_0 = 1 - bits(level1,27,27)
    elif fmt == BF16: e1_0 = 1 - bits(level1,11,11)
    else:             e1_0 = 1 - bits(level1,6,6)
    sh = shl(level1,1)
    if not prop7:  sh = zero_range(sh,7,7)
    if not prop14: sh = zero_range(sh,14,14)
    if not prop20: sh = zero_range(sh,21,21)
    level0 = assemble(e1_3,e1_2,e1_1,e1_0,sh,level1)

    def cnt(e16,e8,e4,e2,e1):
        return (e16<<4)|(e8<<3)|(e4<<2)|(e2<<1)|e1
    count = [
        cnt(e16_0,e8_0,e4_0,e2_0,e1_0),
        cnt(e16_1,e8_1,e4_1,e2_1,e1_1),
        cnt(e16_2,e8_2,e4_2,e2_2,e1_2),
        cnt(e16_3,e8_3,e4_3,e2_3,e1_3),
    ]
    return level0, count

# ---------------------------------------------------------------------------
# golden : independent per-region LZC + left shift
# region = (hi_phys, lo_phys, msb_detect)
# ---------------------------------------------------------------------------
def golden_region(operandX, hi, lo, msb):
    W = hi - lo + 1
    region = bits(operandX, hi, lo)
    d = msb - lo                       # index of detection MSB inside region
    # leading zeros from bit d downward
    lz = 0
    i = d
    while i >= 0 and ((region >> i) & 1) == 0:
        lz += 1
        i -= 1
    shifted = (region << lz) & ((1 << W) - 1)
    return shifted << lo, lz

def golden(fmt, operandX):
    if fmt == FP32:
        regions = [(27,0,27)]
        lanes_of = {0:0,1:0,2:0,3:0}
    elif fmt == BF16:
        regions = [(27,14,27),(13,0,11)]   # hi, lo
        lanes_of = {3:0,2:0,1:1,0:1}
    else:
        regions = [(27,21,27),(20,14,20),(13,7,13),(6,0,6)]
        lanes_of = {3:0,2:1,1:2,0:3}
    res = 0
    lzs = []
    for (hi,lo,msb) in regions:
        part, lz = golden_region(operandX, hi, lo, msb)
        res |= part
        lzs.append(lz)
    count = [0,0,0,0]
    for lane in range(4):
        count[lane] = lzs[lanes_of[lane]]
    return res & MASK28, count

# ---------------------------------------------------------------------------
def gap_fix(fmt, v):
    # enforce the layout invariant: BF16 lo gap [13:12]=0 ; (hi gap none here)
    if fmt == BF16:
        v &= ~(0b11 << 12)
    return v & MASK28

def run(fmt, n):
    name = {FP32:"FP32",BF16:"BF16",FP8:"FP8"}[fmt]
    fails = 0
    for _ in range(n):
        v = gap_fix(fmt, random.getrandbits(28))
        r1,c1 = rtl_sim(fmt, v)
        r2,c2 = golden(fmt, v)
        if r1 != r2 or c1 != c2:
            fails += 1
            if fails <= 5:
                print(f"[{name}] MISMATCH in={v:028b}")
                print(f"   rtl    result={r1:028b} count={c1}")
                print(f"   golden result={r2:028b} count={c2}")
    # edge cases
    edge = [0, MASK28, 1, 1<<27, 1<<6, 1<<13, 1<<20, 1<<11,
            (1<<27)|(1<<13)|(1<<6)|(1<<20)]
    for v in edge:
        v = gap_fix(fmt, v)
        r1,c1 = rtl_sim(fmt, v); r2,c2 = golden(fmt, v)
        if r1 != r2 or c1 != c2:
            fails += 1
            print(f"[{name}] EDGE MISMATCH in={v:028b} rtl={r1:028b}/{c1} gold={r2:028b}/{c2}")
    print(f"[{name}] {n} random + {len(edge)} edge : {'PASS' if fails==0 else f'{fails} FAIL'}")
    return fails

random.seed(1)
total = 0
for f in (FP32, BF16, FP8):
    total += run(f, 200000)
print("ALL PASS" if total == 0 else f"TOTAL FAILS {total}")
