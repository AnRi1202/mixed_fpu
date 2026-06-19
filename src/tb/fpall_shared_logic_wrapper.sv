`timescale 1ns/1ps
import FpuPkg::*;

// Raw bit-vector wrapper for VHDL co-simulation (used by flopoco_wrapper.vhdl
// and the SystemVerilog testbenches under src/tb/add_mult). The actual DUT is
// selected at compile time via one of the macros defined by the simulation
// Makefiles (FOUROPS / SIXOPS / MIXED_ADDMULT).
module fpall_shared_logic_wrapper(
    input  logic        clk,
    input  logic [1:0]  opcode_in, // 00:Add, 01:Mul, 10:Sqrt, 11:Div
    input  logic        fmt_in,    // 0:FMT_FP32, 1:FMT_BF16
    input  logic [31:0] X,
    input  logic [31:0] Y,
    output logic [31:0] R
);

`ifdef FOUROPS
    Fpu4OpsComb u_dut (
        .clk      (clk),
        .opcode   (FpOp_e'(opcode_in)),
        .fmt      (FpFmt_e'(fmt_in)),
        .operandX (X),
        .operandY (Y),
        .result   (R)
    );
`elsif SIXOPS
    FpAllShared u_dut (
        .clk      (clk),
        .opcode   (FpOp_e'(opcode_in)),
        .fmt      (FpFmt_e'(fmt_in)),
        .operandX (X),
        .operandY (Y),
        .result   (R)
    );
`elsif MIXED_ADDMULT
    AddMulOnly u_dut (
        .clk      (clk),
        .opcode   (FpOp_e'(opcode_in)),
        .fmt      (FpFmt_e'(fmt_in)),
        .operandX (X),
        .operandY (Y),
        .result   (R)
    );
`else
    // Trigger a compilation error if no DUT macro is defined.
    Error_No_DUT_Version_Defined_Check_Macros();
`endif

endmodule
