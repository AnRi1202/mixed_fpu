import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import math
import random

# ============================================================================
# E4M3 FP8 helpers
#   format : sign(1) | exp(4, bias=7) | mantissa(3)
#   normal : exp in [1,15]   value = (-1)^s * 2^(exp-7) * (1 + m/8)
#   subnorm: exp == 0        value = (-1)^s * 2^(-6)    * (m/8)
#   (specials such as exp==15&m==7 (NaN) are avoided by the testbench)
# ============================================================================

FP8_MIN_NORMAL = 2.0 ** -6        # smallest positive normal (0.015625)
FP8_MAX_NORMAL = (1.0 + 6.0 / 8.0) * (2.0 ** 8)  # 448.0 (exp=15,m=6)


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
    return f if (f % 2 == 0) else f + 1  # tie -> nearest even


def float_to_fp8_rne(x):
    """Round a real value to E4M3 (round-to-nearest-even).
    Returns the 8-bit pattern, or None if the value is not representable
    as a finite E4M3 normal/subnormal (overflow)."""
    if x == 0.0:
        return 0
    s = 1 if x < 0 else 0
    a = abs(x)
    e = math.floor(math.log2(a))
    if e >= -6:  # normal candidate
        m8 = (a / (2.0 ** e) - 1.0) * 8.0
        mi = _round_half_even(m8)
        if mi == 8:
            mi = 0
            e += 1
        E = e + 7
        if E >= 15:
            return None  # overflow (no Inf in E4M3; max finite is 448)
        if E < 1:
            return s << 7  # underflow to zero
        return (s << 7) | (E << 3) | mi
    else:  # subnormal
        mi = _round_half_even(a / (2.0 ** -9))
        if mi <= 0:
            return s << 7
        if mi >= 8:
            return (s << 7) | (1 << 3)  # rounds up to smallest normal
        return (s << 7) | mi


def pack(lanes):
    """lanes[0..3] -> 32-bit word (lane3 is the MSB byte)."""
    return ((lanes[3] & 0xFF) << 24) | ((lanes[2] & 0xFF) << 16) | \
           ((lanes[1] & 0xFF) << 8) | (lanes[0] & 0xFF)


def unpack(word, i):
    return (word >> (8 * i)) & 0xFF


def fp8_add_ref(a_bits, b_bits):
    """Bit-accurate reference: exact sum of the two FP8 values, RNE back to FP8."""
    return float_to_fp8_rne(fp8_to_float(a_bits) + fp8_to_float(b_bits))


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_fp8_directed(dut):
    """Directed FP8x4 cases, one independent (a,b) pair per lane."""
    await _reset(dut)

    # (a, b) per lane -> tests addition, subtraction and sign handling at once.
    cases = [
        (1.5, 2.5),    # lane0 : 4.0
        (5.0, -2.0),   # lane1 : 3.0
        (-3.5, 1.5),   # lane2 : -2.0
        (-2.0, -3.0),  # lane3 : -5.0
    ]

    a_lanes = [float_to_fp8_rne(a) for (a, _) in cases]
    b_lanes = [float_to_fp8_rne(b) for (_, b) in cases]

    dut.i_operand_a.value = pack(a_lanes)
    dut.i_operand_b.value = pack(b_lanes)
    for _ in range(3):
        await RisingEdge(dut.i_clk)

    res = dut.o_sum.value.to_unsigned()
    for i, (a, b) in enumerate(cases):
        exp_bits = fp8_add_ref(a_lanes[i], b_lanes[i])
        got_bits = unpack(res, i)
        got = fp8_to_float(got_bits)
        exp = fp8_to_float(exp_bits)
        dut._log.info(
            f"lane{i}: {fp8_to_float(a_lanes[i])} + {fp8_to_float(b_lanes[i])} "
            f"= {got} (expected {exp}), got=0x{got_bits:02X} exp=0x{exp_bits:02X}")
        assert got_bits == exp_bits, \
            f"lane{i} failed: {a}+{b} -> 0x{got_bits:02X} ({got}), expected 0x{exp_bits:02X} ({exp})"


@cocotb.test()
async def test_fp8_random(dut):
    """Random FP8x4 addition; bit-accurate vs RNE reference."""
    await _reset(dut)
    random.seed(0xF8)

    def rand_normal_bits():
        # exp in [4,11] keeps inputs as clean normals; mantissa free.
        s = random.randint(0, 1)
        e = random.randint(4, 11)
        m = random.randint(0, 7)
        return (s << 7) | (e << 3) | m

    n_checked = 0
    for it in range(300):
        a_lanes = [0, 0, 0, 0]
        b_lanes = [0, 0, 0, 0]
        exp_lanes = [None, None, None, None]

        for i in range(4):
            # regenerate until the lane lands on a checkable (finite normal) result
            for _ in range(20):
                ab = rand_normal_bits()
                bb = rand_normal_bits()
                ref = fp8_add_ref(ab, bb)
                if ref is None:
                    continue
                s = fp8_to_float(ab) + fp8_to_float(bb)
                if s == 0.0 or abs(s) < FP8_MIN_NORMAL:
                    continue  # skip zero / subnormal results (no special-case HW)
                a_lanes[i], b_lanes[i], exp_lanes[i] = ab, bb, ref
                break

        dut.i_operand_a.value = pack(a_lanes)
        dut.i_operand_b.value = pack(b_lanes)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)

        res = dut.o_sum.value.to_unsigned()
        for i in range(4):
            if exp_lanes[i] is None:
                continue
            got_bits = unpack(res, i)
            if got_bits != exp_lanes[i] and n_checked < 40:
                dut._log.warning(
                    f"it{it} lane{i}: {fp8_to_float(a_lanes[i])} + {fp8_to_float(b_lanes[i])} "
                    f"-> 0x{got_bits:02X} ({fp8_to_float(got_bits)}), "
                    f"expected 0x{exp_lanes[i]:02X} ({fp8_to_float(exp_lanes[i])})")
            assert got_bits == exp_lanes[i], (
                f"it{it} lane{i} failed: 0x{a_lanes[i]:02X}+0x{b_lanes[i]:02X} -> "
                f"0x{got_bits:02X} ({fp8_to_float(got_bits)}), "
                f"expected 0x{exp_lanes[i]:02X} ({fp8_to_float(exp_lanes[i])})")
            n_checked += 1

    dut._log.info(f"random FP8x4: checked {n_checked} lane-results")
    assert n_checked > 0
