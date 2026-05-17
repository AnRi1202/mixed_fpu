import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np

def float_to_bfloat16(f):
    """Convert Python float to BF16 (Brain Float 16) format
    Uses truncation (not RNE rounding) to match hardware behavior
    """
    fp32 = np.float32(f)
    return int(fp32.view(np.uint32) >> 16)

def bfloat16_to_float(h):
    """Convert BF16 hex to Python float"""
    fp32_bits = np.uint32(h & 0xFFFF) << 16
    return float(fp32_bits.view(np.float32))


@cocotb.test()
async def test_bf16_mult_pipeline(dut):
    """Test the 3-stage BF16 multiplier with various multiplication cases"""

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # Reset
    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Warm-up
    dut.i_a.value = float_to_bfloat16(1.0)
    dut.i_b.value = float_to_bfloat16(1.0)
    for i in range(4):
        await RisingEdge(dut.i_clk)

    # Test Case 1: Basic multiplication - 2.0 * 3.0 = 6.0
    val_a = 2.0
    val_b = 3.0
    expected = val_a * val_b

    dut.i_a.value = float_to_bfloat16(val_a)
    dut.i_b.value = float_to_bfloat16(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 1: {val_a} * {val_b} = {result_float} (expected {expected})")
    assert abs(result_float - expected) < 1e-1, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 2: Negative multiplication
    val_a = 4.0
    val_b = -2.0
    expected = val_a * val_b

    dut.i_a.value = float_to_bfloat16(val_a)
    dut.i_b.value = float_to_bfloat16(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 2: {val_a} * {val_b} = {result_float} (expected {expected})")
    assert abs(result_float - expected) < 1e-1, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 3: Fractional
    val_a = 1.5
    val_b = 2.5
    expected = val_a * val_b

    dut.i_a.value = float_to_bfloat16(val_a)
    dut.i_b.value = float_to_bfloat16(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 3: {val_a} * {val_b} = {result_float} (expected {expected})")
    assert abs(result_float - expected) < 1e-1, f"Failed: Expected {expected}, got {result_float}"


@cocotb.test()
async def test_bf16_random_mult(dut):
    """Feed random BF16 floats and check multiplication results"""
    import random

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # BF16 has same range as FP32, use moderate values
    for i in range(100):
        a = random.uniform(-1000.0, 1000.0)
        b = random.uniform(-1000.0, 1000.0)

        a_bf16_hex = float_to_bfloat16(a)
        b_bf16_hex = float_to_bfloat16(b)
        a_bf16 = bfloat16_to_float(a_bf16_hex)
        b_bf16 = bfloat16_to_float(b_bf16_hex)

        expected_fp32 = np.float32(a_bf16 * b_bf16)
        expected = bfloat16_to_float(float_to_bfloat16(expected_fp32))

        dut.i_a.value = a_bf16_hex
        dut.i_b.value = b_bf16_hex

        for _ in range(4):
            await RisingEdge(dut.i_clk)

        result_hex = dut.o_prod.value.to_unsigned()
        got = bfloat16_to_float(result_hex)

        import math
        if math.isnan(expected) or math.isnan(got):
            if math.isnan(expected) and math.isnan(got):
                rel_error = 0.0
            else:
                rel_error = float('inf')
        elif math.isinf(expected) or math.isinf(got):
            if math.isinf(expected) and math.isinf(got) and (expected > 0) == (got > 0):
                rel_error = 0.0
            else:
                rel_error = float('inf')
        elif expected == 0 and got == 0:
            rel_error = 0.0
        elif expected != 0:
            rel_error = abs(got - expected) / abs(expected)
        else:
            rel_error = abs(got - expected)

        if i < 4:
            dut._log.info(f"Test {i}: {a_bf16:.3f} * {b_bf16:.3f} = {got:.3f} (exp {expected:.3f}), rel_err={rel_error:.2e}")

        threshold = 2e-2
        assert rel_error < threshold, f"Test {i} failed: {a_bf16} * {b_bf16} = {got}, expected {expected}, rel_error={rel_error}"
