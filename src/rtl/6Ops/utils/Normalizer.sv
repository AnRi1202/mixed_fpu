`timescale 1ns/1ps
import FpuPkg::*;
/*
===============================================================================
Normalizer (Leading-Zero count_o + Left Shift) for Shared FMT_FP32 / Dual-FMT_BF16 Datapath
-------------------------------------------------------------------------------
Normalizes the post-add fraction by:
  1) Leading-zero count (LZC)
  2) Left shift by the LZC result


FMT_FP32 mode (single 28-bit lane):
[27:3] : padding(1b), frac(24b)
[2]    : guard
[1]    : rnd 
[0]    : stk (actual value from add_sticky_l)

FMT_BF16 mode (dual 14-bit bf16x2, after fracSticky assignment):
High lane [27:14] (14 bits):
    [27]    : padding_h
    [26:19] : frac_h (8-bit high lane fraction)
    [18]    : guard_h
    [17]    : rnd_h 
    [16]    : stk_h (overwritten by add_sticky_h, originally gap[4])
    [15:14] : gap[3:2] (2 bits of 5-bit gap, now 4-bit after [16] override)

Low lane [13:0] (14 bits):
    [13:12] : gap[1:0] (remaining 2 bits of gap)
    [11]    : padding_l
    [10:3]  : frac_l (8-bit low lane fraction)
    [2]     : guard_l
    [1]     : rnd_l 
    [0]     : stk_l 

I/O:
  - Input  `operandX[27:0]` : concatenated fraction (includes sticky extension)
  - Output `result[27:0]` : normalized fraction
  - Output `countHi` : FP16x2 hi-lane LZC, or full 28-bit LZC in FMT_FP32
  - Output `countLo` : valid only in FMT_BF16 mode (start at operandX[11])  

Datapath:
  - FMT_FP32   : LZC(28) on `operandX[27:0]` then cross-lane shift -> `result[27:0]`
  - FP16x2 : LZC(14) + shift on each lane independently

Notes:
  - Cross-lane shifting occurs only in FMT_FP32 mode.
  - FP16x2 bf16x2 remain independent to reduce area/routing and avoid per-stage
    `fmt` multiplexers.
===============================================================================
*/
module Normalizer(
    input  logic       clk,
    input  FpFmt_e    fmt,
    input  logic [27:0] operandX,
    output logic [4:0]  countHi,
    output logic [4:0]  countLo,
    output logic [27:0] result
);

    // stage levels (14b hi/lo halves)
    logic [13:0] level4_h, level4_l;
    logic [13:0] level3_h, level3_l;
    logic [13:0] level2_h, level2_l;
    logic [13:0] level1_h, level1_l;
    logic [13:0] level0_h, level0_l;

    // stage count bits
    logic count4_h, count4_l;
    logic count3_h, count3_l;
    logic count2_h, count2_l;
    logic count1_h, count1_l;
    logic count0_h, count0_l;

    // Stage 4 decision (FMT_FP32-only shift-by-16)
    always_comb begin
        // Stage 4: shift by 16 (FMT_FP32 lane only)
        
        // "stage4 on" condition: FMT_FP32 mode AND upper 16b are all-zero
        count4_h = ((fmt == FMT_FP32) &&  ~(|operandX[27:12]));
        count4_l = 1'b0;   // Stage4 is FMT_FP32-only, and countLo is FMT_BF16-only
        {level4_h, level4_l} = ((fmt == FMT_FP32) && count4_h) ? {operandX[11:0], 16'b0} : operandX;

        // Stage 3: shift by 8
        count3_h = ~(|level4_h[13:6]);
        count3_l = (fmt ==FMT_FP32) ? count3_h :~(|level4_l[11:4]);
        // if (fmt == FMT_FP32) begin
        //     level3_h = count3_h ? {level4_h[5:0],  level4_l[13:6]}: level4_h;
        // end else begin 
        //     level3_h = count3_h ? {level4_h[5:2], 8'b0, 2'b0} : level4_h;
        // end
        level3_h[13:10] = count3_h ? level4_h[5:2] : level4_h[13:10];
        level3_h[9:0] = count3_h ? ({level4_h[1:0], level4_l[13:6]} & {10{fmt==FMT_FP32}}) : level4_h[9:0];

        level3_l = count3_l ? {level4_l[5:0], 8'b0} : level4_l;

        // Stage 2: shift by 4            
        count2_h = ~(|level3_h[13:10]);
        count2_l = (fmt ==FMT_FP32) ? count2_h : ~(|level3_l[11:8]);
        // if (fmt == FMT_FP32) begin
        //     level2_h = count2_h ? {level3_h[9:0],  level3_l[13:10]} :level3_h;
        // end else begin 
        //     level2_h = count2_h ? {level3_h[9:2], 4'b0, 2'b0} : level3_h;
        // end
        level2_h[13:6] = count2_h ? level3_h[9:2] : level3_h[13:6];
        level2_h[5:0] = count2_h ? ({level3_h[1:0], level3_l[13:10]} & {6{fmt==FMT_FP32}}) : level3_h[5:0];


        level2_l = count2_l ? {level3_l[9:0], 4'b0} : level3_l;
        // Stage 1: shift by 2
        count1_h = ~(|level2_h[13:12]);
        count1_l = (fmt ==FMT_FP32) ? count1_h :~(|level2_l[11:10]);
        // if (fmt == FMT_FP32) begin
        //     level1_h = count1_h ? {level2_h[11:0],  level2_l[13:12]} : level2_h;
        // end else begin 
        //     level1_h = count1_h ? {level2_h[11:2], 2'b0, 2'b0} : level2_h;
        // end
        level1_h[13:4] = count1_h ? level2_h[11:2] : level2_h[13:4];
        level1_h[3:0] = count1_h ? ({level2_h[1:0], level2_l[13:12]} & {4{fmt==FMT_FP32}}) : level2_h[3:0];
 
        level1_l = count1_l ? {level2_l[11:0], 2'b0} : level2_l;
        // Stage 0: shift by 1
        count0_h = ~(|level1_h[13]);
        count0_l = (fmt ==FMT_FP32) ? count0_h : ~(|level1_l[11]);
        // if (fmt == FMT_FP32) begin
        //     level0_h = count0_h ? {level1_h[12:0],  level1_l[13]}: level1_h;
        // end else begin 
        //     level0_h = count0_h ? {level1_h[12:2], 1'b0, 2'b0} : level1_h;
        // end
        level0_h[13:3] = count0_h ? level1_h[12:2] : level1_h[13:3];
        level0_h[2:0] = count0_h ? ({level1_h[1:0], level1_l[13]} & {3{fmt==FMT_FP32}}) : level1_h[2:0];
 
        level0_l = count0_l ? {level1_l[12:0], 1'b0} : level1_l;


        result = {level0_h, level0_l};
        countHi = {count4_h, count3_h, count2_h, count1_h, count0_h};
        countLo = {count4_l, count3_l, count2_l, count1_l, count0_l};
    end
endmodule : Normalizer
