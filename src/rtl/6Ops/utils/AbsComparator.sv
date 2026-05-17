`timescale 1ns/1ps
import FpuPkg::*;

module AbsComparator (
    input  FpFmt_e     fmt,
    input  FpVec_u operandX,
    input  FpVec_u operandY,
    output logic        swapLo, // FP16x2: lane.lo |operandX| < |operandY|
    output logic        swapHi  // FP16x2: lane.hi |operandX| < |operandY|, FMT_FP32: |operandX|<|operandY|
);


    // -----------------------
    // segmented subtraction: a - b (unsigned)
    // a - b = a + ~b + 1
    // A<B  <=> carry_out == 0  <=> ~carry_out
    // -----------------------

    logic [15:0] x_lo;
    logic [14:0] x_hi;
    logic [15:0] y_lo;
    logic [14:0] y_hi;

    always_comb begin
        x_lo = operandX.lanes.lo;
        x_hi = operandX.lanes.hi[14:0];
        y_lo = operandY.lanes.lo;
        y_hi = operandY.lanes.hi[14:0];
        
        if (fmt == FMT_FP16) begin
            x_lo[15] = 1'b0;
            y_lo[15] = 1'b0;
        end
    end

    logic [16:0] sub_lo;
    logic        c16;

    assign sub_lo = {1'b0, x_lo} + {1'b0, ~y_lo} + 17'd1;
    assign c16    = sub_lo[16];

    logic cin_hi;
    assign cin_hi = (fmt == FMT_FP16) ? 1'b1 : c16; // Key shared logic: carry propagation control

    logic [15:0] sub_hi;
    logic        c32;

    assign sub_hi = {1'b0, x_hi} + {1'b0, ~y_hi} + {15'd0, cin_hi};
    assign c32    = sub_hi[15];

    // borrow = ~carry_out
    assign swapLo = ~c16; // lane.lo: a_lo < b_lo
    assign swapHi = ~c32; // lane.hi (FMT_FP16) or entire 32-bit (FMT_FP32)
endmodule : AbsComparator
