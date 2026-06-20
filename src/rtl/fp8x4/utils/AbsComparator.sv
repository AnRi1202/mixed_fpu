`timescale 1ns/1ps
import FpuPkg::*;

module AbsComparator (
    input  FpFmt_e          fmt,
    input  FpVec_u          operandX,
    input  FpVec_u          operandY,
    output logic [3:0]      swap
);

    // Per-byte operands with sign bits masked for magnitude compare
    logic [7:0] x0, x1, x2, x3;
    logic [7:0] y0, y1, y2, y3;

    // 4 x 8-bit segmented subtraction (a - b = a + ~b + 1).
    // A < B  <=>  carry_out == 0  <=>  ~carry_out
    logic [8:0] s0, s1, s2, s3;
    logic       c0, c1, c2, c3;
    logic       cin1, cin2, cin3;

    always_comb begin
        // Split both operands into byte lanes
        x0 = operandX.fp8x4.lane0;
        x1 = operandX.fp8x4.lane1;
        x2 = operandX.fp8x4.lane2;
        x3 = operandX.fp8x4.lane3;

        y0 = operandY.fp8x4.lane0;
        y1 = operandY.fp8x4.lane1;
        y2 = operandY.fp8x4.lane2;
        y3 = operandY.fp8x4.lane3;

        // Mask the sign bit of each active lane (magnitude compare)
        //   bit31 (x3[7]) : sign in every fmt   -> always masked
        //   bit23 (x2[7]) : sign in FP8         -> FP8 only
        //   bit15 (x1[7]) : sign in FP8 & BF16  -> masked unless FP32
        //   bit7  (x0[7]) : sign in FP8         -> FP8 only
        x3[7] = 1'b0;
        y3[7] = 1'b0;
        if (fmt != FMT_FP32) begin
            x1[7] = 1'b0;
            y1[7] = 1'b0;
        end
        if (fmt == FMT_FP8) begin
            x0[7] = 1'b0;
            y0[7] = 1'b0;
            x2[7] = 1'b0;
            y2[7] = 1'b0;
        end

        // Slice 0 (LSB): slice carry-in is the +1 of two's-complement subtraction
        s0   = {1'b0, x0} + {1'b0, ~y0} + 9'd1;
        c0   = s0[8];

        // Boundary @8 : cut only in FP8
        cin1 = (fmt == FMT_FP8) ? 1'b1 : c0;
        s1   = {1'b0, x1} + {1'b0, ~y1} + {8'd0, cin1};
        c1   = s1[8];

        // Boundary @16 : cut in FP8 and BF16 (propagate only in FP32)
        cin2 = (fmt == FMT_FP32) ? c1 : 1'b1;
        s2   = {1'b0, x2} + {1'b0, ~y2} + {8'd0, cin2};
        c2   = s2[8];

        // Boundary @24 : cut only in FP8
        cin3 = (fmt == FMT_FP8) ? 1'b1 : c2;
        s3   = {1'b0, x3} + {1'b0, ~y3} + {8'd0, cin3};
        c3   = s3[8];

        // borrow = ~carry_out, one result per byte lane
        swap = {~c3, ~c2, ~c1, ~c0};
    end

endmodule : AbsComparator
