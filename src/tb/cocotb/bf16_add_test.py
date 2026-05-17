import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import numpy as np

def float_to_bfloat16(f):
    """Convert Python float to BF16 (Brain Float 16) format
    BF16: 1 sign bit, 8 exponent bits (same as FP32), 7 mantissa bits
    Uses truncation (not RNE rounding) to match hardware behavior
    """
    fp32 = np.float32(f)
    # Truncate to BF16 by taking upper 16 bits
    return int(fp32.view(np.uint32) >> 16)

def bfloat16_to_float(h):
    """Convert BF16 hex to Python float"""
    # Extend BF16 to FP32 by shifting left 16 bits
    fp32_bits = np.uint32(h & 0xFFFF) << 16
    return float(fp32_bits.view(np.float32))


@cocotb.test()
async def test_bf16_adder_pipeline(dut):
    """Test the 4-stage BF16 adder with addition and subtraction cases"""

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
    dut.i_operand_a.value = float_to_bfloat16(1.0)
    dut.i_operand_b.value = float_to_bfloat16(1.0)
    for i in range(5):
        await RisingEdge(dut.i_clk)

    # Test Case 1: Addition - 1.5 + 2.5 = 4.0
    val_a = 1.5
    val_b = 2.5
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_bfloat16(val_a)
    dut.i_operand_b.value = float_to_bfloat16(val_b)

    dut._log.info(f"Input hex: a=0x{float_to_bfloat16(val_a):04X}, b=0x{float_to_bfloat16(val_b):04X}")

    # Account for 4 pipeline stages
    for i in range(5):
        await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 1 - Addition: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}, hex=0x{result_hex:04X}")
    assert abs(result_float - expected) < 1e-2, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 2: Subtraction - 5.0 + (-2.0) = 3.0
    val_a = 5.0
    val_b = -2.0
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_bfloat16(val_a)
    dut.i_operand_b.value = float_to_bfloat16(val_b)


    await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 2 - Subtraction: {val_a} + ({val_b}) = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-2, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 3: Subtraction - (-3.5) + 1.5 = -2.0
    val_a = -3.5
    val_b = 1.5
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_bfloat16(val_a)
    dut.i_operand_b.value = float_to_bfloat16(val_b)

    await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 3 - Subtraction: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-2, f"Failed: Expected {expected}, got {result_float}"

    # Test Case 4: Addition of negatives - (-2.0) + (-3.0) = -5.0
    val_a = -2.0
    val_b = -3.0
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_bfloat16(val_a)
    dut.i_operand_b.value = float_to_bfloat16(val_b)

    await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 4 - Addition of negatives: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-2, f"Failed: Expected {expected}, got {result_float}"


    # Test Case 5: Addition of negatives - (-2.0) + (-3.0) = -5.0
    val_a = -2.0
    val_b = -3.0
    expected = val_a + val_b

    dut.i_operand_a.value = float_to_bfloat16(val_a)
    dut.i_operand_b.value = float_to_bfloat16(val_b)

    await RisingEdge(dut.i_clk)

    result_hex = dut.o_sum.value.to_unsigned()
    result_float = bfloat16_to_float(result_hex)

    dut._log.info(f"Test 4 - Addition of negatives: {val_a} + {val_b} = {result_float} (expected {expected}), error={abs(result_float-expected):.2e}")
    assert abs(result_float - expected) < 1e-2, f"Failed: Expected {expected}, got {result_float}"

@cocotb.test()
async def test_bf16_random_floats(dut):
    """Feed random BF16 floats and check results after pipeline latency"""
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
    # BF16 has same range as FP32 (8-bit exponent) but less precision (7-bit mantissa)
    for i in range(240):
        # Use moderate range
        a = random.uniform(-1.0e6, 1.0e6)
        b = random.uniform(-1.0e6, 1.0e6)
        
        # Convert to BF16 precision for reference calculation
        # Python doesn't have native BF16, so we use the conversion functions
        a_bf16_hex = float_to_bfloat16(a)
        b_bf16_hex = float_to_bfloat16(b)
        a_bf16 = bfloat16_to_float(a_bf16_hex)
        b_bf16 = bfloat16_to_float(b_bf16_hex)
        
        # Expected result in BF16 precision
        expected_fp32 = np.float32(a_bf16 + b_bf16)
        expected = bfloat16_to_float(float_to_bfloat16(expected_fp32))

        dut.i_operand_a.value = a_bf16_hex
        dut.i_operand_b.value = b_bf16_hex

        # Wait for pipeline (4 stages)
        for _ in range(5):
            await RisingEdge(dut.i_clk)

        result_hex = dut.o_sum.value.to_unsigned()
        got = bfloat16_to_float(result_hex)
        error = abs(got - expected)

        # Detect catastrophic cancellation: large inputs, small output
        input_magnitude = max(abs(a_bf16), abs(b_bf16))
        output_magnitude = abs(expected)
        is_cancellation = (input_magnitude > 10.0) and (output_magnitude < input_magnitude * 0.1)

        # Use adaptive thresholds - BF16 has less precision than FP32
        if is_cancellation:
            # For catastrophic cancellation, use absolute error relative to input magnitude
            rel_error = error / input_magnitude if input_magnitude > 0 else error
            threshold = 5e-2  # Relaxed threshold for BF16 cancellation cases
        else:
            # Normal case: relative error
            # BF16 has ~2-3 decimal digits of precision
            rel_error = error / max(abs(expected), 1.0) if expected != 0 else error
            threshold = 1e-2

        # Log the first few for debugging
        if i < 4:
            dut._log.info(f"Test {i}: {a_bf16:.4f} + {b_bf16:.4f} = {got:.4f} (exp {expected:.4f}), hex=0x{result_hex:04X}, rel_err={rel_error:.2e}")

        if rel_error >= 1e-2:  # Log errors > 1e-2
            cancel_flag = " [CANCELLATION]" if is_cancellation else ""
            dut._log.warning(f"Large error at test {i}: {a_bf16:.4f} + {b_bf16:.4f} = {got:.4f} (expected {expected:.4f}), rel_error={rel_error:.2e}{cancel_flag}")

        assert rel_error < threshold, f"Test {i} failed: {a_bf16} + {b_bf16} = {got}, expected {expected}, rel_error={rel_error}, threshold={threshold}"
