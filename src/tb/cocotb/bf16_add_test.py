import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np
import random

# ============================================================================
# BF16 helpers  (sign(1) | exp(8, bias=127) | mantissa(7))
# Uses RNE rounding to match hardware behavior.
#
# Tests drive BOTH lanes (hi=[31:16], lo=[15:0]) with independent pairs.
# ============================================================================


def float_to_bf16(f):
    bits = int(np.float32(f).view(np.uint32))
    rnd = (bits >> 15) & 1
    sticky = bits & 0x7FFF
    trunc = bits >> 16
    if rnd and (sticky or (trunc & 1)):
        trunc += 1
    return trunc & 0xFFFF


def bf16_to_float(h):
    fp32_bits = np.uint32(h & 0xFFFF) << 16
    return float(fp32_bits.view(np.float32))


def bf16_add_ref(a_bits, b_bits):
    s = np.float32(bf16_to_float(a_bits)) + np.float32(bf16_to_float(b_bits))
    return float_to_bf16(float(s))


def pack(lanes):
    return ((lanes[1] & 0xFFFF) << 16) | (lanes[0] & 0xFFFF)


def unpack(word, i):
    return (word >> (16 * i)) & 0xFFFF


async def _reset(dut):
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())
    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)


@cocotb.test()
async def test_bf16x2_add_directed(dut):
    """Directed BF16x2 addition, one independent (a,b) pair per lane."""
    await _reset(dut)

    cases = [
        (1.5, 2.5),     # lo : 4.0
        (-3.0, 5.0),    # hi : 2.0
    ]

    a_lanes = [float_to_bf16(a) for (a, _) in cases]
    b_lanes = [float_to_bf16(b) for (_, b) in cases]

    dut.i_operand_a.value = pack(a_lanes)
    dut.i_operand_b.value = pack(b_lanes)
    for _ in range(5):
        await RisingEdge(dut.i_clk)

    res = dut.o_sum.value.to_unsigned()
    for i, (a, b) in enumerate(cases):
        exp_bits = bf16_add_ref(a_lanes[i], b_lanes[i])
        got_bits = unpack(res, i)
        got = bf16_to_float(got_bits)
        exp = bf16_to_float(exp_bits)
        lane = "lo" if i == 0 else "hi"
        dut._log.info(
            f"lane_{lane}: {bf16_to_float(a_lanes[i])} + {bf16_to_float(b_lanes[i])} "
            f"= {got} (expected {exp}), got=0x{got_bits:04X} exp=0x{exp_bits:04X}")
        assert got_bits == exp_bits, \
            f"lane_{lane} failed: {a}+{b} -> 0x{got_bits:04X} ({got}), expected 0x{exp_bits:04X} ({exp})"


@cocotb.test()
async def test_bf16x2_add_random(dut):
    """Random BF16x2 addition; bit-accurate vs truncation reference, both lanes."""
    await _reset(dut)
    random.seed(0xBF)

    n_checked = 0
    for it in range(300):
        a_lanes = [0, 0]
        b_lanes = [0, 0]
        exp_lanes = [None, None]

        for i in range(2):
            for _ in range(20):
                a = random.uniform(-1.0e6, 1.0e6)
                b = random.uniform(-1.0e6, 1.0e6)
                ab = float_to_bf16(a)
                bb = float_to_bf16(b)
                ref = bf16_add_ref(ab, bb)
                s = bf16_to_float(ab) + bf16_to_float(bb)
                if s == 0.0 or abs(s) < abs(bf16_to_float(ab)) * 2**-7:
                    continue
                a_lanes[i], b_lanes[i], exp_lanes[i] = ab, bb, ref
                break

        dut.i_operand_a.value = pack(a_lanes)
        dut.i_operand_b.value = pack(b_lanes)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)

        res = dut.o_sum.value.to_unsigned()
        for i in range(2):
            if exp_lanes[i] is None:
                continue
            got_bits = unpack(res, i)
            lane = "lo" if i == 0 else "hi"
            if got_bits != exp_lanes[i] and n_checked < 40:
                dut._log.warning(
                    f"it{it} lane_{lane}: {bf16_to_float(a_lanes[i])} + {bf16_to_float(b_lanes[i])} "
                    f"-> 0x{got_bits:04X} ({bf16_to_float(got_bits)}), "
                    f"expected 0x{exp_lanes[i]:04X} ({bf16_to_float(exp_lanes[i])})")
            assert got_bits == exp_lanes[i], (
                f"it{it} lane_{lane} failed: 0x{a_lanes[i]:04X}+0x{b_lanes[i]:04X} -> "
                f"0x{got_bits:04X} ({bf16_to_float(got_bits)}), "
                f"expected 0x{exp_lanes[i]:04X} ({bf16_to_float(exp_lanes[i])})")
            n_checked += 1

    dut._log.info(f"random BF16x2 add: checked {n_checked} lane-results")
    assert n_checked > 0
