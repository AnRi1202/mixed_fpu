`timescale 1ns/1ps
import FpuPkg::*;

module AddMulOnlyRet #(
    parameter int NUM_PIPE_STAGES = 1
)(
    input logic clk,
    input FpOp_e opcode,
    input FpFmt_e fmt,
    input logic [31:0] operandX,
    input logic [31:0] operandY,
    output logic [31:0] result
);

    logic [31:0] R_inner;
    AddMulOnly inner (
        .clk(clk),
        .opcode(opcode),
        .fmt(fmt),
        .operandX(operandX),
        .operandY(operandY),
        .result(R_inner)
    );

    // Pipeline stages for retiming
    generate
        if (NUM_PIPE_STAGES == 0) begin : gen_no_pipe
            assign result = R_inner;
        end else begin : gen_pipe
            logic [31:0] R_pipe [0:NUM_PIPE_STAGES-1];
            always_ff @(posedge clk) begin
                R_pipe[0] <= R_inner;
                for (int i = 1; i < NUM_PIPE_STAGES; i++) begin
                    R_pipe[i] <= R_pipe[i-1];
                end
            end
            assign result = R_pipe[NUM_PIPE_STAGES-1];
        end
    endgenerate

endmodule : AddMulOnlyRet
