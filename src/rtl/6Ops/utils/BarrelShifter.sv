`timescale 1ns/1ps
import FpuPkg::*;

/*
===============================================================================
Barrel Shifter for Shared FMT_FP32 / Dual-FMT_FP16 Datapath
-------------------------------------------------------------------------------
This shifter is shared between:
  - FMT_FP32   : single 26-bit fraction path
  - FP16x2 : dual-lane segmented fraction path (lane isolation via a zero gap)

Implementation note:
  - Logarithmic barrel shifter (staged shifts: 16/8/4/2/1).
  - One shared shift network serves both FMT_FP32 and FP16x2 modes.

Input packing expectation:
  - FMT_FP32 (fmt == FMT_FP32):
      `operandX` represents the single FMT_FP32 fraction payload.
      `X26` conceptually corresponds to { frac[23:0], guard, sticky }.
  - FMT_FP16 (fmt == FMT_FP16):
      FP16x2 is interpreted in the 26-bit widened vector `X26` (after
      `X26 = { operandX, 2'b00 }`) as two 10-bit lanes separated by a 6-bit zero gap:
        lane.hi -> X26[25:16] = { frac_hi[7:0], guard_hi, sticky_hi }
        gap     -> X26[15:10] = 6'b0
        lane.lo -> X26[9:0]   = { frac_lo[7:0], guard_lo, sticky_lo }

      NOTE: This module does not repack lanes; correct lane+gap packing is an
      upstream responsibility.

Shift amount encoding (`shiftAmount`):
  - FMT_FP32 : shift_amt = shiftAmount[4:0]  (0–31)
  - FMT_FP16 : shift_hi  = shiftAmount[7:4]  (0–15), shift_lo = shiftAmount[3:0] (0–15)

Output (`result`):
  - `result[25:0]` is the shifted result in the same `X26` layout.
    - FMT_FP32  : 26-bit shifted fraction path
    - FP16x2: lane.hi in `result[25:16]`, zero gap in `result[15:10]`, lane.lo in `result[9:0]`

Sticky outputs:
  - stickyHi : valid only in FMT_FP16 mode (upper lane)
  - stickyLo : FMT_FP32 = global sticky; FMT_FP16 = lower-lane sticky
===============================================================================
*/

module BarrelShifter(
    input  FpFmt_e    fmt,
    input  logic [23:0] operandX,
    input  logic [7:0]  shiftAmount,
    output logic [25:0] result,
    output logic        stickyHi,
    output logic        stickyLo
);
    // stage levels
    logic [25:0] level5;
    logic [12:0] level4_h, level4_l;
    logic [12:0] level3_h, level3_l;
    logic [12:0] level2_h, level2_l;
    logic [12:0] level1_h, level1_l;
    logic [12:0] level0_h, level0_l;

    // stage sticky bits
    logic stk4_h, stk4_l;
    logic stk3_h, stk3_l;
    logic stk2_h, stk2_l;
    logic stk1_h, stk1_l;
    logic stk0_h, stk0_l;

    // input widening (24b -> 26b)
    logic [25:0] X26;
    assign X26 = {operandX, 2'b00};
    assign level5  = X26;

    // shift control
    logic [4:0] steps_h, steps_l;
    logic [12:0] level0_h_out;  

    // Shift control
    assign steps_h = (fmt == FMT_FP32) ? shiftAmount[4:0] : {1'b0, shiftAmount[7:4]};
    assign steps_l = (fmt == FMT_FP32) ? shiftAmount[4:0] : {1'b0, shiftAmount[3:0]};

    always_comb begin
        // Stage 4: shift by 16 (FMT_FP32 only)
        stk4_h  = 1'b0;
        stk4_l  = (fmt == FMT_FP32) && shiftAmount[4] && (|level5[15:0]);

        // Split 26-bit into two 13-bit halves and shift by 16 if enabled
        {level4_h,level4_l} = steps_h[4] ? {16'b0, level5[25:16]} : level5[25:0];


        // Stage 3: shift by 8
        stk3_h   = (fmt == FMT_FP16) && steps_h[3] && (|level4_h[7:0]);
        stk3_l   = stk4_l | (steps_l[3] & (|level4_l[7:0]));

        // Upper half shift
        level3_h = steps_h[3] ? {8'b0, level4_h[12:8]} : level4_h;
        // Lower half shift
        // if (fmt ==FMT_FP32) begin
        //     level3_l = steps_l[3] ? {level4_h[7:0], level4_l[12:8]} : level4_l;
        // end else begin
        //     level3_l = steps_l[3] ? {8'b0, level4_l[12:8]} : level4_l;
        // end

        level3_l[12:5] = steps_l[3] ? (level4_h[7:0] & {8{fmt == FMT_FP32}}): level4_l[12:5];
        level3_l[4:0] = steps_l[3] ? level4_l[12:8] : level4_l[4:0];

        // Stage 2: shift by 4
        stk2_h   = stk3_h | ((fmt == FMT_FP16) && steps_h[2] && (|level3_h[3:0]));
        stk2_l   = stk3_l | (steps_l[2] & (|level3_l[3:0]));
        level2_h = steps_h[2] ? {4'b0, level3_h[12:4]} : level3_h;
        // if (fmt == FMT_FP32) begin
        //     level2_l = steps_l[2] ? {level3_h[3:0], level3_l[12:4]} : level3_l;
        // end else begin
        //     level2_l = steps_l[2] ? {4'b0, level3_l[12:4]} : level3_l;
        // end
        level2_l[12:9] = steps_l[2] ? (level3_h[3:0] & {4{fmt == FMT_FP32}}): level3_l[12:9];
        level2_l[8:0] = steps_l[2] ? level3_l[12:4] : level3_l[8:0];

        // Stage 1: shift by 2
        stk1_h   = stk2_h | ((fmt == FMT_FP16) && steps_h[1] && (|level2_h[1:0]));
        stk1_l   = stk2_l | (steps_l[1] & (|level2_l[1:0]));
        level1_h = steps_h[1] ? {2'b0, level2_h[12:2]} : level2_h;
        // if (fmt == FMT_FP32) begin
        //     level1_l = steps_l[1] ? {level2_h[1:0], level2_l[12:2]} : level2_l;
        // end else begin
        //     level1_l = steps_l[1] ? {2'b0, level2_l[12:2]} : level2_l;
        // end
        level1_l[12:11] = steps_l[1] ? (level2_h[1:0] & {2{fmt == FMT_FP32}}): level2_l[12:11];
        level1_l[10:0] = steps_l[1] ? level2_l[12:2] : level2_l[10:0];

        // Stage 0: shift by 1
        stk0_h   = stk1_h | ((fmt == FMT_FP16) && steps_h[0] && (|level1_h[0]));
        stk0_l   = stk1_l | (steps_l[0] & level1_l[0]);
        level0_h = steps_h[0] ? {1'b0, level1_h[12:1]} : level1_h;
        // if (fmt == FMT_FP32) begin
        //     level0_l = steps_l[0] ? {level1_h[0], level1_l[12:1]} : level1_l;
        // end else begin
        //     level0_l = steps_l[0] ? {1'b0, level1_l[12:1]} : level1_l;
        // end
        level0_l[12] = steps_l[0] ? (level1_h[0] & {1{fmt == FMT_FP32}}): level1_l[12];
        level0_l[11:0] = steps_l[0] ? level1_l[12:1] : level1_l[11:0];

        // In FMT_FP16 mode, lower 3 bits of upper lane are masked (lane width = 10b)
        level0_h_out = level0_h;
        if (fmt == FMT_FP16) level0_h_out[2:0] = 3'b0;
        result = {level0_h_out, level0_l};

        stickyHi =(stk0_h | (|level0_h[2:0]));
        stickyLo = stk0_l;
        
    end

endmodule : BarrelShifter