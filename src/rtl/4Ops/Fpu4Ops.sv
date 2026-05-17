`timescale 1ns/1ps
import FpuPkg::*;

// Pipelined wrapper: Fpu4OpsComb + output registers for retiming.
module Fpu4Ops #(
    parameter int NUM_PIPE_STAGES_ADD_MUL  = 1, // Add/Mul pipeline depth
    parameter int NUM_PIPE_STAGES_DIV_SQRT = 1  // Div/Sqrt pipeline depth
)(
    input  logic                   clk,
    input  FpOp_e                  opcode,
    input  FpFmt_e                 fmt,
    input  logic [FP32_WIDTH-1:0]  operandX,
    input  logic [FP32_WIDTH-1:0]  operandY,
    output logic [FP32_WIDTH-1:0]  result
);

    logic [31:0] R_inner;

    Fpu4OpsComb u_inner (
        .clk(clk),
        .opcode(opcode),
        .fmt(fmt),
        .operandX(operandX),
        .operandY(operandY),
        .result(R_inner)
    );

    // Pipeline: depth = max(AM, DS) for retiming flexibility
    localparam int PIPE_DEPTH = (NUM_PIPE_STAGES_ADD_MUL >= NUM_PIPE_STAGES_DIV_SQRT) ? NUM_PIPE_STAGES_ADD_MUL : NUM_PIPE_STAGES_DIV_SQRT;

    generate
        if (PIPE_DEPTH == 0) begin : gen_no_pipe
            assign result = R_inner;
        end else begin : gen_pipe
            logic [31:0] R_pipe [0:PIPE_DEPTH-1];
            always_ff @(posedge clk) begin
                R_pipe[0] <= R_inner;
                for (int i = 1; i < PIPE_DEPTH; i++) begin
                    R_pipe[i] <= R_pipe[i-1];
                end
            end
            assign result = R_pipe[PIPE_DEPTH-1];
        end
    endgenerate

endmodule : Fpu4Ops
