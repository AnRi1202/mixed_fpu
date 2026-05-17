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

    // Floating-point format selector
    typedef enum logic {
        FMT_FP32 = 1'b0,
        FMT_FP16 = 1'b1
    } FpFmt_e;

    // Operation selector
    typedef enum logic [1:0] {
        FOP_ADD  = 2'b00,
        FOP_MUL  = 2'b01,
        FOP_SQRT = 2'b10,
        FOP_DIV  = 2'b11
    } FpOp_e;

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
            logic [15:0] hi;
            logic [15:0] lo;
        } lanes;
        struct packed {
            logic       sign;
            logic [7:0] exp;
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
