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

Implementation note:
  - Logarithmic barrel shifter (staged shifts: 16/8/4/2/1).
  - One shared shift network serves both FMT_FP32 and FP16x2 modes.

Input packing expectation:
  - FMT_FP32 (fmt == FMT_FP32):
      `operandX` represents the single FMT_FP32 fraction payload.
      `X26` conceptually corresponds to { frac[23:0], guard, sticky }.
  - FMT_BF16 (fmt == FMT_BF16):
      FP16x2 is interpreted in the 26-bit widened vector `X26` (after
      `X26 = { operandX, 2'b00 }`) as two 10-bit bf16x2 separated by a 6-bit zero gap:
        lane.hi -> X26[25:16] = { frac_hi[7:0], guard_hi, sticky_hi }
        gap     -> X26[15:10] = 6'b0
        lane.lo -> X26[9:0]   = { frac_lo[7:0], guard_lo, sticky_lo }

      NOTE: This module does not repack bf16x2; correct lane+gap packing is an
      upstream responsibility.

Shift amount encoding (`shiftAmount`):
  - FMT_FP32 : shift_amt = shiftAmount[4:0]  (0–31)
  - FMT_BF16 : shift_hi  = shiftAmount[7:4]  (0–15), shift_lo = shiftAmount[3:0] (0–15)

Output (`result`):
  - `result[25:0]` is the shifted result in the same `X26` layout.
    - FMT_FP32  : 26-bit shifted fraction path
    - FP16x2: lane.hi in `result[25:16]`, zero gap in `result[15:10]`, lane.lo in `result[9:0]`

Sticky outputs:
  - stickyHi : valid only in FMT_BF16 mode (upper lane)
  - stickyLo : FMT_FP32 = global sticky; FMT_BF16 = lower-lane sticky
===============================================================================
*/

module BarrelShifter(
    input  FpFmt_e    fmt,
    input  logic [23:0] operandX,
    input  logic [11:0]  shiftAmount,
    output logic [25:0] result,
    output logic [3:0]  sticky
);
  // stage levels (original naming, now full 26-bit, no _h/_l split)
  logic [25:0] level5, level4, level3, level2, level1, level0;
  logic stk0, stk1, stk2, stk3;
  logic [25:0] shifted;

  // per-lane sticky accumulators
  logic stk0, stk1, stk2, stk3;

      // per-lane shift amounts (only low bits used per fmt)
      logic [4:0] st3, st2, st1, st0;



    always_comb begin: set_steps
        steps0 = '0; steps1 = '0; steps2 = '0; steps3 = '0;
        unique case (fmt)
            FMT_FP32: begin
                steps0 = shiftAmount[4:0]; steps1 = steps0;
                steps2 = steps0;           steps3 = steps0;
            end
            FMT_BF16: begin
                steps0 = {1'b0, shiftAmount[3:0]}; steps1 = steps0;
                steps2 = {1'b0, shiftAmount[7:4]}; steps3 = steps2;
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



    // boundary propagation enable
    //   propagate (lanes merge) when enabled, block (lanes isolated) when disabled
    logic prop07, prop13, prop20;
    always_comb begin: bit_propagation
        prop07 = (fmt == FMT_FP8);
        prop13 = (fmt != FMT_FP32);
        prop20 = (fmt == FMT_FP8);
    end

    // input widening (24b -> 26b)
    logic [25:0] X26;
    always_comb begin: 
      X26 = {operandX, 2'b00};
      level5  = X26;
      // =================== stage by 16 : level5 -> level4 ===================
      shifted = level5 >> 16;
      shifted[6:0]  = shifted[6:0]  & {7 {prop07}};
      shifted[12:0] = shifted[12:0] & {13{prop13}};
      shifted[19:4] = shifted[19:4] & {16{prop20}};
      stk0 |=           steps0[4] & (|level5[6:0]);
      stk1 |= !prop07 & steps1[4] & (|level5[12:7]);
      stk2 |= !prop13 & steps2[4] & (|level5[19:13]);
      stk3 |= !prop20 & steps3[4] & (|level5[25:20]);
      level4[6:0]   = steps0[4] ? shifted[6:0]   : level5[6:0];
      level4[12:7]  = steps1[4] ? shifted[12:7]  : level5[12:7];
      level4[19:13] = steps2[4] ? shifted[19:13] : level5[19:13];
      level4[25:20] = steps3[4] ? shifted[25:20] : level5[25:20];
      // =================== stage by 8 : level4 -> level3 ===================
      shifted = level4 >> 8;
      shifted[6:0]   = shifted[6:0]   & {7{prop07}};
      shifted[12:5]  = shifted[12:5]  & {8{prop13}};
      shifted[19:12] = shifted[19:12] & {8{prop20}};
      stk0 |=           steps0[3] & (|level4[6:0]);
      stk1 |= !prop07 & steps1[3] & (|level4[12:7]);
      stk2 |= !prop13 & steps2[3] & (|level4[19:13]);
      stk3 |= !prop20 & steps3[3] & (|level4[25:20]);
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

        if (fmt == FMT_BF16) begin
          stk2 |= |level0[15:13];
          level0[15:13] = 3'b0;
        end
        if (fmt == FMT_FP8) begin
          stk3 = 
        end
        stickyHi =(stk0_h | (|level0_h[2:0]));
        stickyLo = stk0_l;
        
    end

endmodule : BarrelShifter
