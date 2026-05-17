




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
async def test_fp_adder_pipeline(dut):
    """Test the 3-stage FP adder with addition and subtraction cases"""

    # 1. Start the clock (100MHz / 10ns period)
    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # 2. Reset the DUT
    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await Timer(20, unit="ns")
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Warm-up: Feed a simple operation to flush the pipeline after reset
    dut.i_operand_a.value = float_to_hex(1.0)
    dut.i_operand_b.value = float_to_hex(1.0)
    for i in range(5):
        await RisingEdge(dut.i_clk)

    # Test Case 1: Addition - 1.5 + 2.5 = 4.0
    val_a = 1.5
    val_b = 2.5
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_hex(val_a)
    dut.i_operand_b.value = float_to_hex(val_b)

    dut._log.info(f"Input hex: a=0x{float_to_hex(val_a):08X}, b=0x{float_to_hex(val_b):08X}")

    # Account for 4 pipeline stages
    for i in range(5):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 1 - Addition: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}, hex=0x{result_hex:08X}")
    assert abs(result_float - expected) < 1e-6, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 2: Subtraction - 5.0 + (-2.0) = 3.0
    val_a = 5.0
    val_b = -2.0
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_hex(val_a)
    dut.i_operand_b.value = float_to_hex(val_b)

    for i in range(5):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 2 - Subtraction: {val_a} + ({val_b}) = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-6, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 3: Subtraction - (-3.5) + 1.5 = -2.0
    val_a = -3.5
    val_b = 1.5
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_hex(val_a)
    dut.i_operand_b.value = float_to_hex(val_b)

    for i in range(5):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 3 - Subtraction: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-6, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 4: Addition of negatives - (-2.0) + (-3.0) = -5.0
    val_a = -2.0
    val_b = -3.0
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_hex(val_a)
    dut.i_operand_b.value = float_to_hex(val_b)

    for i in range(5):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = hex_to_float(result_hex)

    dut._log.info(f"Test 4 - Addition of negatives: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-6, f"Failed: Expected {expected}, got {result_float}"

@cocotb.test()
async def test_random_floats(dut):
    """Feed random floats (positive and negative) and check results after pipeline latency"""
    import random

    cocotb.start_soon(Clock(dut.i_clk, 10, unit="ns").start())

    # Reset the DUT
    dut.i_rst_n.value = 0
    dut.i_operand_a.value = 0
    dut.i_operand_b.value = 0
    await RisingEdge(dut.i_clk)
    await RisingEdge(dut.i_clk)
    dut.i_rst_n.value = 1
    await RisingEdge(dut.i_clk)

    # Test 240 random cases
    for i in range(240):
        a = random.uniform(-1.0e-30, 1.0e30)
        b = random.uniform(-1.0e-30, 1.0e30)
        # Use single precision for reference calculation to match hardware
        a_sp = np.float32(a)
        b_sp = np.float32(b)
        expected = float(np.float32(a_sp + b_sp))

        dut.i_operand_a.value = float_to_hex(a_sp)
        dut.i_operand_b.value = float_to_hex(b_sp)

        # Wait for pipeline (5 stages now: convert -> align -> add/sub -> normalize -> round to SP)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)
        await RisingEdge(dut.i_clk)

        result_hex = dut.o_sum.value.to_unsigned()
        got = hex_to_float(result_hex)
        error = abs(got - expected)

        # Detect catastrophic cancellation: large inputs, small output
        input_magnitude = max(abs(a), abs(b))
        output_magnitude = abs(expected)
        is_cancellation = (input_magnitude > 10.0) and (output_magnitude < input_magnitude * 0.1)

        # Use adaptive thresholds
        if is_cancellation:
            # For catastrophic cancellation, use absolute error relative to input magnitude
            rel_error = error / input_magnitude if input_magnitude > 0 else error
            threshold = 1e-99 # 1e-5  # Relaxed threshold for cancellation cases
        else:
            # Normal case: relative error
            rel_error = error / max(abs(expected), 1.0) if expected != 0 else error
            threshold = 1e-99 # 1e-6  # Stricter threshold for normal operations

        # Log the first few for debugging
        if i < 4:
            dut._log.info(f"Test {i}: {a_sp:.4f} + {b_sp:.4f} = {got:.4f} (exp {expected:.4f}), hex=0x{result_hex:08X}, rel_err={rel_error:.2e}")

        if rel_error >= 0.00000001:  # Log errors > 1e-8
            cancel_flag = " [CANCELLATION]" if is_cancellation else ""
            dut._log.warning(f"Large error at test {i}: {a_sp:.4f} + {b_sp:.4f} = {got:.4f} (expected {expected:.4f}), rel_error={rel_error:.2e}{cancel_flag}")

        assert rel_error < threshold, f"Test {i} failed: {a_sp} + {b_sp} = {got}, expected {expected}, rel_error={rel_error}, threshold={threshold}"

