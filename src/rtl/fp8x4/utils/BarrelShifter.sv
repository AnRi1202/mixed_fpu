`timescale 1ns/1ps
import FpuPkg::*;

/*
===============================================================================
Barrel Shifter for Shared FMT_FP32 / BF16x2 / FP8x4 Datapath
-------------------------------------------------------------------------------
One logarithmic right-shift network (stages 16/8/4/2/1) shared by:
  - FMT_FP32 : 1 lane  (26-bit fraction path)
  - FMT_BF16 : 2 lanes (bf16x2)
  - FMT_FP8  : 4 lanes (fp8x4, E4M3: significand = 4 bits)

Lane isolation: the 26-bit shift network has 3 boundaries; whether a bit is
allowed to PROPAGATE across a boundary is enabled/disabled per fmt:
    boundary @7  (lane0|lane1) : propagate unless FP8
    boundary @13 (lane1|lane2) : propagate only in FP32   (= BF16 mid-boundary)
    boundary @20 (lane2|lane3) : propagate unless FP8
When propagation is enabled the network collapses to the wider-format shift
(FP32 -> one 26-bit shift, BF16 -> two 13-bit halves).

X26 layout (X26 = {operandX, 2'b00}):
  FMT_FP32 : X26[25:0]                                  = { frac[23:0], guard, sticky }
  FMT_BF16 : X26[25:16]=lane.hi, [15:10]=gap, [9:0]=lane.lo
  FMT_FP8  : lane3=X26[25:20], gap=X26[19], lane2=X26[18:13],
             lane1=X26[12:7],  gap=X26[6],  lane0=X26[5:0]
             (each FP8 lane = 6-bit content with LSB at the lane bottom; the two
              spare bits of the 26-bit word are placed as 1-bit gaps at bit6/bit19
              so that (a) all 4 lanes are uniform, (b) lane1|lane2 reuses the
              BF16 mid-boundary @13, and (c) no per-lane residual-sticky logic is
              needed -> minimum area.)
  NOTE: upstream is responsible for packing each format correctly.

shiftAmount (12-bit, minimum width for 4 independent FP8 lane amounts):
  FMT_FP32 : shiftAmount[4:0]                              (0..26)
  FMT_BF16 : [3:0]=lo lane, [7:4]=hi lane                  (0..10)
  FMT_FP8  : [2:0]=lane0,[5:3]=lane1,[8:6]=lane2,[11:9]=lane3 (0..6)

Output:
  result[25:0] : shifted value in the same X26 layout
  sticky[3:0]  : one sticky bit per byte lane
     FMT_FP8  : sticky[0..3] = lane0..lane3
     FMT_BF16 : sticky[0] = lo lane, sticky[2] = hi lane
     FMT_FP32 : sticky[0] = global sticky
===============================================================================
*/

module BarrelShifter(
    input  FpFmt_e      fmt,
    input  logic [23:0] operandX,
    input  logic [11:0] shiftAmount,
    output logic [25:0] result,
    output logic [3:0]  sticky
);

    // per-lane shift amounts (5-bit: FP32 needs up to 26)
    logic [4:0] steps0, steps1, steps2, steps3;
    always_comb begin : set_steps
        steps0 = '0; steps1 = '0; steps2 = '0; steps3 = '0;
        unique case (fmt)
            FMT_FP32: begin
                steps0 = shiftAmount[4:0]; steps1 = steps0;
                steps2 = steps0;           steps3 = steps0;
            end
            FMT_BF16: begin
                steps0 = {1'b0, shiftAmount[3:0]}; steps1 = steps0; // lo lane
                steps2 = {1'b0, shiftAmount[7:4]}; steps3 = steps2; // hi lane
            end
            FMT_FP8: begin
                steps0 = {2'b0, shiftAmount[2:0]};
                steps1 = {2'b0, shiftAmount[5:3]};
                steps2 = {2'b0, shiftAmount[8:6]};
                steps3 = {2'b0, shiftAmount[11:9]};
            end
            default: ;
        endcase
    end

    // boundary propagation enable (1 = lanes merge, 0 = lanes isolated)
    logic prop07, prop13, prop20;
    always_comb begin : bit_propagation
        prop07 = (fmt != FMT_FP8);
        prop13 = (fmt == FMT_FP32);
        prop20 = (fmt != FMT_FP8);
    end

    // stage levels (full 26-bit) and per-lane sticky accumulators
    logic [25:0] X26, level5, level4, level3, level2, level1, level0, shifted;
    logic stk0, stk1, stk2, stk3;

    always_comb begin : shift_network
        X26    = {operandX, 2'b00};
        level5 = X26;
        stk0 = 1'b0; stk1 = 1'b0; stk2 = 1'b0; stk3 = 1'b0;

        // =================== stage by 16 : level5 -> level4 ===================
        // Only FP32 shifts here (BF16<=10, FP8<=6), all boundaries open -> no mask.
        shifted = level5 >> 16;
        stk0 |= steps0[4] & (|level5[15:0]);
        level4[6:0]   = steps0[4] ? shifted[6:0]   : level5[6:0];
        level4[12:7]  = steps1[4] ? shifted[12:7]  : level5[12:7];
        level4[19:13] = steps2[4] ? shifted[19:13] : level5[19:13];
        level4[25:20] = steps3[4] ? shifted[25:20] : level5[25:20];

        // =================== stage by 8 : level4 -> level3 ===================
        // FP32 + BF16 shift here (FP8<=6). Only the mid-boundary (prop13) matters.
        shifted = level4 >> 8;
        shifted[12:5] = shifted[12:5] & {8{prop13}};
        stk0 |=           steps0[3] & (|level4[7:0]);
        stk2 |= !prop13 & steps2[3] & (|level4[20:13]);
        level3[6:0]   = steps0[3] ? shifted[6:0]   : level4[6:0];
        level3[12:7]  = steps1[3] ? shifted[12:7]  : level4[12:7];
        level3[19:13] = steps2[3] ? shifted[19:13] : level4[19:13];
        level3[25:20] = steps3[3] ? shifted[25:20] : level4[25:20];

        // =================== stage by 4 : level3 -> level2 ===================
        shifted = level3 >> 4;
        shifted[6:3]   = shifted[6:3]   & {4{prop07}};
        shifted[12:9]  = shifted[12:9]  & {4{prop13}};
        shifted[19:16] = shifted[19:16] & {4{prop20}};
        stk0 |=           steps0[2] & (|level3[3:0]);
        stk1 |= !prop07 & steps1[2] & (|level3[10:7]);
        stk2 |= !prop13 & steps2[2] & (|level3[16:13]);
        stk3 |= !prop20 & steps3[2] & (|level3[23:20]);
        level2[6:0]   = steps0[2] ? shifted[6:0]   : level3[6:0];
        level2[12:7]  = steps1[2] ? shifted[12:7]  : level3[12:7];
        level2[19:13] = steps2[2] ? shifted[19:13] : level3[19:13];
        level2[25:20] = steps3[2] ? shifted[25:20] : level3[25:20];

        // =================== stage by 2 : level2 -> level1 ===================
        shifted = level2 >> 2;
        shifted[6:5]   = shifted[6:5]   & {2{prop07}};
        shifted[12:11] = shifted[12:11] & {2{prop13}};
        shifted[19:18] = shifted[19:18] & {2{prop20}};
        stk0 |=           steps0[1] & (|level2[1:0]);
        stk1 |= !prop07 & steps1[1] & (|level2[8:7]);
        stk2 |= !prop13 & steps2[1] & (|level2[14:13]);
        stk3 |= !prop20 & steps3[1] & (|level2[21:20]);
        level1[6:0]   = steps0[1] ? shifted[6:0]   : level2[6:0];
        level1[12:7]  = steps1[1] ? shifted[12:7]  : level2[12:7];
        level1[19:13] = steps2[1] ? shifted[19:13] : level2[19:13];
        level1[25:20] = steps3[1] ? shifted[25:20] : level2[25:20];

        // =================== stage by 1 : level1 -> level0 ===================
        shifted = level1 >> 1;
        shifted[6]  = shifted[6]  & prop07;
        shifted[12] = shifted[12] & prop13;
        shifted[19] = shifted[19] & prop20;
        stk0 |=           steps0[0] & (level1[0]);
        stk1 |= !prop07 & steps1[0] & (level1[7]);
        stk2 |= !prop13 & steps2[0] & (level1[13]);
        stk3 |= !prop20 & steps3[0] & (level1[20]);
        level0[6:0]   = steps0[0] ? shifted[6:0]   : level1[6:0];
        level0[12:7]  = steps1[0] ? shifted[12:7]  : level1[12:7];
        level0[19:13] = steps2[0] ? shifted[19:13] : level1[19:13];
        level0[25:20] = steps3[0] ? shifted[25:20] : level1[25:20];

        // ---- residual sticky + result cleanup ----
        // BF16: hi-lane content is [25:16], so [15:13] hold residual precision.
        if (fmt == FMT_BF16) begin
            stk2 |= |level0[15:13];
            level0[15:13] = 3'b0;
        end
        // FP8: gaps carry no payload (uniform 6-bit lanes need no residual term).
        if (fmt == FMT_FP8) begin
            level0[6]  = 1'b0;
            level0[19] = 1'b0;
        end

        result = level0;
        sticky = {stk3, stk2, stk1, stk0};
    end

endmodule : BarrelShifter
