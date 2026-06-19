`timescale 1ns/1ps

// =============================================================================
// FpuPkg
// -----------------------------------------------------------------------------
// Central package for the mixed-precision FPU.
// Defines common types, enums and constants shared by every RTL module.
// =============================================================================
package FpuPkg;

    // Common widths
    localparam int FP32_WIDTH      = 32;
    localparam int FP32_EXP_WIDTH  = 8;
    localparam int FP32_FRAC_WIDTH = 23;
    localparam int FP32_BIAS       = 127;

    localparam int FP16_WIDTH      = 16;
    localparam int FP16_EXP_WIDTH  = 5;
    localparam int FP16_FRAC_WIDTH = 10;

    localparam int BF16_WIDTH      = 16;
    localparam int BF16_EXP_WIDTH  = 8;
    localparam int BF16_FRAC_WIDTH = 7;

    // FP8: E4M3
    localparam int FP8_WIDTH       = 8;
    localparam int FP8_EXP_WIDTH  = 4;
    localparam int FP8_FRAC_WIDTH = 3;

    // Floating-point format selector
    typedef enum logic [1:0] {
        FMT_FP32 = 2'b00,
        FMT_BF16 = 2'b01,
        FMT_FP8  = 2'b10
    } FpFmt_e;

    // Operation selector
    typedef enum logic [1:0] {
        FOP_ADD  = 2'b00,
        FOP_MUL  = 2'b01,
        FOP_SQRT = 2'b10,
        FOP_DIV  = 2'b11
    } FpOp_e;

    // FP8 view
    typedef union packed {
        logic [7:0] raw;
        struct packed {
            logic       sign;
            logic [3:0] exp;
            logic [2:0] frac;
        } FP8;
    } Fp8_u;

    // BF16 view
    typedef union packed {
        logic [15:0] raw;
        struct packed {
            logic       sign;
            logic [7:0] exp;
            logic [6:0] frac;
        } bf16;
    } Bf16_u;

    // 32-bit vector with FP32 / dual-FP16x2 views
    typedef union packed {
        logic [31:0]  raw;
        struct packed {
            logic [7:0] lane3;
            logic [7:0] lane2;
            logic [7:0] lane1;
            logic [7:0] lane0;
        } fp8x4;

        struct packed {
            logic [15:0] hi;
            logic [15:0] lo;
        } bf16x2;

        struct packed {
            logic        sign;
            logic [7:0]  exp;
            logic [22:0] frac;
        } fp32;
    } FpVec_u;

`ifndef SYNTHESIS
    function automatic string disp_36(input logic [35:0] v);
        string s;
        int i;
        begin
            s = "";
            for (i = 35; i >= 0; i--) begin
                s = {s, v[i] ? "1" : "0"};
                if (i % 4 == 0 && i != 0)
                    s = {s, "_"};
            end
            return s;
        end
    endfunction

    function automatic string disp_32(input logic [31:0] v);
        string s;
        int i;
        begin
            s = "";
            for (i = 31; i >= 0; i--) begin
                s = {s, v[i] ? "1" : "0"};
                if (i % 4 == 0 && i != 0)
                    s = {s, "_"};
            end
            return s;
        end
    endfunction
`endif

endpackage : FpuPkg
