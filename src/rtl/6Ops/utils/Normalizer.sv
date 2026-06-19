`timescale 1ns/1ps
import FpuPkg::*;
/*
===============================================================================
Normalizer (Leading-Zero count + Left Shift) for the Shared
FMT_FP32 / FMT_BF16x2 / FMT_FP8x4 Datapath
-------------------------------------------------------------------------------
One logarithmic left-shift network (stages 16/8/4/2/1) shared by:
  - FMT_FP32 : 1 lane   (28-bit fraction path)
  - FMT_BF16 : 2 lanes  (bf16x2, 14-bit lanes)
  - FMT_FP8  : 4 lanes  (fp8x4,  7-bit lanes, E4M3)

The single 28-bit datapath is partitioned into four 7-bit lanes:

    L3 = operandX[27:21]   L2 = operandX[20:14]   L1 = operandX[13:7]   L0 = operandX[6:0]

Lane merging is controlled by boundary-propagation enables (same scheme as
AbsComparator): a boundary "propagates" (lanes merge into one region) when
enabled, and "blocks" (lanes stay independent) when disabled.

    prop @ L0|L1  (bit 6/7)   : merge when fmt != FMT_FP8
    prop @ L1|L2  (bit 13/14) : merge when fmt == FMT_FP32
    prop @ L2|L3  (bit 20/21) : merge when fmt != FMT_FP8

This yields the regions:
    FMT_FP32 : { L3,L2,L1,L0 }                       -> [27:0]
    FMT_BF16 : { L3,L2 } , { L1,L0 }                 -> [27:14] , [13:0]
    FMT_FP8  : { L3 } , { L2 } , { L1 } , { L0 }     -> 4 x 7-bit

Per-lane bit layout (E4M3, FP8x4):
    [6] pad      [5:2] significand(4b, incl. implicit 1)   [1] guard   [0] round/sticky
Normalization brings the leading 1 up to the lane's MSB (the pad bit), exactly
mirroring the FMT_FP32 / FMT_BF16 behaviour (where the pad bit becomes the
implicit-1 position after normalization).

Leading-zero detection MSBs (per region):
    FMT_FP32 region          : bit 27
    FMT_BF16 hi region       : bit 27          lo region : bit 11 (gap at [13:12])
    FMT_FP8  L3/L2/L1/L0     : bit 27 / 20 / 13 / 6

I/O:
  - Input  `operandX[27:0]` : concatenated fraction (includes sticky extension)
  - Output `result[27:0]`   : normalized fraction (same lane layout)
  - Output `count[i]`       : leading-zero count (shift amount) of lane i's region.
                              count[3]==count[2] in FMT_BF16 (hi), count[1]==count[0] (lo);
                              all four equal in FMT_FP32. Maps to the previous
                              countHi (count[3]) / countLo (count[0]).

Notes:
  - Cross-lane shifting occurs only across propagating boundaries.
  - The BF16 lo region's two MSBs [13:12] are the lane gap (always 0); detection
    starts at bit 11, identical to the previous implementation (no regression).
===============================================================================
*/
module Normalizer(
    input  logic        clk,
    input  FpFmt_e      fmt,
    input  logic [27:0] operandX,
    output logic [4:0]  count [4],
    output logic [27:0] result
);

    // Boundary propagation enables (1 = merge / propagate)
    logic prop7, prop14, prop20;

    // Stage levels (full 28-bit, shared network)
    logic [27:0] level5, level4, level3, level2, level1, level0;
    logic [27:0] shifted;

    // Per-lane shift enables (= count bits) for each stage
    logic e16_3, e16_2, e16_1, e16_0;   // stage 16 (FMT_FP32 only)
    logic e8_3,  e8_2,  e8_1,  e8_0;    // stage 8  (FMT_FP32 / FMT_BF16)
    logic e4_3,  e4_2,  e4_1,  e4_0;    // stage 4  (all)
    logic e2_3,  e2_2,  e2_1,  e2_0;    // stage 2  (all)
    logic e1_3,  e1_2,  e1_1,  e1_0;    // stage 1  (all)

    always_comb begin : normalize
        prop7  = (fmt != FMT_FP8);
        prop14 = (fmt == FMT_FP32);
        prop20 = (fmt != FMT_FP8);

        level5 = operandX;

        // =================== stage 16 : level5 -> level4 (FMT_FP32 only) ===================
        // Single 28-bit region (MSB = bit 27); all boundaries propagate in FMT_FP32.
        e16_3 = (fmt == FMT_FP32) & ~(|level5[27:12]);
        e16_2 = e16_3;
        e16_1 = e16_3;
        e16_0 = e16_3;

        shifted = level5 << 16;     // FMT_FP32 => every boundary open, no masking

        level4[27:21] = e16_3 ? shifted[27:21] : level5[27:21];
        level4[20:14] = e16_2 ? shifted[20:14] : level5[20:14];
        level4[13:7]  = e16_1 ? shifted[13:7]  : level5[13:7];
        level4[6:0]   = e16_0 ? shifted[6:0]   : level5[6:0];

        // =================== stage 8 : level4 -> level3 (FMT_FP32 / FMT_BF16) ===================
        // hi region MSB = 27, lo region MSB = 11 (BF16). FMT_FP8 does not use this stage.
        e8_3 = (fmt != FMT_FP8) & ~(|level4[27:20]);
        e8_2 = e8_3;
        e8_1 = (fmt == FMT_FP32) ? (~(|level4[27:20]))
             : (fmt == FMT_BF16) ? (~(|level4[11:4]))
             : 1'b0;
        e8_0 = e8_1;

        shifted = level4 << 8;
        if (!prop14) shifted[21:14] = 8'b0;   // block L1|L2 crossing (FMT_BF16/FMT_FP8)

        level3[27:21] = e8_3 ? shifted[27:21] : level4[27:21];
        level3[20:14] = e8_2 ? shifted[20:14] : level4[20:14];
        level3[13:7]  = e8_1 ? shifted[13:7]  : level4[13:7];
        level3[6:0]   = e8_0 ? shifted[6:0]   : level4[6:0];

        // =================== stage 4 : level3 -> level2 (all) ===================
        // Region MSBs: L3=27, L2=20, L1=13, L0=6 ; BF16 lo MSB=11 ; FMT_FP32 MSB=27.
        e4_3 = ~(|level3[27:24]);
        e4_2 = (fmt == FMT_FP8) ? (~(|level3[20:17]))
             :                    (~(|level3[27:24]));   // FMT_FP32/FMT_BF16: part of hi region
        e4_1 = (fmt == FMT_FP32) ? (~(|level3[27:24]))
             : (fmt == FMT_BF16) ? (~(|level3[11:8]))
             :                     (~(|level3[13:10]));
        e4_0 = (fmt == FMT_FP32) ? (~(|level3[27:24]))
             : (fmt == FMT_BF16) ? (~(|level3[11:8]))
             :                     (~(|level3[6:3]));

        shifted = level3 << 4;
        if (!prop7)  shifted[10:7]  = 4'b0;    // block L0|L1
        if (!prop14) shifted[17:14] = 4'b0;    // block L1|L2
        if (!prop20) shifted[24:21] = 4'b0;    // block L2|L3

        level2[27:21] = e4_3 ? shifted[27:21] : level3[27:21];
        level2[20:14] = e4_2 ? shifted[20:14] : level3[20:14];
        level2[13:7]  = e4_1 ? shifted[13:7]  : level3[13:7];
        level2[6:0]   = e4_0 ? shifted[6:0]   : level3[6:0];

        // =================== stage 2 : level2 -> level1 (all) ===================
        e2_3 = ~(|level2[27:26]);
        e2_2 = (fmt == FMT_FP8) ? (~(|level2[20:19]))
             :                    (~(|level2[27:26]));
        e2_1 = (fmt == FMT_FP32) ? (~(|level2[27:26]))
             : (fmt == FMT_BF16) ? (~(|level2[11:10]))
             :                     (~(|level2[13:12]));
        e2_0 = (fmt == FMT_FP32) ? (~(|level2[27:26]))
             : (fmt == FMT_BF16) ? (~(|level2[11:10]))
             :                     (~(|level2[6:5]));

        shifted = level2 << 2;
        if (!prop7)  shifted[8:7]   = 2'b0;
        if (!prop14) shifted[15:14] = 2'b0;
        if (!prop20) shifted[22:21] = 2'b0;

        level1[27:21] = e2_3 ? shifted[27:21] : level2[27:21];
        level1[20:14] = e2_2 ? shifted[20:14] : level2[20:14];
        level1[13:7]  = e2_1 ? shifted[13:7]  : level2[13:7];
        level1[6:0]   = e2_0 ? shifted[6:0]   : level2[6:0];

        // =================== stage 1 : level1 -> level0 (all) ===================
        e1_3 = ~level1[27];
        e1_2 = (fmt == FMT_FP8) ? (~level1[20])
             :                    (~level1[27]);
        e1_1 = (fmt == FMT_FP32) ? (~level1[27])
             : (fmt == FMT_BF16) ? (~level1[11])
             :                     (~level1[13]);
        e1_0 = (fmt == FMT_FP32) ? (~level1[27])
             : (fmt == FMT_BF16) ? (~level1[11])
             :                     (~level1[6]);

        shifted = level1 << 1;
        if (!prop7)  shifted[7]  = 1'b0;
        if (!prop14) shifted[14] = 1'b0;
        if (!prop20) shifted[21] = 1'b0;

        level0[27:21] = e1_3 ? shifted[27:21] : level1[27:21];
        level0[20:14] = e1_2 ? shifted[20:14] : level1[20:14];
        level0[13:7]  = e1_1 ? shifted[13:7]  : level1[13:7];
        level0[6:0]   = e1_0 ? shifted[6:0]   : level1[6:0];

        result   = level0;

        // Per-lane leading-zero counts (region shift amount).
        count[3] = {e16_3, e8_3, e4_3, e2_3, e1_3};
        count[2] = {e16_2, e8_2, e4_2, e2_2, e1_2};
        count[1] = {e16_1, e8_1, e4_1, e2_1, e1_1};
        count[0] = {e16_0, e8_0, e4_0, e2_0, e1_0};
    end
endmodule : Normalizer
