import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import math


def float_to_fp8_e4m3(f):
    """Convert a Python float to E4M3 FP8 format.
    E4M3: 1 sign bit, 4 exponent bits (bias 7), 3 mantissa bits.
    Mantissa is truncated toward zero to match the hardware datapath.
    Subnormals/overflow are flushed/saturated (kept out of the test range).
    """
    if f == 0.0 or math.isnan(f):
        return 0
    sign = 1 if f < 0 else 0
    af = abs(f)
    e = math.floor(math.log2(af))
    exp_field = e + 7
    if exp_field < 1:
        # underflow -> flush to (signed) zero
        return sign << 7
    if exp_field > 15:
        # overflow -> saturate to largest magnitude
        return (sign << 7) | (15 << 3) | 0x7
    mant = af / (2.0 ** e) - 1.0  # fractional part in [0, 1)
    mant_bits = int(mant * 8.0)   # truncate to 3 bits
    if mant_bits > 7:
        mant_bits = 7
    return (sign << 7) | (exp_field << 3) | mant_bits


def fp8_e4m3_to_float(h):
    """Convert an E4M3 FP8 byte to a Python float."""
    h &= 0xFF
    sign = -1.0 if (h >> 7) & 1 else 1.0
    exp_field = (h >> 3) & 0xF
    mant = h & 0x7
    if exp_field == 0:
        # subnormal: value = sign * 2^(1-7) * (mant/8)
        return sign * (2.0 ** (1 - 7)) * (mant / 8.0)
    return sign * (2.0 ** (exp_field - 7)) * (1.0 + mant / 8.0)


def fp8_ulp(x):
    """Gap between adjacent E4M3 values around magnitude |x|."""
    ax = abs(x)
    if ax == 0.0:
        return 2.0 ** (1 - 7 - 3)  # smallest subnormal step
    e = math.floor(math.log2(ax))
    exp_field = e + 7
    if exp_field < 1:
        exp_field = 1
    if exp_field > 15:
        exp_field = 15
    return 2.0 ** (exp_field - 7 - 3)


@cocotb.test()
async def test_fp8_adder_pipeline(dut):
    """Test the FP8 (E4M3) adder with addition and subtraction cases"""

    # 1. Start the clock (100MHz / 10ns period)
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # 2. Reset the DUT
    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Warm-up: flush the pipeline after reset
    dut.i_operand_a.value = float_to_fp8_e4m3(1.0)
    dut.i_operand_b.value = float_to_fp8_e4m3(1.0)
    for i in range(5):
        await RisingEdge(dut.i_clk)

    # All cases use exactly E4M3-representable values and results.
    cases = [
        (1.5, 2.5),    # 4.0
        (5.0, -2.0),   # 3.0
        (-3.5, 1.5),   # -2.0
        (-2.0, -3.0),  # -5.0
        (0.5, 0.25),   # 0.75
    ]

    for idx, (val_a, val_b) in enumerate(cases, start=1):
        expected = val_a + val_b

        dut.i_operand_a.value = float_to_fp8_e4m3(val_a)
        dut.i_operand_b.value = float_to_fp8_e4m3(val_b)

        dut._log.info(
            f"Input hex: a=0x{float_to_fp8_e4m3(val_a):02X}, "
            f"b=0x{float_to_fp8_e4m3(val_b):02X}"
        )

        # Account for the pipeline stages
        for _ in range(5):
            await RisingEdge(dut.i_clk)

        result_hex = dut.o_sum.value.to_unsigned()
        result_float = fp8_e4m3_to_float(result_hex)

        tol = fp8_ulp(expected) + 1e-9
        error = abs(result_float - expected)
        dut._log.info(
            f"Test {idx}: {val_a} + {val_b} = {result_float} "
            f"(expected {expected}), error={error:.3e}, hex=0x{result_hex:02X}"
        )
        assert error <= tol, (
            f"Test {idx} failed: {val_a} + {val_b} = {result_float}, "
            f"expected {expected}, error={error}, tol={tol}"
        )


@cocotb.test()
async def test_fp8_random_floats(dut):
    """Feed random FP8 (E4M3) floats and check results after pipeline latency"""
    import random

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # E4M3 normal range is narrow; keep magnitudes well inside it.
    for i in range(240):
        a = random.uniform(-15.0, 15.0)
        b = random.uniform(-15.0, 15.0)

        a_hex = float_to_fp8_e4m3(a)
        b_hex = float_to_fp8_e4m3(b)
        a_fp8 = fp8_e4m3_to_float(a_hex)
        b_fp8 = fp8_e4m3_to_float(b_hex)

        # Ideal real sum of the actual FP8 operands.
        expected = a_fp8 + b_fp8

        dut.i_operand_a.value = a_hex
        dut.i_operand_b.value = b_hex

        for _ in range(5):
            await RisingEdge(dut.i_clk)

        result_hex = dut.o_sum.value.to_unsigned()
        got = fp8_e4m3_to_float(result_hex)
        error = abs(got - expected)

        # Allow up to 1 ULP of rounding error around the ideal sum.
        tol = fp8_ulp(expected) + 1e-9

        if i < 4:
            dut._log.info(
                f"Test {i}: {a_fp8:.4f} + {b_fp8:.4f} = {got:.4f} "
                f"(exp {expected:.4f}), hex=0x{result_hex:02X}, err={error:.3e}"
            )

        if error > tol:
            dut._log.warning(
                f"Large error at test {i}: {a_fp8:.4f} + {b_fp8:.4f} = {got:.4f} "
                f"(expected {expected:.4f}), error={error:.3e}, tol={tol:.3e}"
            )

        assert error <= tol, (
            f"Test {i} failed: {a_fp8} + {b_fp8} = {got}, expected {expected}, "
            f"error={error}, tol={tol}"
        )
