`timescale 1ns/1ps
    import FpuPkg::*;

// =============================================================================
// Fp8x4MultCSA
// -----------------------------------------------------------------------------
// Multi-precision floating-point multiplier (area-first, fully folded variant):
//   FMT_FP32 : 1 x (24x24)   FMT_BF16 : 2 x (8x8)   FMT_FP8 : 4 x (4x4, E4M3)
//
// This is the reconfigurable Zhan-2019-style sibling of Fp8x4Mult: the dedicated
// per-lane 4x4 multipliers are removed and EVERY format shares one 24x24
// partial-product array.
//
//   * Significand product (reconfigurable masked array):
//       A SINGLE 24x24 partial-product array serves every format. The SIMD
//       lanes are obtained by masking cross-lane partial products at the lane
//       boundaries, so each lane's product lands in its own disjoint bit range
//       of one product.
//
//       Operand packing (mulA / mulB, 24-bit):
//         FMT_FP32 : {1, frac23}                       (one lane)
//         FMT_BF16 : {8'b0, sigHi8, sigLo8}            (hi@[15:8], lo@[7:0])
//         FMT_FP8  : {8'b0, sig3, sig2, sig1, sig0}    (nibble k @ [4k+3:4k])
//
//       Product positions (prodFull):
//         FMT_FP32 : full 48b @ [47:0]          (norm @ 47)
//         FMT_BF16 : lo@[15:0],  hi@[31:16]     (norm @ 15 / 31)
//         FMT_FP8  : lane k @ [8k+7:8k]         (norm @ 8k+7)
//
//       Row mask : for product row j (driven by bit j of B), keep only the A
//       bits in the SAME lane as bit j. Then a_i*b_j is formed only when i,j
//       share a lane, so cross-lane terms vanish and every lane is self
//       contained. FP32 uses an all-ones mask (one lane = the whole array).
//
//   * Exponent path, the 31-bit rounding adder and result packing are shared
//     across all three formats, exactly like Fp8x4Add.
// =============================================================================
module Fp8x4MultCSA(
    input  logic       clk,
    input  FpOp_e      opcode, // 00: Add, 01: Mul, ...
    input  FpFmt_e     fmt,
    input  logic [31:0] operandX,
    input  logic [31:0] operandY,
    output logic [31:0] result
);
    FpVec_u mx, my;
    assign mx.raw = operandX;
    assign my.raw = operandY;

    // -------------------------------------------------------------------------
    // Signs (result sign = Xsign ^ Ysign, per lane)
    // -------------------------------------------------------------------------
    logic       sign_h, sign_l;   // FP32 / BF16-hi (== FP8 lane3) ; BF16-lo (== FP8 lane1)
    logic [3:0] sign_f8;          // FP8 per-lane sign
    assign sign_h     = operandX[31] ^ operandY[31];
    assign sign_l     = operandX[15] ^ operandY[15];
    assign sign_f8[3] = operandX[31] ^ operandY[31];
    assign sign_f8[2] = operandX[23] ^ operandY[23];
    assign sign_f8[1] = operandX[15] ^ operandY[15];
    assign sign_f8[0] = operandX[7]  ^ operandY[7];

    // =========================================================================
    // Exponent sum
    // =========================================================================
    // FP32 / BF16 : bias 127 (8-bit exponents)
    logic [8:0] expSumPreSub_h, expSumPreSub_l;
    logic [9:0] expSum_h, expSum_l;
    assign expSumPreSub_h = mx.fp32.exp     + my.fp32.exp;
    assign expSumPreSub_l = mx.bf16x2.lo[14:7] + my.bf16x2.lo[14:7];
    assign expSum_h = expSumPreSub_h - 9'd127;
    assign expSum_l = expSumPreSub_l - 9'd127;

    // FP8 (E4M3) : bias 7 (4-bit exponents). expSum = expX + expY - 7 (+ norm later)
    logic [3:0] expX_f8 [4], expY_f8 [4];
    always_comb begin
        expX_f8[3] = mx.fp8x4.lane3[6:3];  expY_f8[3] = my.fp8x4.lane3[6:3];
        expX_f8[2] = mx.fp8x4.lane2[6:3];  expY_f8[2] = my.fp8x4.lane2[6:3];
        expX_f8[1] = mx.fp8x4.lane1[6:3];  expY_f8[1] = my.fp8x4.lane1[6:3];
        expX_f8[0] = mx.fp8x4.lane0[6:3];  expY_f8[0] = my.fp8x4.lane0[6:3];
    end

    // =========================================================================
    // Reconfigurable significand multiplier (Zhan-2019-style masked array)
    // -------------------------------------------------------------------------
    // One 24x24 partial-product array, lane boundaries masked (see header).
    //   product = sum_j ( mulB[j] ? ((mulA & rowMask(fmt,j)) << j) : 0 )
    // rowMask keeps only the A bits in the same lane as B bit j.
    // sigProd = {2'b0, prodFull} keeps the FP32/BF16-lo downstream indexing.
    // =========================================================================
    logic [23:0] mulA, mulB;
    logic [47:0] prodFull;
    logic [49:0] sigProd;
    always_comb begin
        case (fmt)
            FMT_FP32: begin
                mulA = {1'b1, mx.fp32.frac};
                mulB = {1'b1, my.fp32.frac};
            end
            FMT_BF16: begin
                mulA = {8'b0, 1'b1, mx.bf16x2.hi[6:0], 1'b1, mx.bf16x2.lo[6:0]};
                mulB = {8'b0, 1'b1, my.bf16x2.hi[6:0], 1'b1, my.bf16x2.lo[6:0]};
            end
            default: begin // FMT_FP8 : four contiguous nibbles
                mulA = {8'b0, 1'b1, mx.fp8x4.lane3[2:0],
                               1'b1, mx.fp8x4.lane2[2:0],
                               1'b1, mx.fp8x4.lane1[2:0],
                               1'b1, mx.fp8x4.lane0[2:0]};
                mulB = {8'b0, 1'b1, my.fp8x4.lane3[2:0],
                               1'b1, my.fp8x4.lane2[2:0],
                               1'b1, my.fp8x4.lane1[2:0],
                               1'b1, my.fp8x4.lane0[2:0]};
            end
        endcase
    end

    always_comb begin
        logic [23:0] rmask;
        prodFull = 48'd0;
        for (int j = 0; j < 24; j++) begin
            case (fmt)
                FMT_FP32: rmask = 24'hFFFFFF;
                FMT_BF16: rmask = (j < 8)  ? 24'h0000FF :
                                  (j < 16) ? 24'h00FF00 : 24'h000000;
                default : rmask = (j < 4)  ? 24'h00000F :
                                  (j < 8)  ? 24'h0000F0 :
                                  (j < 12) ? 24'h000F00 :
                                  (j < 16) ? 24'h00F000 : 24'h000000;
            endcase
            if (mulB[j]) prodFull += (48'(mulA & rmask) << j);
        end
    end
    assign sigProd = {2'b0, prodFull};

    // =========================================================================
    // FP32 / BF16 normalization (single norm bit) + frac extraction
    // BF16 product layout : lo @ [15:0], hi @ [31:16]
    // =========================================================================
    logic norm_h, norm_l;
    logic [7:0] expPostNorm_h, expPostNorm_l;
    logic [47:0] sigProdExt;

    assign norm_h = (fmt == FMT_BF16) ? sigProd[31] : sigProd[47]; // 1x.xx...
    assign norm_l = (fmt == FMT_BF16) ? sigProd[15] : 1'b0;

    assign expPostNorm_h = expSum_h[7:0] + {7'd0, norm_h};
    assign expPostNorm_l = expSum_l[7:0] + {7'd0, norm_l};

    always_comb begin
        sigProdExt = 48'd0;
        if (fmt == FMT_FP32) begin
            sigProdExt = (norm_h) ? {sigProd[46:0], 1'b0} : {sigProd[45:0], 2'b00}; // drop implicit 1
        end else begin
            sigProdExt[47:32] = (norm_h) ? {sigProd[30:16], 1'b0} : {sigProd[29:16], 2'b00};
            sigProdExt[15: 0] = (norm_l) ? {sigProd[14:0], 1'b0} : {sigProd[13:0], 2'b00};
        end
    end

    // FP32 / BF16 round bits : Guard & (LSB | Sticky)
    logic mult_round_32, mult_round_h, mult_round_l;
    assign mult_round_32 = sigProdExt[24] & (sigProdExt[25] | (|sigProdExt[23:0]));
    assign mult_round_h  = sigProdExt[40] & (sigProdExt[41] | (|sigProdExt[39:32]));
    assign mult_round_l  = sigProdExt[8]  & (sigProdExt[9]  | (|sigProdExt[7:0]));

    // =========================================================================
    // FP8 per-lane normalization + frac/round (all 4 lanes from the array)
    // -------------------------------------------------------------------------
    // prod_k = 4b * 4b in [64,225]. norm = bit7 (product >= 2.0).
    // Normalize so the leading 1 sits at bit7:
    //   prodN = norm ? prod : prod<<1
    //   frac3 = prodN[6:4] ; guard = prodN[3] ; sticky = |prodN[2:0]
    //   roundUp = guard & (lsb | round | sticky) = prodN[3] & (prodN[4] | |prodN[2:0])
    // =========================================================================
    logic [7:0] prod_f8 [4];
    logic       norm_f8 [4];
    logic [7:0] prodN_f8 [4];
    logic [2:0] frac3_f8 [4];
    logic       roundup_f8 [4];
    logic [5:0] expSum_f8 [4];   // expX + expY - 7 + norm (4b field used)

    always_comb begin
        prod_f8[0] = prodFull[7:0];
        prod_f8[1] = prodFull[15:8];
        prod_f8[2] = prodFull[23:16];
        prod_f8[3] = prodFull[31:24];
        for (int k = 0; k < 4; k++) begin
            norm_f8[k]    = prod_f8[k][7];
            prodN_f8[k]   = norm_f8[k] ? prod_f8[k] : {prod_f8[k][6:0], 1'b0};
            frac3_f8[k]   = prodN_f8[k][6:4];
            roundup_f8[k] = prodN_f8[k][3] & (prodN_f8[k][4] | (|prodN_f8[k][2:0]));
            expSum_f8[k]  = ({2'b0, expX_f8[k]} + {2'b0, expY_f8[k]})
                          - 6'd7 + {5'b0, norm_f8[k]};
        end
    end

    // =========================================================================
    // Pack exp+frac for the shared 31-bit rounding adder
    //   FP32 : {exp8, frac23}
    //   BF16 : {exp8, frac7} | sign_l@15 | {exp8, frac7}
    //   FP8  : per byte {exp4, frac3} with gap bits [23]/[15]/[7] isolating carries
    // =========================================================================
    logic [30:0] expSig;
    always_comb begin
        case (fmt)
            FMT_FP32: expSig = {expPostNorm_h, sigProdExt[47:25]};
            FMT_BF16: expSig = { {expPostNorm_h, sigProdExt[47:41]},
                                 sign_l,
                                 {expPostNorm_l, sigProdExt[15:9]} };
            default : expSig = { expSum_f8[3][3:0], frac3_f8[3], 1'b0,
                                 expSum_f8[2][3:0], frac3_f8[2], 1'b0,
                                 expSum_f8[1][3:0], frac3_f8[1], 1'b0,
                                 expSum_f8[0][3:0], frac3_f8[0] };
        endcase
    end

    // Shared 31-bit rounding adder : ra_R = ra_X + ra_Y + ra_Cin
    logic [30:0] ra_X, ra_Y, ra_R;
    logic        ra_Cin;
    assign ra_X = expSig;
    always_comb begin
        case (fmt)
            FMT_FP32: begin ra_Y = 31'd0;                          ra_Cin = mult_round_32;   end
            FMT_BF16: begin ra_Y = (31'(mult_round_h) << 16);      ra_Cin = mult_round_l;     end
            default : begin ra_Y = (31'(roundup_f8[1]) << 8)
                                 | (31'(roundup_f8[2]) << 16)
                                 | (31'(roundup_f8[3]) << 24);     ra_Cin = roundup_f8[0];    end
        endcase
    end
    assign ra_R = ra_X + ra_Y + ra_Cin;

    // =========================================================================
    // Result packing
    // =========================================================================
    logic [31:0] mul_R_fp32, mul_R_fp16, mul_R_fp8;
    assign mul_R_fp32 = {sign_h, ra_R};                 // sign + exp + frac
    assign mul_R_fp16 = {sign_h, ra_R};                 // sign_l already at ra_R[15]
    assign mul_R_fp8  = { sign_f8[3], ra_R[30:24],
                          sign_f8[2], ra_R[22:16],
                          sign_f8[1], ra_R[14:8],
                          sign_f8[0], ra_R[6:0] };

    assign result = (fmt == FMT_FP32) ? mul_R_fp32 :
                    (fmt == FMT_BF16) ? mul_R_fp16 :
                                        mul_R_fp8;

endmodule : Fp8x4MultCSA
