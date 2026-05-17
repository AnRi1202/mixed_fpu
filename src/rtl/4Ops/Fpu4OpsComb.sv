`timescale 1ns/1ps
import FpuPkg::*;

module Fpu4OpsComb(
    input  logic                    clk,
    input  FpOp_e                   opcode, // FOP_ADD / FOP_MUL / FOP_SQRT / FOP_DIV
    input  FpFmt_e                  fmt,    // FMT_FP32 / FMT_FP16
    input  logic [FP32_WIDTH-1:0]   operandX,
    input  logic [FP32_WIDTH-1:0]   operandY,
    output logic [FP32_WIDTH-1:0]   result
);

    
    // FPAdd signals
    logic swap;
    logic [7:0] expDiff;
    logic [31:0] newX, newY;
    logic [7:0] add_expX;
    logic signX, signY, EffSub;
    logic [1:0] sXsYExnXY;
    logic [3:0] sdExnXY;
    logic [23:0] mantissaY;
    logic shiftedOut;
    logic [4:0] shiftVal;
    logic [25:0] shiftedMantissaY;
    logic add_sticky;
    logic [26:0] mantissaYpad, EffSubVector, mantissaYpadXorOp, mantissaXpad;
    logic cInSigAdd;
    logic [26:0] fracAddResult;
    logic [27:0] fracSticky;
    logic [4:0] nZerosNew;
    logic [27:0] shiftedFrac;
    logic [8:0] extendedExpInc;
    logic [8:0] updatedExp;
    logic stk, rnd, lsb;
    logic [32:0] RoundedExpFrac;
    logic [22:0] fracR;
    logic [7:0] expR;

    // FPMul signals
    logic sign;
    logic [7:0] mul_expX, expY;
    logic [9:0] expSumPreSub, bias; 
    logic [7:0] expSum;
    logic [23:0] sigX, sigY;
    logic [47:0] sigProd;
    logic norm;
    logic [7:0] expPostNorm;
    logic [47:0] sigProdExt;
    logic [30:0] expSig;
    logic mul_guard_bit, mul_sticky, mul_round, mul_lsb;
    logic [30:0] expSigPostRound;

    // FPDiv signals
    logic [23:0] fX, fY;
    logic [9:0] expR0;
    logic sR;
    logic [23:0] D;
    logic [24:0] psX;
    
    // Div iterations (unrolled)
    // Div iterations (unrolled)
    // is_div removed as per request


    logic [26:0] betaw14, w13;
    logic[26:0] absq14D; // reg/logic for always_comb
    logic [8:0] sel14;
    logic [2:0] q14, q14_copy5;
    
    logic [26:0] betaw13, w12;
    logic[26:0] absq13D;
    logic [8:0] sel13;
    logic [2:0] q13, q13_copy6;
    
    logic [26:0] betaw12, w11;
    logic[26:0] absq12D;
    logic [8:0] sel12;
    logic [2:0] q12, q12_copy7;

    logic [26:0] betaw11, w10;
    logic[26:0] absq11D;
    logic [8:0] sel11;
    logic [2:0] q11, q11_copy8;
    
    logic [26:0] betaw10, w9;
    logic[26:0] absq10D;
    logic [8:0] sel10;
    logic [2:0] q10, q10_copy9;
    
    logic [26:0] betaw9, w8;
    logic[26:0] absq9D;
    logic [8:0] sel9;
    logic [2:0] q9, q9_copy10;
    
    logic [26:0] betaw8, w7;
    logic[26:0] absq8D;
    logic [8:0] sel8;
    logic [2:0] q8, q8_copy11;
    
    logic [26:0] betaw7, w6;
    logic[26:0] absq7D;
    logic [8:0] sel7;
    logic [2:0] q7, q7_copy12;
    
    logic [26:0] betaw6, w5;
    logic[26:0] absq6D;
    logic [8:0] sel6;
    logic [2:0] q6, q6_copy13;
    
    logic [26:0] betaw5, w4;
    logic[26:0] absq5D;
    logic [8:0] sel5;
    logic [2:0] q5, q5_copy14;
    
    logic [26:0] betaw4, w3;
    logic[26:0] absq4D;
    logic [8:0] sel4;
    logic [2:0] q4, q4_copy15;
    
    logic [26:0] betaw3, w2;
    logic[26:0] absq3D;
    logic [8:0] sel3;
    logic [2:0] q3, q3_copy16;
    
    logic [26:0] betaw2, w1;
    logic[26:0] absq2D;
    logic [8:0] sel2;
    logic [2:0] q2, q2_copy17;
    
    logic [26:0] betaw1, w0;
    logic[26:0] absq1D;
    logic [8:0] sel1;
    logic [2:0] q1, q1_copy18;

    logic [24:0] wfinal;
    logic qM0;
    logic [1:0] qP14, qM14, qP13, qM13, qP12, qM12, qP11, qM11, qP10, qM10;
    logic [1:0] qP9, qM9, qP8, qM8, qP7, qM7, qP6, qM6, qP5, qM5, qP4, qM4;
    logic [1:0] qP3, qM3, qP2, qM2, qP1, qM1;
    logic [27:0] qP, qM, quotient;
    logic [25:0] div_mR;
    logic [23:0] fRnorm;
    logic div_round;
    logic [9:0] expR1;
    logic [30:0] expfracR;
    logic [31:0] div_R;

    // FPSqrt signals
    logic [22:0] mantissaX;
    logic [7:0] eRn0;
    logic [7:0] eRn1;
    logic [26:0] mantissaXnorm;
    
    logic [1:0] S0;
    logic [26:0] T1;
    logic d1;
    logic [27:0] T1s;
    logic [5:0] T1s_h, U1, T3_h;
    logic [21:0] T1s_l;
    
    logic [26:0] T2;
    logic [2:0] S1;
    logic d2;
    logic [27:0] T2s;
    logic [6:0] T2s_h, U2, T4_h;
    logic [20:0] T2s_l;

    logic [26:0] T3;
    logic [3:0] S2;
    logic d3;
    logic [27:0] T3s;
    logic [7:0] T3s_h, U3, T5_h;
    logic [19:0] T3s_l;

    logic [26:0] T4;
    logic [4:0] S3;
    logic d4;
    logic [27:0] T4s;
    logic [8:0] T4s_h, U4, T6_h;
    logic [18:0] T4s_l;
    
    logic [26:0] T5;
    logic [5:0] S4;
    logic d5;
    logic [27:0] T5s;
    logic [9:0] T5s_h, U5, T7_h;
    logic [17:0] T5s_l;

    logic [26:0] T6;
    logic [6:0] S5;
    logic d6;
    logic [27:0] T6s;
    logic [10:0] T6s_h, U6, T8_h;
    logic [16:0] T6s_l;

    logic [26:0] T7;
    logic [7:0] S6;
    logic d7;
    logic [27:0] T7s;
    logic [11:0] T7s_h, U7, T9_h;
    logic [15:0] T7s_l;
    
    logic [26:0] T8;
    logic [8:0] S7;
    logic d8;
    logic [27:0] T8s;
    logic [12:0] T8s_h, U8, T10_h;
    logic [14:0] T8s_l;

    logic [26:0] T9;
    logic [9:0] S8;
    logic d9;
    logic [27:0] T9s;
    logic [13:0] T9s_h, U9, T11_h;
    logic [13:0] T9s_l;

    logic [26:0] T10;
    logic [10:0] S9;
    logic d10;
    logic [27:0] T10s;
    logic [14:0] T10s_h, U10, T12_h;
    logic [12:0] T10s_l;
    
    logic [26:0] T11;
    logic [11:0] S10;
    logic d11;
    logic [27:0] T11s;
    logic [15:0] T11s_h, U11, T13_h;
    logic [11:0] T11s_l;
    
    logic [26:0] T12;
    logic [12:0] S11;
    logic d12;
    logic [27:0] T12s;
    logic [16:0] T12s_h, U12, T14_h;
    logic [10:0] T12s_l;
    
    logic [26:0] T13;
    logic [13:0] S12;
    logic d13;
    logic [27:0] T13s;
    logic [17:0] T13s_h, U13, T15_h;
    logic [9:0] T13s_l;
    
    logic [26:0] T14;
    logic [14:0] S13;
    logic d14;
    logic [27:0] T14s;
    logic [18:0] T14s_h, U14, T16_h;
    logic [8:0] T14s_l;
    
    logic [26:0] T15;
    logic [15:0] S14;
    logic d15;
    logic [27:0] T15s;
    logic [19:0] T15s_h, U15, T17_h;
    logic [7:0] T15s_l;
    
    logic [26:0] T16;
    logic [16:0] S15;
    logic d16;
    logic [27:0] T16s;
    logic [20:0] T16s_h, U16, T18_h;
    logic [6:0] T16s_l;
    
    logic [26:0] T17;
    logic [17:0] S16;
    logic d17;
    logic [27:0] T17s;
    logic [21:0] T17s_h, U17, T19_h;
    logic [5:0] T17s_l;
    
    logic [26:0] T18;
    logic [18:0] S17;
    logic d18;
    logic [27:0] T18s;
    logic [22:0] T18s_h, U18, T20_h;
    logic [4:0] T18s_l;
    
    logic [26:0] T19;
    logic [19:0] S18;
    logic d19;
    logic [27:0] T19s;
    logic [23:0] T19s_h, U19, T21_h;
    logic [3:0] T19s_l;

    logic [26:0] T20;
    logic [20:0] S19;
    logic d20;
    logic [27:0] T20s;
    logic [24:0] T20s_h, U20, T22_h;
    logic [2:0] T20s_l;
    
    logic [26:0] T21;
    logic [21:0] S20;
    logic d21;
    logic [27:0] T21s;
    logic [25:0] T21s_h, U21, T23_h;
    logic [1:0] T21s_l;
    
    logic [26:0] T22;
    logic [22:0] S21;
    logic d22;
    logic [27:0] T22s;
    logic [26:0] T22s_h, U22, T24_h;
    logic [0:0] T22s_l;
    
    logic [26:0] T23;
    logic [23:0] S22;
    logic d23;
    logic [27:0] T23s;
    logic [27:0] T23s_h, U23, T25_h;
    
    logic [26:0] T24;
    logic [24:0] S23;
    logic d25;
    logic [25:0] sqrt_mR;
    logic [22:0] fR;
    logic sqrt_round;
    logic [22:0] fRrnd;
    logic [30:0] Rn2;
    logic [31:0] sqrt_R;
    logic [22:0] sqrt_expFrac;

    // Shared Add/Sub Signals
    // Gen 0
    logic [27:0] shared_as_x0, shared_as_y0;
    logic shared_as_sub0;
    logic [27:0] shared_as_r0, sub_mask0, y_xor0, cin_vec0;
    
    // Gen 1
    logic [26:0] shared_as_x1, shared_as_y1;
    logic shared_as_sub1;
    logic [26:0] shared_as_r1;
    
    // Gen 2
    logic [26:0] shared_as_x2, shared_as_y2;
    logic shared_as_sub2;
    logic [26:0] shared_as_r2, sub_mask2, y_xor2, cin_vec2;
    
    // Gen 3
    logic [26:0] shared_as_x3, shared_as_y3;
    logic shared_as_sub3;
    logic [26:0] shared_as_r3, sub_mask3, y_xor3, cin_vec3;
    
    // Gen 4
    logic [26:0] shared_as_x4, shared_as_y4;
    logic shared_as_sub4;
    logic [26:0] shared_as_r4, sub_mask4, y_xor4, cin_vec4;
    
    // Gen 5
    logic [26:0] shared_as_x5, shared_as_y5;
    logic shared_as_sub5;
    logic [26:0] shared_as_r5;
    
    // Gen 6
    logic [26:0] shared_as_x6, shared_as_y6;
    logic shared_as_sub6;
    logic [26:0] shared_as_r6;
    
    // Gen 7
    logic [26:0] shared_as_x7, shared_as_y7;
    logic shared_as_sub7;
    logic [26:0] shared_as_r7;

    // Gen 8
    logic [26:0] shared_as_x8, shared_as_y8;
    logic shared_as_sub8;
    logic [26:0] shared_as_r8;
    
    // Gen 9
    logic [26:0] shared_as_x9, shared_as_y9;
    logic shared_as_sub9;
    logic [26:0] shared_as_r9;
    
    // Gen 10
    logic [26:0] shared_as_x10, shared_as_y10;
    logic shared_as_sub10;
    logic [26:0] shared_as_r10;
    
    // Gen 11
    logic [26:0] shared_as_x11, shared_as_y11;
    logic shared_as_sub11;
    logic [26:0] shared_as_r11;
    
    // Gen 12
    logic [26:0] shared_as_x12, shared_as_y12;
    logic shared_as_sub12;
    logic [26:0] shared_as_r12;
    
    // Gen 13
    logic [26:0] shared_as_x13, shared_as_y13;
    logic shared_as_sub13;
    logic [26:0] shared_as_r13, sub_mask13, y_xor13, cin_vec13;

    // Shared Output Signals
    logic [31:0] add_R, mul_R;
    logic [30:0] add_expFrac;
    logic add_round;
    // logic mul_round; // already defined
    logic [30:0] ra_X, ra_R;
    logic [30:0] add_ra_X, mul_ra_X, div_ra_X, sqrt_ra_X;
    logic ra_Cin;
    
    logic [26:0] add_fracAdder_X, add_fracAdder_Y, add_fracAdder_R;
    logic [26:0] ia27_X, ia27_Y, ia27_R;
    logic ia27_Cin;
    logic add_fracAdder_Cin;
    
    logic [7:0] mul_expAdder_X, mul_expAdder_Y;
    logic mul_expAdder_Cin;
    logic [8:0] mul_expAdder_R; 
    

    // =================================================================================
    // FPAdd Logic
    // =================================================================================

    assign swap = (operandX[30:0] < operandY[30:0]); //comparator
    // input swap so that |operandX|>|operandY| 
    assign newX = (swap == 1'b0) ? operandX : operandY; 
    assign newY = (swap == 1'b0) ? operandY : operandX; 
    // exponent difference
    assign expDiff = newX[30:23] - newY[30:23]; 
    // now we decompose the inputs into their sign, exponent, fraction 
    assign add_expX = newX[30:23];
    assign signX = newX[31];
    assign signY = newY[31];
    assign EffSub = signX ^ signY;
    
    assign mantissaY = {1'b1, newY[22:0]};
    
    assign shiftedOut = (expDiff > 8'd25) ? 1'b1 : 1'b0;
    assign shiftVal = (shiftedOut == 1'b0) ? expDiff[4:0] : 5'd26;

    RightShifterSticky24_by_max_26_Freq1_uid4 right_shifter_component (
        .clk(clk),
        .S(shiftVal),
        .X(mantissaY),
        .R(shiftedMantissaY),
        .Sticky(add_sticky)
    );
    
    assign mantissaYpad = {1'b0, shiftedMantissaY};
    assign EffSubVector = {27{EffSub}};
    assign mantissaYpadXorOp = mantissaYpad ^ EffSubVector;
    assign mantissaXpad = {2'b01, newX[22:0], 2'b00};
    assign cInSigAdd = EffSub & (~add_sticky); // if we subtract and the sticky was one, some of the negated sticky bits would have absorbed this carry 

    // Connect to Shared IntAdder_27
    assign add_fracAdder_X = mantissaXpad;       // Connect padded operandX fraction
    assign add_fracAdder_Y = mantissaYpadXorOp;  // Connect prepared operandY fraction
    assign add_fracAdder_Cin = cInSigAdd;    // Carry-in accounting for subtraction and sticky bit
    assign fracAddResult = add_fracAdder_R;  // Get addition result back
    
    assign fracSticky = {fracAddResult, add_sticky};
    
    Normalizer_Z_28_28_28_Freq1_uid8 lzc_and_shifter (
        .clk(clk),
        .X(fracSticky),
        .Count(nZerosNew),
        .R(shiftedFrac)
    );
    
    assign extendedExpInc = {1'b0, add_expX} + 9'd1;
    assign updatedExp = {extendedExpInc} - {4'b0000, nZerosNew};
    
    assign add_expFrac = {updatedExp[7:0], shiftedFrac[26:4]}; //8bit + 23bit
    assign stk = shiftedFrac[2] | shiftedFrac[1] | shiftedFrac[0];
    assign rnd = shiftedFrac[3];
    assign lsb = shiftedFrac[4];
    // Connect to Shared Rounding Adder
    assign add_ra_X = add_expFrac; 
    assign add_round = ((rnd == 1'b1) && (stk == 1'b1)) || ((rnd == 1'b1) && (stk == 1'b0) && (lsb == 1'b1)) ? 1'b1 : 1'b0;
    // Get result from Shared Rounding Adder
    assign RoundedExpFrac = ra_R;
    assign fracR = RoundedExpFrac[22:0];
    assign expR = RoundedExpFrac[30:23];
    
    assign add_R = {signX, expR, fracR};

    
    // =================================================================================
    // FPMult Logic
    // =================================================================================
    
    assign sign = operandX[31] ^ operandY[31];
    assign mul_expX = operandX[30:23];
    assign expY = operandY[30:23];
    
    // Connect to Shared IntAdder_27
    assign mul_expAdder_X = mul_expX;        // Connect exponent operandX
    assign mul_expAdder_Y = expY;            // Connect exponent operandY
    assign mul_expAdder_Cin = 1'b0;          // No carry-in needed for simple addition
    assign expSumPreSub = {1'b0, mul_expAdder_R[8:0]}; // Get addition result
    
    assign bias = 10'd127;
    assign expSum = expSumPreSub - bias;
    
    assign sigX = {1'b1, operandX[22:0]};
    assign sigY = {1'b1, operandY[22:0]};
    
    assign sigProd = sigX * sigY;
    // exponent update 
    assign norm = sigProd[47];
    assign expPostNorm = expSum + {7'd0, norm};
    // significand normalization shift 
    assign sigProdExt = (norm == 1'b1) ? {sigProd[46:0], 1'b0} : {sigProd[45:0], 2'b00};
    assign expSig = {expPostNorm, sigProdExt[47:25]}; 
    assign mul_guard_bit = sigProdExt[24];
    assign mul_sticky = |sigProdExt[23:0];
    assign mul_lsb = sigProdExt[25];
    assign mul_round = mul_guard_bit & (mul_sticky | mul_lsb);
    
    // Connect to Shared Rounding Adder
    assign mul_ra_X =  expSig; 
    
    // Get result from Shared Rounding Adder
    assign expSigPostRound = ra_R;
    assign mul_R = {sign, expSigPostRound};


    // =================================================================================
    // FPDiv Logic
    // =================================================================================

    assign fX = {1'b1, operandX[22:0]};
    assign fY = {1'b1, operandY[22:0]};
    // exponent difference, sign and exception combination computed early, to have fewer bits to pipeline
    assign expR0 = {2'b00, operandX[30:23]} - {2'b00, operandY[30:23]};
    assign sR = operandX[31] ^ operandY[31];
    
    // early exception handling (not fully implemented in this SV version as per previous code, but keeping structure)
    
    assign D = fY;
    assign psX = {1'b0, fX};
    assign betaw14 = {2'b00, psX};
    assign sel14 = {betaw14[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_14 (
        .operandX(sel14),
        .y_o(q14_copy5)
    );
    assign q14 = q14_copy5; // output copy to hold a pipeline register if needed
    
    always_comb begin
        case(q14)
            3'b001, 3'b111: absq14D = {3'b000, D};       // mult by 1
            3'b010, 3'b110: absq14D = {2'b00, D, 1'b0};  // mult by 2
            default: absq14D = 27'd0;                    // mult by 0
        endcase
    end
    
    // Shared Logic Connection for w13
    // Shared Logic Connection for w13
    assign w13 = shared_as_r13; // Connect result from Shared Add/Sub Logic Step 13 (Divider Step 13)

    assign betaw13 = {w13[24:0], 2'b00}; // multiplication by the radix
    assign sel13 = {betaw13[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_13 (
        .operandX(sel13),
        .y_o(q13_copy6)
    );
    assign q13 = q13_copy6; // output copy to hold a pipeline register if needed
    
    always_comb begin
        case(q13)
            3'b001, 3'b111: absq13D = {3'b000, D};       // mult by 1
            3'b010, 3'b110: absq13D = {2'b00, D, 1'b0};  // mult by 2
            default: absq13D = 27'd0;                    // mult by 0
        endcase
    end

    // Shared Logic Connection for w12
    assign w12 = shared_as_r12;

    assign betaw12 = {w12[24:0], 2'b00};
    assign sel12 = {betaw12[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_12 (
        .operandX(sel12),
        .y_o(q12_copy7)
    );
    assign q12 = q12_copy7;

    always_comb begin
        case(q12)
            3'b001, 3'b111: absq12D = {3'b000, D};
            3'b010, 3'b110: absq12D = {2'b00, D, 1'b0};
            default: absq12D = 27'd0;
        endcase
    end
    
    // Shared Logic Connection for w11
    assign w11 = shared_as_r11;

    assign betaw11 = {w11[24:0], 2'b00};
    assign sel11 = {betaw11[26:21], D[22:20]};

    SelFunctionFreq1Uid4 sel_function_table_11 (
        .operandX(sel11),
        .y_o(q11_copy8)
    );
    assign q11 = q11_copy8;
    
    always_comb begin
        case(q11)
            3'b001, 3'b111: absq11D = {3'b000, D};
            3'b010, 3'b110: absq11D = {2'b00, D, 1'b0};
            default: absq11D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w10
    assign w10 = shared_as_r10;

    assign betaw10 = {w10[24:0], 2'b00};
    assign sel10 = {betaw10[26:21], D[22:20]};

    SelFunctionFreq1Uid4 sel_function_table_10 (
        .operandX(sel10),
        .y_o(q10_copy9)
    );
    assign q10 = q10_copy9;
    
    always_comb begin
        case(q10)
            3'b001, 3'b111: absq10D = {3'b000, D};
            3'b010, 3'b110: absq10D = {2'b00, D, 1'b0};
            default: absq10D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w9
    assign w9 = shared_as_r9;

    assign betaw9 = {w9[24:0], 2'b00};
    assign sel9 = {betaw9[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_9 (
        .operandX(sel9),
        .y_o(q9_copy10)
    );
    assign q9 = q9_copy10;
    
    always_comb begin
        case(q9)
            3'b001, 3'b111: absq9D = {3'b000, D};
            3'b010, 3'b110: absq9D = {2'b00, D, 1'b0};
            default: absq9D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w8
    assign w8 = shared_as_r8;

    assign betaw8 = {w8[24:0], 2'b00};
    assign sel8 = {betaw8[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_8 (
        .operandX(sel8),
        .y_o(q8_copy11)
    );
    assign q8 = q8_copy11;
    
    always_comb begin
        case(q8)
            3'b001, 3'b111: absq8D = {3'b000, D};
            3'b010, 3'b110: absq8D = {2'b00, D, 1'b0};
            default: absq8D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w7
    assign w7 = shared_as_r7;

    assign betaw7 = {w7[24:0], 2'b00};
    assign sel7 = {betaw7[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_7 (
        .operandX(sel7),
        .y_o(q7_copy12)
    );
    assign q7 = q7_copy12;
    
    always_comb begin
        case(q7)
            3'b001, 3'b111: absq7D = {3'b000, D};
            3'b010, 3'b110: absq7D = {2'b00, D, 1'b0};
            default: absq7D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w6
    assign w6 = shared_as_r6;

    assign betaw6 = {w6[24:0], 2'b00};
    assign sel6 = {betaw6[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_6 (
        .operandX(sel6),
        .y_o(q6_copy13)
    );
    assign q6 = q6_copy13;
    
    always_comb begin
        case(q6)
            3'b001, 3'b111: absq6D = {3'b000, D};
            3'b010, 3'b110: absq6D = {2'b00, D, 1'b0};
            default: absq6D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w5
    assign w5 = shared_as_r5;

    assign betaw5 = {w5[24:0], 2'b00};
    assign sel5 = {betaw5[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_5 (
        .operandX(sel5),
        .y_o(q5_copy14)
    );
    assign q5 = q5_copy14;
    
    always_comb begin
        case(q5)
            3'b001, 3'b111: absq5D = {3'b000, D};
            3'b010, 3'b110: absq5D = {2'b00, D, 1'b0};
            default: absq5D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w4
    assign w4 = shared_as_r4;

    assign betaw4 = {w4[24:0], 2'b00};
    assign sel4 = {betaw4[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_4 (
        .operandX(sel4),
        .y_o(q4_copy15)
    );
    assign q4 = q4_copy15;
    
    always_comb begin
        case(q4)
            3'b001, 3'b111: absq4D = {3'b000, D};
            3'b010, 3'b110: absq4D = {2'b00, D, 1'b0};
            default: absq4D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w3
    assign w3 = shared_as_r3;

    assign betaw3 = {w3[24:0], 2'b00};
    assign sel3 = {betaw3[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_3 (
        .operandX(sel3),
        .y_o(q3_copy16)
    );
    assign q3 = q3_copy16;
    
    always_comb begin
        case(q3)
            3'b001, 3'b111: absq3D = {3'b000, D};
            3'b010, 3'b110: absq3D = {2'b00, D, 1'b0};
            default: absq3D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w2
    assign w2 = shared_as_r2;

    assign betaw2 = {w2[24:0], 2'b00};
    assign sel2 = {betaw2[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_2 (
        .operandX(sel2),
        .y_o(q2_copy17)
    );
    assign q2 = q2_copy17;
    
    always_comb begin
        case(q2)
            3'b001, 3'b111: absq2D = {3'b000, D};
            3'b010, 3'b110: absq2D = {2'b00, D, 1'b0};
            default: absq2D = 27'd0;
        endcase
    end

    // Shared Logic Connection for w1
    assign w1 = shared_as_r1;

    assign betaw1 = {w1[24:0], 2'b00};
    assign sel1 = {betaw1[26:21], D[22:20]};
    
    SelFunctionFreq1Uid4 sel_function_table_1 (
        .operandX(sel1),
        .y_o(q1_copy18)
    );
    assign q1 = q1_copy18;
    
    always_comb begin
        case(q1)
            3'b001, 3'b111: absq1D = {3'b000, D};
            3'b010, 3'b110: absq1D = {2'b00, D, 1'b0};
            default: absq1D = 27'd0;
        endcase
    end
    
    // Shared Logic Connection for w0
    assign w0 = shared_as_r0[26:0];
    
    assign wfinal = w0[24:0];
    assign qM0 = wfinal[24]; // rounding bit is the sign of the remainder
    
    assign qP14 = q14[1:0]; assign qM14 = {q14[2], 1'b0};
    assign qP13 = q13[1:0]; assign qM13 = {q13[2], 1'b0};
    assign qP12 = q12[1:0]; assign qM12 = {q12[2], 1'b0};
    assign qP11 = q11[1:0]; assign qM11 = {q11[2], 1'b0};
    assign qP10 = q10[1:0]; assign qM10 = {q10[2], 1'b0};
    assign qP9  = q9[1:0];  assign qM9  = {q9[2], 1'b0};
    assign qP8  = q8[1:0];  assign qM8  = {q8[2], 1'b0};
    assign qP7  = q7[1:0];  assign qM7  = {q7[2], 1'b0};
    assign qP6  = q6[1:0];  assign qM6  = {q6[2], 1'b0};
    assign qP5  = q5[1:0];  assign qM5  = {q5[2], 1'b0};
    assign qP4  = q4[1:0];  assign qM4  = {q4[2], 1'b0};
    assign qP3  = q3[1:0];  assign qM3  = {q3[2], 1'b0};
    assign qP2  = q2[1:0];  assign qM2  = {q2[2], 1'b0};
    assign qP1  = q1[1:0];  assign qM1  = {q1[2], 1'b0};
    
    assign qP = {qP14, qP13, qP12, qP11, qP10, qP9, qP8, qP7, qP6, qP5, qP4, qP3, qP2, qP1};
    assign qM = {qM14[0], qM13, qM12, qM11, qM10, qM9, qM8, qM7, qM6, qM5, qM4, qM3, qM2, qM1, qM0};
    
    assign quotient = qP - qM;
    // We need a mR in (0, -wf-2) format: 1+wF fraction bits, 1 round bit, and 1 guard bit for the normalisation,
    // quotient is the truncation of the exact quotient to at least 2^(-wF-2) bits
    // now discarding its possible known MSB zeroes, and dropping the possible extra LSB bit (due to radix 4)
    assign div_mR = quotient[26:1];
    
    // normalisation
    assign fRnorm = (div_mR[25] == 1'b1) ? div_mR[24:1] : div_mR[23:0]; // now fRnorm is a (-1, -wF-1) fraction
    assign div_round = fRnorm[0];
    
    assign expR1 = expR0 + {3'b000, 6'b111111, div_mR[25]}; // add back bias
    // final rounding
    assign div_ra_X = {expR1[7:0], fRnorm[23:1]};
    // Connect to Shared Rounding Adder
    // Get result from Shared Rounding Adder
    assign expfracR = ra_R;
    assign div_R = {sR, expfracR};


    // =================================================================================
    // FPSqrt Logic
    // =================================================================================

    assign mantissaX = operandX[22:0]; // fraction
    assign eRn0 = {1'b0, operandX[30:24]}; // exponent
    
    assign eRn1 = eRn0 + {2'b00, 6'b111111} + {7'd0, operandX[23]}; 
    
    assign mantissaXnorm = (operandX[23] == 1'b0) ? {1'b1, mantissaX, 3'b000} : {2'b01, mantissaX, 2'b00}; // pre-normalization
    
    assign S0 = 2'b01;
    assign T1 = {4'b0111 + mantissaXnorm[26:23], mantissaXnorm[22:0]};
    // now implementing the recurrence 
    //  this is a binary non-restoring algorithm, see ASA book
    // Step 2
    
    // Step 2
    assign d1 = ~T1[26]; //  bit of weight -1
    assign T1s = {T1, 1'b0};
    assign T1s_h = T1s[27:22];
    assign T1s_l = T1s[21:0];
    assign U1 = {1'b0, S0, d1, ~d1, 1'b1};
    
    assign T3_h = (d1 == 1'b1) ? (T1s_h - U1) : (T1s_h + U1);
    assign T2 = {T3_h[4:0], T1s_l};
    assign S1 = {S0, d1}; // here -1 becomes 0 and 1 becomes 1
    
    // Step 3
    assign d2 = ~T2[26]; //  bit of weight -2
    assign T2s = {T2, 1'b0};
    assign T2s_h = T2s[27:21];
    assign T2s_l = T2s[20:0];
    assign U2 = {1'b0, S1, d2, ~d2, 1'b1};
    
    assign T4_h = (d2 == 1'b1) ? (T2s_h - U2) : (T2s_h + U2);
    assign T3 = {T4_h[5:0], T2s_l};
    assign S2 = {S1, d2};
    
    // Step 4
    assign d3 = ~T3[26];
    assign T3s = {T3, 1'b0};
    assign T3s_h = T3s[27:20];
    assign T3s_l = T3s[19:0];
    assign U3 = {1'b0, S2, d3, ~d3, 1'b1};
    
    assign T5_h = (d3 == 1'b1) ? (T3s_h - U3) : (T3s_h + U3);
    assign T4 = {T5_h[6:0], T3s_l};
    assign S3 = {S2, d3};
    
    // Step 5
    assign d4 = ~T4[26];
    assign T4s = {T4, 1'b0};
    assign T4s_h = T4s[27:19];
    assign T4s_l = T4s[18:0];
    assign U4 = {1'b0, S3, d4, ~d4, 1'b1};
    
    assign T6_h = (d4 == 1'b1) ? (T4s_h - U4) : (T4s_h + U4);
    assign T5 = {T6_h[7:0], T4s_l};
    assign S4 = {S3, d4};

    // Step 6
    assign d5 = ~T5[26];
    assign T5s = {T5, 1'b0};
    assign T5s_h = T5s[27:18];
    assign T5s_l = T5s[17:0];
    assign U5 = {1'b0, S4, d5, ~d5, 1'b1};
    
    assign T7_h = (d5 == 1'b1) ? (T5s_h - U5) : (T5s_h + U5);
    assign T6 = {T7_h[8:0], T5s_l};
    assign S5 = {S4, d5};
    
    // Step 7
    assign d6 = ~T6[26];
    assign T6s = {T6, 1'b0};
    assign T6s_h = T6s[27:17];
    assign T6s_l = T6s[16:0];
    assign U6 = {1'b0, S5, d6, ~d6, 1'b1};
    
    assign T8_h = (d6 == 1'b1) ? (T6s_h - U6) : (T6s_h + U6);
    assign T7 = {T8_h[9:0], T6s_l};
    assign S6 = {S5, d6};
    
    // Step 8
    assign d7 = ~T7[26];
    assign T7s = {T7, 1'b0};
    assign T7s_h = T7s[27:16];
    assign T7s_l = T7s[15:0];
    assign U7 = {1'b0, S6, d7, ~d7, 1'b1};
    
    assign T9_h = (d7 == 1'b1) ? (T7s_h - U7) : (T7s_h + U7);
    assign T8 = {T9_h[10:0], T7s_l};
    assign S7 = {S6, d7};
    
    // Step 9
    assign d8 = ~T8[26];
    assign T8s = {T8, 1'b0};
    assign T8s_h = T8s[27:15];
    assign T8s_l = T8s[14:0];
    assign U8 = {1'b0, S7, d8, ~d8, 1'b1};
    
    assign T10_h = (d8 == 1'b1) ? (T8s_h - U8) : (T8s_h + U8);
    assign T9 = {T10_h[11:0], T8s_l};
    assign S8 = {S7, d8};
    
    // Step 10
    assign d9 = ~T9[26];
    assign T9s = {T9, 1'b0};

    assign T9s_h = T9s[27:14];
    assign T9s_l = T9s[13:0];
    assign U9 = {1'b0, S8, d9, ~d9, 1'b1};
    
    assign T11_h = (d9 == 1'b1) ? (T9s_h - U9) : (T9s_h + U9);
    assign T10 = {T11_h[12:0], T9s_l};
    assign S9 = {S8, d9};
    
    // Step 11
    assign d10 = ~T10[26];
    assign T10s = {T10, 1'b0};
    assign T10s_h = T10s[27:13];
    assign T10s_l = T10s[12:0];
    assign U10 = {1'b0, S9, d10, ~d10, 1'b1};
    
    // Shared Logic Connection for T12_h (Index 11, Step 11)
    assign T12_h = shared_as_r13[14:0];
    assign T11 = {T12_h[13:0], T10s_l};
    assign S10 = {S9, d10};
    
    // Step 12
    assign d11 = ~T11[26];
    assign T11s = {T11, 1'b0};
    assign T11s_h = T11s[27:12];
    assign T11s_l = T11s[11:0];
    assign U11 = {1'b0, S10, d11, ~d11, 1'b1};

    // Shared Logic Connection for T13_h (Index 12)
    assign T13_h = shared_as_r12[15:0];
    assign T12 = {T13_h[14:0], T11s_l};
    assign S11 = {S10, d11};

    // Step 13
    assign d12 = ~T12[26];
    assign T12s = {T12, 1'b0};
    assign T12s_h = T12s[27:11];
    assign T12s_l = T12s[10:0];
    assign U12 = {1'b0, S11, d12, ~d12, 1'b1};
    
    // Shared Logic Connection for T14_h (Index 11)
    assign T14_h = shared_as_r11[16:0];
    assign T13 = {T14_h[15:0], T12s_l};
    assign S12 = {S11, d12};
    
    // Step 14
    assign d13 = ~T13[26];
    assign T13s = {T13, 1'b0};
    assign T13s_h = T13s[27:10];
    assign T13s_l = T13s[9:0];
    assign U13 = {1'b0, S12, d13, ~d13, 1'b1};
    
    // Shared Logic Connection for T15_h (Index 10)
    assign T15_h = shared_as_r10[17:0];
    assign T14 = {T15_h[16:0], T13s_l};
    assign S13 = {S12, d13};

    // Step 15
    assign d14 = ~T14[26];
    assign T14s = {T14, 1'b0};
    assign T14s_h = T14s[27:9];
    assign T14s_l = T14s[8:0];
    assign U14 = {1'b0, S13, d14, ~d14, 1'b1};
    
    // Shared Logic Connection for T16_h (Index 9)
    assign T16_h = shared_as_r9[18:0];
    assign T15 = {T16_h[17:0], T14s_l};
    assign S14 = {S13, d14};
    
    // Step 16
    assign d15 = ~T15[26];
    assign T15s = {T15, 1'b0};
    assign T15s_h = T15s[27:8];
    assign T15s_l = T15s[7:0];
    assign U15 = {1'b0, S14, d15, ~d15, 1'b1};
    
    // Shared Logic Connection for T17_h
    assign T17_h = shared_as_r8[19:0];
    assign T16 = {T17_h[18:0], T15s_l};
    assign S15 = {S14, d15};

    // Step 17
    assign d16 = ~T16[26];
    assign T16s = {T16, 1'b0};
    assign T16s_h = T16s[27:7];
    assign T16s_l = T16s[6:0];
    assign U16 = {1'b0, S15, d16, ~d16, 1'b1};
    
    // Shared Logic Connection for T18_h
    assign T18_h = shared_as_r7[20:0];
    assign T17 = {T18_h[19:0], T16s_l};
    assign S16 = {S15, d16};

    // Step 18
    assign d17 = ~T17[26];
    assign T17s = {T17, 1'b0};
    assign T17s_h = T17s[27:6];
    assign T17s_l = T17s[5:0];
    assign U17 = {1'b0, S16, d17, ~d17, 1'b1};
    
    // Shared Logic Connection for T19_h
    assign T19_h = shared_as_r6[21:0];
    assign T18 = {T19_h[20:0], T17s_l};
    assign S17 = {S16, d17};
    
    // Step 19
    assign d18 = ~T18[26];
    assign T18s = {T18, 1'b0};
    assign T18s_h = T18s[27:5];
    assign T18s_l = T18s[4:0];
    assign U18 = {1'b0, S17, d18, ~d18, 1'b1};
    
    // Shared Logic Connection for T20_h
    assign T20_h = shared_as_r5[22:0];
    assign T19 = {T20_h[21:0], T18s_l};
    assign S18 = {S17, d18};
    
    // Step 20
    assign d19 = ~T19[26];
    assign T19s = {T19, 1'b0};
    assign T19s_h = T19s[27:4];
    assign T19s_l = T19s[3:0];
    assign U19 = {1'b0, S18, d19, ~d19, 1'b1};
    
    // Shared Logic Connection for T21_h
    assign T21_h = shared_as_r4[23:0];
    assign T20 = {T21_h[22:0], T19s_l};
    assign S19 = {S18, d19};
    
    // Step 21
    assign d20 = ~T20[26];
    assign T20s = {T20, 1'b0};
    assign T20s_h = T20s[27:3];
    assign T20s_l = T20s[2:0];
    assign U20 = {1'b0, S19, d20, ~d20, 1'b1};
    
    // Shared Logic Connection for T22_h
    assign T22_h = shared_as_r3[24:0];
    assign T21 = {T22_h[23:0], T20s_l};
    assign S20 = {S19, d20};

    // Step 22
    assign d21 = ~T21[26];
    assign T21s = {T21, 1'b0};
    assign T21s_h = T21s[27:2];
    assign T21s_l = T21s[1:0];
    assign U21 = {1'b0, S20, d21, ~d21, 1'b1};

    // Shared Logic Connection for T23_h
    assign T23_h = shared_as_r2[25:0];
    assign T22 = {T23_h[24:0], T21s_l};
    assign S21 = {S20, d21};
    
    // Step 23
    assign d22 = ~T22[26];
    assign T22s = {T22, 1'b0};
    assign T22s_h = T22s[27:1];
    assign T22s_l = T22s[0:0];
    assign U22 = {1'b0, S21, d22, ~d22, 1'b1};
    
    // Shared Logic Connection for T24_h
    assign T24_h = shared_as_r1;
    assign T23 = {T24_h[25:0], T22s_l};
    assign S22 = {S21, d22};
    
    // Step 24
    assign d23 = ~T23[26];
    assign T23s = {T23, 1'b0};
    assign T23s_h = T23s[27:0];
    assign U23 = {1'b0, S22, d23, ~d23, 1'b1};

    // Shared Logic Connection for T25_h
    assign T25_h = shared_as_r0;
    assign T24 = T25_h[26:0];
    assign S23 = {S22, d23}; // here -1 becomes 0 and 1 becomes 1
    assign d25 = ~T24[26]; // the sign of the remainder will become the round bit
    
    assign sqrt_mR = {S23, d25}; // result significand
    assign fR = sqrt_mR[23:1]; // removing leading 1
    assign sqrt_round = sqrt_mR[0]; // round bit
    assign sqrt_expFrac = fR;
    // Connect to Shared Rounding Adder
    assign sqrt_ra_X = {8'd0, sqrt_expFrac}; 
    // Get result from Shared Rounding Adder
    assign fRrnd = ra_R[22:0]; // rounding sqrt never changes exponents (handled in shared adder) 
    assign Rn2 = {eRn1, fRrnd};
    // sign and exception processing

    assign sqrt_R = {operandX[31], Rn2};


    // =================================================================================
    // Shared Add/Sub Logic (Steps 0 to 13)
    // - Used by Divider (Iterative Steps) and Sqrt (Iterative Steps)
    // - Mapping:
    //   Shared Step 0  <-> Div Step 1  | Sqrt Step 24
    //   Shared Step 1  <-> Div Step 2  | Sqrt Step 23
    //   ...
    //   Shared Step 13 <-> Div Step 14 | Sqrt Step 11
    // =================================================================================

    // Step 0
    assign shared_as_x0 = (opcode[0] == 1'b1) ? {1'b0, betaw1} : T23s_h; // only use 1 bit of opcode
    assign shared_as_y0 = (opcode[0] == 1'b1) ? {1'b0, absq1D} : U23;
    assign shared_as_sub0 = (opcode[0] == 1'b1) ? ~q1[2] : d23;
    
    assign sub_mask0 = {28{shared_as_sub0}};
    assign y_xor0 = shared_as_y0 ^ sub_mask0;
    assign cin_vec0 = {27'd0, shared_as_sub0};
    assign shared_as_r0 = shared_as_x0 + y_xor0 + cin_vec0;

    // Step 1
    assign shared_as_x1 = (opcode[0] == 1'b1) ? betaw2 : T22s_h;
    assign shared_as_y1 = (opcode[0] == 1'b1) ? absq2D : U22;
    assign shared_as_sub1 = (opcode[0] == 1'b1) ? ~q2[2] : d22;
    
    assign shared_as_r1 = (shared_as_sub1 == 1'b1) ? (shared_as_x1 - shared_as_y1) : (shared_as_x1 + shared_as_y1);

    // Step 2
    assign shared_as_x2 = (opcode[0] == 1'b1) ? betaw3 : {1'b0, T21s_h};
    assign shared_as_y2 = (opcode[0] == 1'b1) ? absq3D : {1'b0, U21};
    assign shared_as_sub2 = (opcode[0] == 1'b1) ? ~q3[2] : d21;
    
    assign sub_mask2 = {27{shared_as_sub2}}; // 26 downto 0 is 27 bits
    assign y_xor2 = shared_as_y2 ^ sub_mask2;
    assign cin_vec2 = {26'd0, shared_as_sub2};
    assign shared_as_r2 = shared_as_x2 + y_xor2 + cin_vec2;

    // Step 3
    assign shared_as_x3 = (opcode[0] == 1'b1) ? betaw4 : {2'b00, T20s_h};
    assign shared_as_y3 = (opcode[0] == 1'b1) ? absq4D : {2'b00, U20};
    assign shared_as_sub3 = (opcode[0] == 1'b1) ? ~q4[2] : d20;
    
    assign sub_mask3 = {27{shared_as_sub3}};
    assign y_xor3 = shared_as_y3 ^ sub_mask3;
    assign cin_vec3 = {26'd0, shared_as_sub3};
    assign shared_as_r3 = shared_as_x3 + y_xor3 + cin_vec3;

    // Step 4
    assign shared_as_x4 = (opcode[0] == 1'b1) ? betaw5 : {3'b000, T19s_h};
    assign shared_as_y4 = (opcode[0] == 1'b1) ? absq5D : {3'b000, U19};
    assign shared_as_sub4 = (opcode[0] == 1'b1) ? ~q5[2] : d19;
    
    assign sub_mask4 = {27{shared_as_sub4}};
    assign y_xor4 = shared_as_y4 ^ sub_mask4;
    assign cin_vec4 = {26'd0, shared_as_sub4};
    assign shared_as_r4 = shared_as_x4 + y_xor4 + cin_vec4;

    // Step 5
    assign shared_as_x5 = (opcode[0] == 1'b1) ? betaw6 : {4'd0, T18s_h};
    assign shared_as_y5 = (opcode[0] == 1'b1) ? absq6D : {4'd0, U18};
    assign shared_as_sub5 = (opcode[0] == 1'b1) ? ~q6[2] : d18;
    
    assign shared_as_r5 = (shared_as_sub5 == 1'b1) ? (shared_as_x5 - shared_as_y5) : (shared_as_x5 + shared_as_y5);

    // Step 6
    assign shared_as_x6 = (opcode[0] == 1'b1) ? betaw7 : {5'd0, T17s_h};
    assign shared_as_y6 = (opcode[0] == 1'b1) ? absq7D : {5'd0, U17};
    assign shared_as_sub6 = (opcode[0] == 1'b1) ? ~q7[2] : d17;
    
    assign shared_as_r6 = (shared_as_sub6 == 1'b1) ? (shared_as_x6 - shared_as_y6) : (shared_as_x6 + shared_as_y6);

    // Step 7
    assign shared_as_x7 = (opcode[0] == 1'b1) ? betaw8 : {6'd0, T16s_h};
    assign shared_as_y7 = (opcode[0] == 1'b1) ? absq8D : {6'd0, U16};
    assign shared_as_sub7 = (opcode[0] == 1'b1) ? ~q8[2] : d16;
    
    assign shared_as_r7 = (shared_as_sub7 == 1'b1) ? (shared_as_x7 - shared_as_y7) : (shared_as_x7 + shared_as_y7);

    // Step 8
    assign shared_as_x8 = (opcode[0] == 1'b1) ? betaw9 : {7'd0, T15s_h};
    assign shared_as_y8 = (opcode[0] == 1'b1) ? absq9D : {7'd0, U15};
    assign shared_as_sub8 = (opcode[0] == 1'b1) ? ~q9[2] : d15;
    
    assign shared_as_r8 = (shared_as_sub8 == 1'b1) ? (shared_as_x8 - shared_as_y8) : (shared_as_x8 + shared_as_y8);

    // Step 9
    assign shared_as_x9 = (opcode[0] == 1'b1) ? betaw10 : {8'd0, T14s_h};
    assign shared_as_y9 = (opcode[0] == 1'b1) ? absq10D : {8'd0, U14};
    assign shared_as_sub9 = (opcode[0] == 1'b1) ? ~q10[2] : d14;
    
    assign shared_as_r9 = (shared_as_sub9 == 1'b1) ? (shared_as_x9 - shared_as_y9) : (shared_as_x9 + shared_as_y9);

    // Step 10
    assign shared_as_x10 = (opcode[0] == 1'b1) ? betaw11 : {9'd0, T13s_h};
    assign shared_as_y10 = (opcode[0] == 1'b1) ? absq11D : {9'd0, U13};
    assign shared_as_sub10 = (opcode[0] == 1'b1) ? ~q11[2] : d13;
    
    assign shared_as_r10 = (shared_as_sub10 == 1'b1) ? (shared_as_x10 - shared_as_y10) : (shared_as_x10 + shared_as_y10);

    // Step 11
    assign shared_as_x11 = (opcode[0] == 1'b1) ? betaw12 : {10'd0, T12s_h};
    assign shared_as_y11 = (opcode[0] == 1'b1) ? absq12D : {10'd0, U12};
    assign shared_as_sub11 = (opcode[0] == 1'b1) ? ~q12[2] : d12;
    
    assign shared_as_r11 = (shared_as_sub11 == 1'b1) ? (shared_as_x11 - shared_as_y11) : (shared_as_x11 + shared_as_y11);

    // Step 12
    assign shared_as_x12 = (opcode[0] == 1'b1) ? betaw13 : {11'd0, T11s_h};
    assign shared_as_y12 = (opcode[0] == 1'b1) ? absq13D : {11'd0, U11};
    assign shared_as_sub12 = (opcode[0] == 1'b1) ? ~q13[2] : d11;
    
    assign shared_as_r12 = (shared_as_sub12 == 1'b1) ? (shared_as_x12 - shared_as_y12) : (shared_as_x12 + shared_as_y12);

    // Step 13
    assign shared_as_x13 = (opcode[0] == 1'b1) ? betaw14 : {12'd0, T10s_h};
    assign shared_as_y13 = (opcode[0] == 1'b1) ? absq14D : {12'd0, U10};
    assign shared_as_sub13 = (opcode[0] == 1'b1) ? ~q14[2] : d10;
    
    assign sub_mask13 = {27{shared_as_sub13}};
    assign y_xor13 = shared_as_y13 ^ sub_mask13;
    assign cin_vec13 = {26'd0, shared_as_sub13};
    assign shared_as_r13 = shared_as_x13 + y_xor13 + cin_vec13;


    // =================================================================================
    // Shared Resources & Output Mux
    // =================================================================================

    // Multiplex inputs to Shared Rounding Adder
    // opcode: 00=Add, 01=Mul, 10=Sqrt, 11=Div
    always_comb begin
        unique case (opcode)
            2'b00: begin
                ra_X   = add_ra_X;
                ra_Cin = add_round;
            end
            2'b01: begin
                ra_X   = mul_ra_X;
                ra_Cin = mul_round;
            end
            2'b11: begin
                ra_X   = div_ra_X;
                ra_Cin = div_round;
            end
            2'b10: begin
                ra_X   = sqrt_ra_X;
                ra_Cin = sqrt_round;
            end
            default: begin
                ra_X   = 'x;
                ra_Cin = 'x;
            end
        endcase
    end
    assign ra_R = ra_X + ra_Cin;
    // Multiplex inputs to Shared IntAdder_27
    assign ia27_X[26:9] = add_fracAdder_X[26:9];
    assign ia27_X[8:0] = (opcode == 2'b00) ? add_fracAdder_X[8:0] : {1'b0, mul_expAdder_X};
    assign ia27_Y[26:9] = add_fracAdder_Y[26:9];
    assign ia27_Y[8:0] = (opcode == 2'b00) ? add_fracAdder_Y[8:0] : {1'b0, mul_expAdder_Y};
    assign ia27_Cin = (opcode == 2'b00) ? add_fracAdder_Cin : mul_expAdder_Cin;
    assign add_fracAdder_R = ia27_R;
    assign mul_expAdder_R = ia27_R[8:0];
    assign ia27_R = ia27_X + ia27_Y + {{26{1'b0}}, ia27_Cin};

    always_comb begin
        unique case (opcode)
            2'b00: result = add_R;
            2'b01: result = mul_R;
            2'b10: result = sqrt_R;
            2'b11: result = div_R;
            default: result = 'x;
        endcase
    end


endmodule : Fpu4OpsComb
