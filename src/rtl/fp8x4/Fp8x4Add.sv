`timescale 1ns/1ps
    import FpuPkg::*;

module Fp8x4Add(
    input logic clk,
    input FpOp_e opcode, //00: Add, 01: Mul, 10: Sqrt, 11: Div
    input FpFmt_e fmt,
    input logic [31:0] operandX,
    input logic [31:0] operandY,
    output logic [31:0] result
);
    // ========================================================================
    // for multiprecision
    // Design Policy:
    // When in FMT_FP32 mode, prioritize using the logic/resources associated with
    // the high-order 16-bit bf16x2 (FMT_BF16 high part) to maximize sharing.
    // ========================================================================
    FpVec_u x, y;
    assign x.raw = operandX;
    assign y.raw = operandY;

    // FPAdd signals
    logic [3:0] swap;

    logic [7:0] expDiff_h;
    logic [7:0] expDiff_l;
    logic [3:0] expDiff_3, expDiff_2, expDiff_1, expDiff_0;  // FP8x4 per-lane exp diffs

    FpVec_u newX, newY;
    logic [7:0] add_expX_h,add_expX_l;
    // Sign
    logic [3:0] signX, signY;
    // Effective subtraction
    logic [3:0] EffSub;
    logic [23:0] significandY;
    logic [7:0] significandY_h, significandY_l;
    logic [3:0] significandY3, significandY2, significandY1, significandY0;
    logic shiftedOut_h, shiftedOut_l;
    logic shiftedOut_2, shiftedOut_1, shiftedOut_0;  // FP8x4 lanes (shiftedOut_h = lane3)
    logic [4:0] shiftVal_h_fp32;
    logic [3:0] shiftVal_h_fp16, shiftVal_l_fp16;
    logic [2:0] shiftVal_3_fp8, shiftVal_2_fp8, shiftVal_1_fp8, shiftVal_0_fp8;
    logic [11:0] shiftVal;
    logic [25:0] shiftedMantissaY;
    logic [3:0] add_sticky;
    logic [26:0] mantissaYpad, EffSub_Vector, mantissaYpadXorOp, mantissaXpad;
    logic [27:0] fracAddSum;
    logic [26:0] cin_vec;
    logic [26:0] fracAddResult;
    logic [27:0] fracSticky;
    logic [4:0] nZerosNew_l, nZerosNew_h;
    logic [4:0] nZerosNew [4];   // per-lane LZC from Normalizer (count[3]=hi/FP32, count[0]=lo)
    logic [27:0] shiftedFrac;
    logic [13:0] shiftedFrac_h, shiftedFrac_l;
    logic [8:0] extendedExpInc_h, extendedExpInc_l;
    logic [8:0] normShift_h, normShift_l;
    logic [7:0] updatedExp_h, updatedExp_l;
    logic stk_h, rnd_h, lsb_h;
    logic stk_l, rnd_l, lsb_l;
    logic [30 :0] round_vec;
    logic [30:0] add_RoundedExpFrac;
    logic [31:0] add_R_fp32;
    logic [31:0] add_R_fp16;
    logic [31:0] add_R_fp8;
    // FP8x4 per-lane exponent update / rounding
    logic [3:0] add_expX_f8 [4];
    logic [4:0] updatedExp_f8 [4];
    logic stk_f8 [4], rnd_f8 [4], lsb_f8 [4];
    logic add_round_f8 [4];
    logic [26:0] add_fracAdder_X, add_fracAdder_Y;
    logic [30:0] add_expFrac;
    logic add_round_h, add_round_l;


    // =================================================================================
    // FPAdd Logic
    // =================================================================================

    // Shared comparator
    AbsComparator u_abs_cmp (
        .fmt(fmt),
        .operandX(x),
        .operandY(y),
        .swap(swap)
    );

    // input swap so that |operandX|>|operandY|
    //
    // AbsComparator's swap[i] (= ~c[i]) is the magnitude-compare result of the
    // *region* whose MSB byte is lane i. Because carries propagate across
    // non-cut boundaries, only the top byte of each region carries the valid
    // decision; the other bytes in the same region must reuse that same bit:
    //   FMT_FP32 : one 32-bit region {L3,L2,L1,L0}        -> all use swap[3]
    //   FMT_BF16 : two 16-bit regions {L3,L2},{L1,L0}     -> hi uses swap[3], lo uses swap[1]
    //   FMT_FP8  : four 8-bit regions {L3},{L2},{L1},{L0} -> each uses its own swap[i]
    logic swap_sel3, swap_sel2, swap_sel1, swap_sel0;
    always_comb begin : swap_sel
        swap_sel3 = swap[3];
        swap_sel2 = (fmt == FMT_FP8)  ? swap[2] : swap[3];
        swap_sel1 = (fmt == FMT_FP32) ? swap[3] : swap[1];
        swap_sel0 = (fmt == FMT_FP32) ? swap[3] :
                    (fmt == FMT_BF16) ? swap[1] : swap[0];

        newX.fp8x4.lane3 = (swap_sel3 == 1'b0) ? x.fp8x4.lane3 : y.fp8x4.lane3;
        newY.fp8x4.lane3 = (swap_sel3 == 1'b0) ? y.fp8x4.lane3 : x.fp8x4.lane3;

        newX.fp8x4.lane2 = (swap_sel2 == 1'b0) ? x.fp8x4.lane2 : y.fp8x4.lane2;
        newY.fp8x4.lane2 = (swap_sel2 == 1'b0) ? y.fp8x4.lane2 : x.fp8x4.lane2;

        newX.fp8x4.lane1 = (swap_sel1 == 1'b0) ? x.fp8x4.lane1 : y.fp8x4.lane1;
        newY.fp8x4.lane1 = (swap_sel1 == 1'b0) ? y.fp8x4.lane1 : x.fp8x4.lane1;

        newX.fp8x4.lane0 = (swap_sel0 == 1'b0) ? x.fp8x4.lane0 : y.fp8x4.lane0;
        newY.fp8x4.lane0 = (swap_sel0 == 1'b0) ? y.fp8x4.lane0 : x.fp8x4.lane0;

    end

    /* Exponent Difference */
    // The two 8-bit subtractors are shared across formats. In FMT_FP8 each one
    // packs two 4-bit lane exponents ({hiLane, loLane}). This is safe because the
    // per-lane swap guarantees expX >= expY in every lane, so the low-nibble
    // subtraction never borrows into the high nibble (no carry-chain cut needed).
    always_comb begin : exponent_dif
        expDiff_h = (fmt == FMT_FP8)
            ? {newX.fp8x4.lane3[6:3], newX.fp8x4.lane2[6:3]}
            - {newY.fp8x4.lane3[6:3], newY.fp8x4.lane2[6:3]}
            : newX.fp32.exp - newY.fp32.exp;

        expDiff_l = (fmt == FMT_FP8)
            ? {newX.fp8x4.lane1[6:3], newX.fp8x4.lane0[6:3]}
            - {newY.fp8x4.lane1[6:3], newY.fp8x4.lane0[6:3]}
            : newX.bf16x2.lo[14:7] - newY.bf16x2.lo[14:7];

        // FP8x4 per-lane exponent differences (sliced from the shared subtractors)
        expDiff_3 = expDiff_h[7:4];
        expDiff_2 = expDiff_h[3:0];
        expDiff_1 = expDiff_l[7:4];
        expDiff_0 = expDiff_l[3:0];
    end

    /* Sign, Exponent, Fraction Decomposition */
    always_comb begin
        signX[3] = newX.fp32.sign;
        signY[3] = newY.fp32.sign;
        signX[2] = newX.fp8x4.lane2[7];
        signY[2] = newY.fp8x4.lane2[7];
        signX[1] = newX.bf16x2.lo[15];
        signY[1] = newY.bf16x2.lo[15];
        signX[0] = newX.fp8x4.lane0[7];
        signY[0] = newY.fp8x4.lane0[7];

        add_expX_h = newX.fp32.exp; // == newX.bf16x2.hi[14:8];
        add_expX_l = newX.bf16x2.lo[14:7];

        EffSub = signX ^ signY; // Calculate each sign bit

        significandY_h = {1'b1, newY.bf16x2.hi[6:0]};
        significandY_l = {1'b1, newY.bf16x2.lo[6:0]};

        significandY3  = {1'b1, newY.fp8x4.lane3[2:0]};
        significandY2  = {1'b1, newY.fp8x4.lane2[2:0]};
        significandY1  = {1'b1, newY.fp8x4.lane1[2:0]};
        significandY0  = {1'b1, newY.fp8x4.lane0[2:0]};
    end

    always_comb begin: shift
    // FMT_FP32 shift amount (cap at 26)
        shiftedOut_h    = (fmt == FMT_FP8) ? (expDiff_3 > 4'd5) : (|expDiff_h[7:5]); // expDiff_h > 31
        shiftVal_h_fp32 = shiftedOut_h ? 5'd26 : expDiff_h[4:0];

    // FMT_BF16 shift amount (cap at 10)
        shiftedOut_l    = (expDiff_l > 9);
        shiftVal_h_fp16 = (shiftedOut_h |expDiff_h[4]) ? 4'd10 : expDiff_h[3:0]; //expDiff_h > 16 (area -4)
        shiftVal_l_fp16 = shiftedOut_l ? 4'd10 : expDiff_l[3:0];

    // FMT_FP8 shift amount: 6-bit lane content (implicit @bit5), so a shift of 5
    // still keeps the implicit bit (@bit0); only diff >= 6 fully flushes it into
    // sticky. Cap at 6 for diff > 5.
        shiftedOut_2 = (expDiff_2 > 4'd5);
        shiftedOut_1 = (expDiff_1 > 4'd5);
        shiftedOut_0 = (expDiff_0 > 4'd5);
        shiftVal_3_fp8 = shiftedOut_h ? 3'd6 : expDiff_3[2:0];
        shiftVal_2_fp8 = shiftedOut_2 ? 3'd6 : expDiff_2[2:0];
        shiftVal_1_fp8 = shiftedOut_1 ? 3'd6 : expDiff_1[2:0];
        shiftVal_0_fp8 = shiftedOut_0 ? 3'd6 : expDiff_0[2:0];
    end


    always_comb begin
        case (fmt)
        FMT_FP32: begin
            shiftVal     = {7'b0, shiftVal_h_fp32};
            significandY   = {1'b1, newY[22:0]};
        end
        FMT_BF16: begin
            shiftVal     = {4'b0, shiftVal_h_fp16, shiftVal_l_fp16};
            significandY   = {significandY_h, 8'b0, significandY_l};
        end
        FMT_FP8: begin
            shiftVal     = {shiftVal_3_fp8,shiftVal_2_fp8,shiftVal_1_fp8,shiftVal_0_fp8};
            significandY = {significandY3, 2'b00, 1'b0, significandY2, 2'b00, significandY1, 2'b00, 1'b0, significandY0};
            //               [23:20]        [19:18] [17] [16:13]       [12:11] [10:7]        [6:5]  [4]  [3:0]
        end
        default: ;
        endcase
    end

    BarrelShifter right_shifter_component (
        .fmt(fmt),
        .shiftAmount(shiftVal),
        .operandX(significandY),
        .result(shiftedMantissaY),
        .sticky(add_sticky)
    );
    /* --- Significand Addition Prep --- */

    // ** Bit Layout (27-bit) [mantissaYpad, EffSub_Vector, mantissaXpad] **:
    //
    // [26:16] Lane High: {padding(2), frac(7), guard, rnd}
    // [15:11] Gap/Zero:  {00000}
    // [10: 0] Lane Low:  {padding(2), frac(7), guard, rnd}
    always_comb begin
        // ---- Y significand placed into the 27b adder layout ----
        // FP32/BF16 : {MSB pad, BarrelShifter output}.
        // FP8       : re-map the BarrelShifter's 6b lanes into Normalizer-aligned
        //             7b slots (L0=[6:0],L1=[13:7],L2=[20:14],L3=[26:21]).
        //             Bits [6]/[13]/[20] are per-lane overflow/gap that isolate
        //             adjacent lanes inside the shared 27b adder.
        case (fmt)
            FMT_FP8 : mantissaYpad = { shiftedMantissaY[25:20],
                                       1'b0, shiftedMantissaY[18:13],
                                       1'b0, shiftedMantissaY[12:7],
                                       1'b0, shiftedMantissaY[5:0] };
            default : mantissaYpad = {1'b0, shiftedMantissaY};
        endcase

        // ---- Effective-sub mask: flip only each lane's CONTENT bits ----
        // The per-lane gap bit stays 0 so the 2's-complement carry stops there
        // and never leaks into the neighbouring lane.
        case (fmt)
            FMT_FP32: EffSub_Vector = {27{EffSub[3]}};
            FMT_BF16: EffSub_Vector = { {11{EffSub[3]}}, 5'b0, {11{EffSub[1]}} };
            FMT_FP8 : EffSub_Vector = { {6{EffSub[3]}},
                                        1'b0, {6{EffSub[2]}},
                                        1'b0, {6{EffSub[1]}},
                                        1'b0, {6{EffSub[0]}} };
            default : EffSub_Vector = '0;
        endcase
        mantissaYpadXorOp = mantissaYpad ^ EffSub_Vector;

        // ---- X significand: same lane layout as mantissaYpad ----
        case (fmt)
            FMT_FP32: mantissaXpad = {2'b01, newX[22:0], 2'b00};
            FMT_BF16: mantissaXpad = { {2'b01, newX.bf16x2.hi[6:0], 2'b0}, 3'b0, 2'b0,
                                       {2'b01, newX.bf16x2.lo[6:0], 2'b0} };
            FMT_FP8 : mantissaXpad = { {1'b1, newX.fp8x4.lane3[2:0], 2'b00},
                                       1'b0, {1'b1, newX.fp8x4.lane2[2:0], 2'b00},
                                       1'b0, {1'b1, newX.fp8x4.lane1[2:0], 2'b00},
                                       1'b0, {1'b1, newX.fp8x4.lane0[2:0], 2'b00} };
            default : mantissaXpad = '0;
        endcase

        add_fracAdder_X = mantissaXpad;       // Connect padded operandX fraction
        add_fracAdder_Y = mantissaYpadXorOp;  // Connect prepared operandY fraction

        // ---- Per-lane carry-in for effective subtraction (x + ~y + 1) ----
        // cin sits at each lane's content LSB; ~sticky absorbs the case where a
        // shifted-out bit already consumed the +1.
        case (fmt)
            FMT_FP32: cin_vec = 27'(EffSub[3] & ~add_sticky[0]);
            FMT_BF16: cin_vec = 27'(EffSub[1] & ~add_sticky[0])
                              | (27'(EffSub[3] & ~add_sticky[2]) << 16);
            FMT_FP8 : cin_vec = 27'(EffSub[0] & ~add_sticky[0])
                              | (27'(EffSub[1] & ~add_sticky[1]) << 7)
                              | (27'(EffSub[2] & ~add_sticky[2]) << 14)
                              | (27'(EffSub[3] & ~add_sticky[3]) << 21);
            default : cin_vec = '0;
        endcase
    end

    /* Execute Significand Addition/Subtraction */
    // 28b sum keeps the carry-out (FP8 lane3 overflow / general MSB overflow).
    assign fracAddSum    = {1'b0, add_fracAdder_X} + {1'b0, add_fracAdder_Y} + {1'b0, cin_vec};
    assign fracAddResult = fracAddSum[26:0];

    // Prepare Normalizer Input (Significand + Sticky)
    always_comb begin
        case (fmt)
            FMT_FP8 : begin
                // adder 7b lanes -> Normalizer FP8 lanes (L0=[6:0],L1=[13:7],L2=[20:14],L3=[27:21])
                fracSticky[6:0]   = fracAddResult[6:0];
                fracSticky[13:7]  = fracAddResult[13:7];
                fracSticky[20:14] = fracAddResult[20:14];
                fracSticky[27:21] = {fracAddSum[27], fracAddResult[26:21]};
                // pad/overflow bit is real only for effective-add; on effective-sub
                // it merely holds the 2's-complement artifact, so clear it.
                if (EffSub[0]) fracSticky[6]  = 1'b0;
                if (EffSub[1]) fracSticky[13] = 1'b0;
                if (EffSub[2]) fracSticky[20] = 1'b0;
                if (EffSub[3]) fracSticky[27] = 1'b0;
                // NOTE: the barrel-shifter sticky is NOT folded into the lane here.
                // Normalization left-shifts the lane (by up to ~2 for FP8), which
                // would carry a folded sticky into the guard position and corrupt
                // rounding. Instead it is OR'd into the post-normalization sticky
                // term (stk_f8) below.
            end
            default : begin
                fracSticky = {fracAddResult, add_sticky[0]};
                if (fmt == FMT_BF16) fracSticky[16] = add_sticky[2];
            end
        endcase
    end

    /* --- LZC and shifter --- */
    Normalizer lzc_and_shifter (
        .clk(clk),
        .fmt(fmt),
        .operandX(fracSticky),
        .count(nZerosNew),
        .result(shiftedFrac)
    );

    // hi-lane / FP32 use count[3]; lo-lane uses count[0]
    assign nZerosNew_h = nZerosNew[3];
    assign nZerosNew_l = nZerosNew[0];

    // Exponent Update
    assign extendedExpInc_h = {1'b0, add_expX_h} + 9'd1;
    assign extendedExpInc_l = {1'b0, add_expX_l} + 9'd1;

    assign normShift_h = {4'b0, nZerosNew_h};
    assign normShift_l = {4'b0, nZerosNew_l};
    assign updatedExp_h = extendedExpInc_h - normShift_h;
    assign updatedExp_l = (fmt == FMT_FP32) ? 8'd0 : (extendedExpInc_l - normShift_l);

    // FP8x4 per-lane exponent update: updatedExp = expX + 1 - leadingZeros
    always_comb begin
        add_expX_f8[3] = newX.fp8x4.lane3[6:3];
        add_expX_f8[2] = newX.fp8x4.lane2[6:3];
        add_expX_f8[1] = newX.fp8x4.lane1[6:3];
        add_expX_f8[0] = newX.fp8x4.lane0[6:3];
        for (int i = 0; i < 4; i++)
            updatedExp_f8[i] = ({1'b0, add_expX_f8[i]} + 5'd1) - nZerosNew[i];
    end



    /* --- rounding --- */
    assign shiftedFrac_h = shiftedFrac[27:14];
    assign shiftedFrac_l = shiftedFrac[13:0];

    // FMT_FP32: exponent uses high lane, rounding uses low lane
    // FMT_FP8 : 4 lanes of {exp(4),frac(3)} at [6:0]/[14:8]/[22:16]/[30:24], gaps [7]/[15]/[23]
    always_comb begin
        case (fmt)
        FMT_FP32: add_expFrac = {updatedExp_h, shiftedFrac_h[12:0], shiftedFrac_l[13:4]}; //[26:3] 暗黙は消えてる
        FMT_BF16: add_expFrac = {updatedExp_h, shiftedFrac_h[12:6],1'b0, updatedExp_l, shiftedFrac_l[10:4]}; //31bit
        FMT_FP8 : add_expFrac = { updatedExp_f8[3][3:0], shiftedFrac[26:24],
                                  1'b0,
                                  updatedExp_f8[2][3:0], shiftedFrac[19:17],
                                  1'b0,
                                  updatedExp_f8[1][3:0], shiftedFrac[12:10],
                                  1'b0,
                                  updatedExp_f8[0][3:0], shiftedFrac[5:3] };
        default : add_expFrac = '0;
        endcase
    end
    assign stk_h = |shiftedFrac_h[4:2];
    assign rnd_h = shiftedFrac_h[5];
    assign lsb_h = shiftedFrac_h[6];

    assign stk_l = |shiftedFrac_l[2:0];
    assign rnd_l = shiftedFrac_l[3];
    assign lsb_l = shiftedFrac_l[4];

    assign add_round_h = rnd_h & (stk_h | lsb_h);
    assign add_round_l = rnd_l & (stk_l | lsb_l);

    // FP8x4 per-lane round bits (guard/round/sticky just below the kept 3-bit frac).
    // The barrel-shifter sticky (bits Y lost to the right shift) always sits below
    // every datapath bit, so it is OR'd straight into the sticky term here.
    always_comb begin
        lsb_f8[0] = shiftedFrac[3];  rnd_f8[0] = shiftedFrac[2];  stk_f8[0] = |shiftedFrac[1:0]  | add_sticky[0];
        lsb_f8[1] = shiftedFrac[10]; rnd_f8[1] = shiftedFrac[9];  stk_f8[1] = |shiftedFrac[8:7]  | add_sticky[1];
        lsb_f8[2] = shiftedFrac[17]; rnd_f8[2] = shiftedFrac[16]; stk_f8[2] = |shiftedFrac[15:14] | add_sticky[2];
        lsb_f8[3] = shiftedFrac[24]; rnd_f8[3] = shiftedFrac[23]; stk_f8[3] = |shiftedFrac[22:21] | add_sticky[3];
        for (int i = 0; i < 4; i++)
            add_round_f8[i] = rnd_f8[i] & (stk_f8[i] | lsb_f8[i]);
    end

    // Add: connect to Shared Rounding Adder
    assign round_vec =
        (fmt == FMT_BF16) ? ((31'(add_round_l)) | (31'(add_round_h) << 16)) :
        (fmt == FMT_FP8)  ? ( 31'(add_round_f8[0])
                            | (31'(add_round_f8[1]) << 8)
                            | (31'(add_round_f8[2]) << 16)
                            | (31'(add_round_f8[3]) << 24))
                          :  (31'(add_round_l));
    assign add_RoundedExpFrac = add_expFrac + round_vec;

    // Pack Result (Sign, Exponent, Mantissa)
    assign add_R_fp32 = {
        signX[3],
        add_RoundedExpFrac   // exp + frac (FMT_FP32)
    };

    assign add_R_fp16 = {
        signX[3],
        add_RoundedExpFrac[30:16], // exp+frac high lane
        signX[1],
        add_RoundedExpFrac[14:0]   // exp+frac low lane
    };

    // FP8x4: 4 lanes of {sign, exp(4), frac(3)} = 8b each
    assign add_R_fp8 = {
        signX[3], add_RoundedExpFrac[30:24],
        signX[2], add_RoundedExpFrac[22:16],
        signX[1], add_RoundedExpFrac[14:8],
        signX[0], add_RoundedExpFrac[6:0]
    };

    assign result = (fmt == FMT_FP32) ? add_R_fp32 :
                   (fmt == FMT_BF16) ? add_R_fp16 :
                                       add_R_fp8;
endmodule


