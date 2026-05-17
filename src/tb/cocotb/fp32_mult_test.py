import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import struct
import numpy as np

def float_to_hex(f):
    # Pack float into IEEE 754 32-bit and unpack as unsigned int
    return struct.unpack('<I', struct.pack('<f', f))[0]

def hex_to_float(h):
    # Pack unsigned int and unpack as IEEE 754 32-bit float
    return struct.unpack('<f', struct.pack('<I', h))[0]


@cocotb.test()
async def test_fp_mult_pipeline(dut):
    """Test the 3-stage FP multiplier with various multiplication cases"""

    # 1. Start the clock (100MHz / 10ns period)
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # 2. Reset the DUT
    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Warm-up: Feed a simple operation to flush the pipeline after reset
    dut.i_a.value = float_to_hex(1.0)
    dut.i_b.value = float_to_hex(1.0)
    for i in range(4):
        await RisingEdge(dut.i_clk)

    # Test Case 1: Basic multiplication - 2.0 * 3.0 = 6.0
    val_a = 2.0
    val_b = 3.0
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    dut._log.info(f"Input hex: a=0x{float_to_hex(val_a):08X}, b=0x{float_to_hex(val_b):08X}")

    # Account for 3 pipeline stages
    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 1 - Multiplication: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}, hex=0x{result_hex:08X}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 2: Negative multiplication - 4.0 * (-2.0) = -8.0
    val_a = 4.0
    val_b = -2.0
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 2 - Negative multiplication: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 3: Two negatives - (-3.0) * (-5.0) = 15.0
    val_a = -3.0
    val_b = -5.0
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 3 - Two negatives: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 4: Fractional multiplication - 1.5 * 2.5 = 3.75
    val_a = 1.5
    val_b = 2.5
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 4 - Fractional multiplication: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 5: Small numbers - 0.125 * 0.25 = 0.03125
    val_a = 0.125
    val_b = 0.25
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 5 - Small numbers: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 6: Large numbers - 100.0 * 200.0 = 20000.0
    val_a = 100.0
    val_b = 200.0
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 6 - Large numbers: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"


@cocotb.test()
async def test_random_mult(dut):
    """Feed random floats and check multiplication results after pipeline latency"""
    import random

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # Reset the DUT
    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Test 240 random cases
    for i in range(240):
        # Use smaller range to avoid overflow/underflow
        # FP32 exponent range is roughly 1e-38 to 1e38
        # To avoid overflow in multiplication, use sqrt of max range
        a = random.uniform(-1.0e-30, 1.0e30)
        b = random.uniform(-1.0e-30, 1.0e30)

        # Use single precision for reference calculation to match hardware
        a_sp = np.float32(a)
        b_sp = np.float32(b)
        expected = float(np.float32(a_sp * b_sp))

        dut.i_a.value = float_to_hex(a_sp)
        dut.i_b.value = float_to_hex(b_sp)

        # Wait for pipeline (3 stages)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)

        result_hex = dut.o_prod.value.to_unsigned()
        got = hex_to_float(result_hex)
        error = abs(got - expected)

        # Handle special cases (infinity, NaN, zero)
        import math
        if math.isnan(expected) or math.isnan(got):
            # If either is NaN, they should both be NaN
            if math.isnan(expected) and math.isnan(got):
                rel_error = 0.0  # Both NaN, consider it a match
            else:
                rel_error = float('inf')
        elif math.isinf(expected) or math.isinf(got):
            # If both are infinity with same sign, consider it a match
            if math.isinf(expected) and math.isinf(got) and (expected > 0) == (got > 0):
                rel_error = 0.0
            else:
                rel_error = float('inf')
        elif expected == 0 and got == 0:
            # Both zero
            rel_error = 0.0
        elif expected != 0:
            rel_error = error / abs(expected)
        else:
            rel_error = error

        # Log the first few for debugging
        if i < 4:
            dut._log.info(f"Test {i}: {float(a_sp):.6e} * {float(b_sp):.6e} = {got:.6e} (exp {expected:.6e}), hex=0x{result_hex:08X}, rel_err={rel_error:.2e}")

        # Multiplication can accumulate more error due to mantissa multiplication
        threshold = 1e-99

        if rel_error >= 1e-99:  # Log significant errors
            dut._log.warning(f"Large error at test {i}: {float(a_sp):.6e} * {float(b_sp):.6e} = {got:.6e} (expected {expected:.6e}), rel_error={rel_error:.2e}")

        assert rel_error < threshold, f"Test {i} failed: {float(a_sp)} * {float(b_sp)} = {got}, expected {expected}, rel_error={rel_error}, threshold={threshold}"


@cocotb.test()
async def test_special_cases(dut):
    """Test special multiplication cases"""

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # Reset the DUT
    dut.i_rst_n.value = 0
    dut.i_a.value = 0
    dut.i_b.value = 0
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Test Case: Multiply by 1.0
    val_a = 42.0
    val_b = 1.0
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Special 1 - Multiply by 1: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case: Multiply by 0.5 (shift exponent)
    val_a = 8.0
    val_b = 0.5
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Special 2 - Multiply by 0.5: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"

    # Test Case: Powers of 2 (exact representation)
    val_a = 16.0
    val_b = 4.0
    expected = val_a * val_b

    dut.i_a.value = float_to_hex(val_a)
    dut.i_b.value = float_to_hex(val_b)

    for i in range(4):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_prod.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Special 3 - Powers of 2: {val_a} * {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-99, f"Failed: Expected {expected}, got {result_float}"
