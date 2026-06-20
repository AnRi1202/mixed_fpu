import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import math
import random

# ============================================================================
# E4M3 FP8 helpers (sign(1) | exp(4, bias=7) | mantissa(3))
#   normal : exp in [1,15]   value = (-1)^s * 2^(exp-7) * (1 + m/8)
#   The HW has no subnormal / Inf / NaN special-casing, so the testbench keeps
#   inputs and products inside the finite-normal range.
#
# This drives all FOUR lanes with independent operand pairs, so it validates:
#   - lane3 / lane1 : products extracted from the shared 25x25 multiplier
#                     (the packed-gap trick)
#   - lane2 / lane0 : products from the dedicated 4x4 multipliers
# ============================================================================

FP8_MIN_NORMAL = 2.0 ** -6
FP8_MAX_NORMAL = (1.0 + 6.0 / 8.0) * (2.0 ** 8)  # 448.0


def fp8_to_float(bits):
    bits &= 0xFF
    s = (bits >> 7) & 1
    e = (bits >> 3) & 0xF
    m = bits & 0x7
    if e == 0:
        val = (m / 8.0) * (2.0 ** -6)
    else:
        val = (1.0 + m / 8.0) * (2.0 ** (e - 7))
    return -val if s else val


def _round_half_even(x):
    f = math.floor(x)
    diff = x - f
    if diff < 0.5:
        return f
    if diff > 0.5:
        return f + 1
    return f if (f % 2 == 0) else f + 1


def float_to_fp8_rne(x):
    """Round a real value to E4M3 (round-to-nearest-even).
    Returns the 8-bit pattern, or None if not a finite normal (overflow)."""
    if x == 0.0:
        return 0
    s = 1 if x < 0 else 0
    a = abs(x)
    e = math.floor(math.log2(a))
    if e >= -6:
        m8 = (a / (2.0 ** e) - 1.0) * 8.0
        mi = _round_half_even(m8)
        if mi == 8:
            mi = 0
            e += 1
        E = e + 7
        if E >= 15:
            return None  # overflow
        if E < 1:
            return s << 7  # underflow to zero
        return (s << 7) | (E << 3) | mi
    return None  # subnormal product (HW does not special-case)


def pack(lanes):
    return ((lanes[3] & 0xFF) << 24) | ((lanes[2] & 0xFF) << 16) | \
           ((lanes[1] & 0xFF) << 8) | (lanes[0] & 0xFF)


def unpack(word, i):
    return (word >> (8 * i)) & 0xFF


def fp8_mult_ref(a_bits, b_bits):
    return float_to_fp8_rne(fp8_to_float(a_bits) * fp8_to_float(b_bits))


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_fp8x4_mult_directed(dut):
    """Directed FP8x4 multiply, one independent (a,b) pair per lane."""
    await _reset(dut)

    # (a, b) per lane -> exercises every lane with distinct values & signs.
    cases = [
        (0.5, 0.5),    # lane0 : 0.25   (dedicated 4x4)
        (1.5, 2.0),    # lane1 : 3.0    (shared mult, low window)
        (-3.0, -2.0),  # lane2 : 6.0    (dedicated 4x4)
        (4.0, -2.0),   # lane3 : -8.0   (shared mult, high window)
    ]

    a_lanes = [float_to_fp8_rne(a) for (a, _) in cases]
    b_lanes = [float_to_fp8_rne(b) for (_, b) in cases]

    dut.i_operand_a.value = pack(a_lanes)
    dut.i_operand_b.value = pack(b_lanes)
    for _ in range(3):
        await RisingEdge(dut.i_clk)

    res = dut.o_prod.value.to_unsigned()
    for i, (a, b) in enumerate(cases):
        exp_bits = fp8_mult_ref(a_lanes[i], b_lanes[i])
        got_bits = unpack(res, i)
        got = fp8_to_float(got_bits)
        exp = fp8_to_float(exp_bits)
        dut._log.info(
            f"lane{i}: {fp8_to_float(a_lanes[i])} * {fp8_to_float(b_lanes[i])} "
            f"= {got} (expected {exp}), got=0x{got_bits:02X} exp=0x{exp_bits:02X}")
        assert got_bits == exp_bits, \
            f"lane{i} failed: {a}*{b} -> 0x{got_bits:02X} ({got}), expected 0x{exp_bits:02X} ({exp})"


@cocotb.test()
async def test_fp8x4_mult_random(dut):
    """Random FP8x4 multiply; bit-accurate vs RNE reference, all 4 lanes."""
    await _reset(dut)
    random.seed(0x8C)

    def rand_normal_bits():
        # exp around the bias keeps both inputs and the product as clean normals.
        s = random.randint(0, 1)
        e = random.randint(5, 9)
        m = random.randint(0, 7)
        return (s << 7) | (e << 3) | m

    n_checked = 0
    for it in range(300):
        a_lanes = [0, 0, 0, 0]
        b_lanes = [0, 0, 0, 0]
        exp_lanes = [None, None, None, None]

        for i in range(4):
            for _ in range(20):
                ab = rand_normal_bits()
                bb = rand_normal_bits()
                ref = fp8_mult_ref(ab, bb)
                if ref is None:
                    continue
                p = fp8_to_float(ab) * fp8_to_float(bb)
                if p == 0.0 or abs(p) < FP8_MIN_NORMAL:
                    continue
                a_lanes[i], b_lanes[i], exp_lanes[i] = ab, bb, ref
                break

        dut.i_operand_a.value = pack(a_lanes)
        dut.i_operand_b.value = pack(b_lanes)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)

        res = dut.o_prod.value.to_unsigned()
        for i in range(4):
            if exp_lanes[i] is None:
                continue
            got_bits = unpack(res, i)
            if got_bits != exp_lanes[i] and n_checked < 40:
                dut._log.warning(
                    f"it{it} lane{i}: {fp8_to_float(a_lanes[i])} * {fp8_to_float(b_lanes[i])} "
                    f"-> 0x{got_bits:02X} ({fp8_to_float(got_bits)}), "
                    f"expected 0x{exp_lanes[i]:02X} ({fp8_to_float(exp_lanes[i])})")
            assert got_bits == exp_lanes[i], (
                f"it{it} lane{i} failed: 0x{a_lanes[i]:02X}*0x{b_lanes[i]:02X} -> "
                f"0x{got_bits:02X} ({fp8_to_float(got_bits)}), "
                f"expected 0x{exp_lanes[i]:02X} ({fp8_to_float(exp_lanes[i])})")
            n_checked += 1

    dut._log.info(f"random FP8x4 mult: checked {n_checked} lane-results")
    assert n_checked > 0
