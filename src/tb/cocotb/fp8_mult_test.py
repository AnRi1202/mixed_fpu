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
        return sign << 7
    if exp_field > 15:
        return (sign << 7) | (15 << 3) | 0x7
    mant = af / (2.0 ** e) - 1.0
    mant_bits = int(mant * 8.0)
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
        return sign * (2.0 ** (1 - 7)) * (mant / 8.0)
    return sign * (2.0 ** (exp_field - 7)) * (1.0 + mant / 8.0)


def fp8_ulp(x):
    """Gap between adjacent E4M3 values around magnitude |x|."""
    ax = abs(x)
    if ax == 0.0:
        return 2.0 ** (1 - 7 - 3)
    e = math.floor(math.log2(ax))
    exp_field = e + 7
    if exp_field < 1:
        exp_field = 1
    if exp_field > 15:
        exp_field = 15
    return 2.0 ** (exp_field - 7 - 3)


@cocotb.test()
async def test_fp8_mult_pipeline(dut):
    """Test the FP8 (E4M3) multiplier with various multiplication cases"""

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # Reset
    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Warm-up
    dut.i_a.value = float_to_fp8_e4m3(1.0)
    dut.i_b.value = float_to_fp8_e4m3(1.0)
    for i in range(4):
        await RisingEdge(dut.i_clk)

    # Exactly E4M3-representable values and results.
    cases = [
        (2.0, 3.0),    # 6.0
        (4.0, -2.0),   # -8.0
        (1.5, 2.0),    # 3.0
        (0.5, 0.5),    # 0.25
        (-3.0, -2.0),  # 6.0
    ]

    for idx, (val_a, val_b) in enumerate(cases, start=1):
        expected = val_a * val_b

        dut.i_a.value = float_to_fp8_e4m3(val_a)
        dut.i_b.value = float_to_fp8_e4m3(val_b)

        for _ in range(4):
            await RisingEdge(dut.i_clk)

        result_hex = dut.o_prod.value.to_unsigned()
        result_float = fp8_e4m3_to_float(result_hex)

        tol = fp8_ulp(expected) + 1e-9
        error = abs(result_float - expected)
        dut._log.info(
            f"Test {idx}: {val_a} * {val_b} = {result_float} "
            f"(expected {expected}), error={error:.3e}, hex=0x{result_hex:02X}"
        )
        assert error <= tol, (
            f"Test {idx} failed: {val_a} * {val_b} = {result_float}, "
            f"expected {expected}, error={error}, tol={tol}"
        )


@cocotb.test()
async def test_fp8_random_mult(dut):
    """Feed random FP8 (E4M3) floats and check multiplication results"""
    import random

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Keep the product inside the E4M3 normal range (|prod| < ~240).
    for i in range(100):
        a = random.uniform(-8.0, 8.0)
        b = random.uniform(-8.0, 8.0)

        a_hex = float_to_fp8_e4m3(a)
        b_hex = float_to_fp8_e4m3(b)
        a_fp8 = fp8_e4m3_to_float(a_hex)
        b_fp8 = fp8_e4m3_to_float(b_hex)

        expected = a_fp8 * b_fp8

        dut.i_a.value = a_hex
        dut.i_b.value = b_hex

        for _ in range(4):
            await RisingEdge(dut.i_clk)

        result_hex = dut.o_prod.value.to_unsigned()
        got = fp8_e4m3_to_float(result_hex)
        error = abs(got - expected)

        # Allow up to 1 ULP of rounding error around the ideal product.
        tol = fp8_ulp(expected) + 1e-9

        if i < 4:
            dut._log.info(
                f"Test {i}: {a_fp8:.3f} * {b_fp8:.3f} = {got:.3f} "
                f"(exp {expected:.3f}), hex=0x{result_hex:02X}, err={error:.3e}"
            )

        assert error <= tol, (
            f"Test {i} failed: {a_fp8} * {b_fp8} = {got}, expected {expected}, "
            f"error={error}, tol={tol}"
        )
