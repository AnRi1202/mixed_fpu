`timescale 1ns/1ps
import FpuPkg::*;
import fp_pkg::*;

// ============================================================================
// FP32 add wrapper
// ============================================================================
module fp32_add_wrapper (
  input   logic           i_clk,
  input   logic           i_rst_n,
  input   fp_pkg::fp32_t  i_operand_a,
  input   fp_pkg::fp32_t  i_operand_b,
  output  fp_pkg::fp32_t  o_sum
);
`ifdef FOUROPS
  Fpu4OpsComb u_dut (
    .clk      (i_clk),
    .opcode   (FOP_ADD),
    .fmt      (FMT_FP32),
    .operandX (32'(i_operand_a)),
    .operandY (32'(i_operand_b)),
    .result   (o_sum)
  );
`elsif MIXED_ADDMULT
  AddMulOnly u_dut (
    .clk      (i_clk),
    .opcode   (FOP_ADD),
    .fmt      (FMT_FP32),
    .operandX (32'(i_operand_a)),
    .operandY (32'(i_operand_b)),
    .result   (o_sum)
  );
`else // SIXOPS
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_ADD),
    .fmt      (FMT_FP32),
    .operandX (32'(i_operand_a)),
    .operandY (32'(i_operand_b)),
    .result   (o_sum)
  );
`endif
endmodule

// ============================================================================
// FP32 mult wrapper
// ============================================================================
module fp32_mult_wrapper (
  input   logic           i_clk,
  input   logic           i_rst_n,
  input   fp_pkg::fp32_t  i_a,
  input   fp_pkg::fp32_t  i_b,
  output  fp_pkg::fp32_t  o_prod
);
`ifdef FOUROPS
  Fpu4OpsComb u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_FP32),
    .operandX (32'(i_a)),
    .operandY (32'(i_b)),
    .result   (o_prod)
  );
`elsif MIXED_ADDMULT
  AddMulOnly u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_FP32),
    .operandX (32'(i_a)),
    .operandY (32'(i_b)),
    .result   (o_prod)
  );
`else // SIXOPS
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_FP32),
    .operandX (32'(i_a)),
    .operandY (32'(i_b)),
    .result   (o_prod)
  );
`endif
endmodule

// ============================================================================
// BF16 / FP16 add wrapper (16-bit lane interface)
// ============================================================================
module bf16_add_wrapper (
  input   logic           i_clk,
  input   logic           i_rst_n,
  input   fp_pkg::bf16_t  i_operand_a,
  input   fp_pkg::bf16_t  i_operand_b,
  output  fp_pkg::bf16_t  o_sum
);
  logic [FP32_WIDTH-1:0] tmpResult;
`ifdef FOUROPS
  // 4Ops is FP32-only; tie BF16 outputs to a known value.
  assign tmpResult = '0;
`elsif MIXED_ADDMULT
  AddMulOnly u_dut (
    .clk      (i_clk),
    .opcode   (FOP_ADD),
    .fmt      (FMT_BF16),
    .operandX ({16'b0, i_operand_a}),
    .operandY ({16'b0, i_operand_b}),
    .result   (tmpResult)
  );
`else // SIXOPS
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_ADD),
    .fmt      (FMT_BF16),
    .operandX ({16'b0, i_operand_a}),
    .operandY ({16'b0, i_operand_b}),
    .result   (tmpResult)
  );
`endif
  assign o_sum = tmpResult[15:0];
endmodule

// ============================================================================
// BF16 / FP16 mult wrapper (16-bit lane interface)
// ============================================================================
module bf16_mult_wrapper (
  input   logic           i_clk,
  input   logic           i_rst_n,
  input   fp_pkg::bf16_t  i_a,
  input   fp_pkg::bf16_t  i_b,
  output  fp_pkg::bf16_t  o_prod
);
  logic [FP32_WIDTH-1:0] tmpResult;
`ifdef FOUROPS
  assign tmpResult = '0;
`elsif MIXED_ADDMULT
  AddMulOnly u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_BF16),
    .operandX ({16'b0, i_a}),
    .operandY ({16'b0, i_b}),
    .result   (tmpResult)
  );
`else // SIXOPS
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_BF16),
    .operandX ({16'b0, i_a}),
    .operandY ({16'b0, i_b}),
    .result   (tmpResult)
  );
`endif
  assign o_prod = tmpResult[15:0];
endmodule

// ============================================================================
// FP8x4 add wrapper (32-bit packed interface, E4M3)
// Full 4-lane interface: lane3=[31:24], lane2=[23:16], lane1=[15:8], lane0=[7:0].
// ============================================================================
module fp8_add_wrapper (
  input   logic                  i_clk,
  input   logic                  i_rst_n,
  input   logic [FP32_WIDTH-1:0] i_operand_a,
  input   logic [FP32_WIDTH-1:0] i_operand_b,
  output  logic [FP32_WIDTH-1:0] o_sum
);
`ifdef FOUROPS
  // 4Ops is FP32-only; FP8 is unsupported.
  assign o_sum = '0;
`elsif MIXED_ADDMULT
  // mixed_addmult supports FP32/BF16 only; FP8 is unsupported.
  assign o_sum = '0;
`else // SIXOPS
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_ADD),
    .fmt      (FMT_FP8),
    .operandX (i_operand_a),
    .operandY (i_operand_b),
    .result   (o_sum)
  );
`endif
endmodule

// ============================================================================
// FP8x4 mult wrapper (32-bit packed interface, E4M3)
// Full 4-lane interface: lane3=[31:24], lane2=[23:16], lane1=[15:8], lane0=[7:0].
// Exercises the shared 25x25 multiplier packing (lanes 3 & 1) as well as the
// dedicated 4x4 multipliers (lanes 2 & 0).
// ============================================================================
module fp8x4_mult_wrapper (
  input   logic                  i_clk,
  input   logic                  i_rst_n,
  input   logic [FP32_WIDTH-1:0] i_operand_a,
  input   logic [FP32_WIDTH-1:0] i_operand_b,
  output  logic [FP32_WIDTH-1:0] o_prod
);
`ifdef FOUROPS
  assign o_prod = '0;
`elsif MIXED_ADDMULT
  assign o_prod = '0;
`else // SIXOPS / FP8X4
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_FP8),
    .operandX (i_operand_a),
    .operandY (i_operand_b),
    .result   (o_prod)
  );
`endif
endmodule

// ============================================================================
// FP8x4 mult wrapper (8-bit lane interface, E4M3)
// ============================================================================
module fp8_mult_wrapper (
  input   logic                 i_clk,
  input   logic                 i_rst_n,
  input   logic [FP8_WIDTH-1:0] i_a,
  input   logic [FP8_WIDTH-1:0] i_b,
  output  logic [FP8_WIDTH-1:0] o_prod
);
  logic [FP32_WIDTH-1:0] tmpResult;
`ifdef FOUROPS
  assign tmpResult = '0;
`elsif MIXED_ADDMULT
  assign tmpResult = '0;
`else // SIXOPS
  FpAllShared u_dut (
    .clk      (i_clk),
    .opcode   (FOP_MUL),
    .fmt      (FMT_FP8),
    .operandX ({24'b0, i_a}),
    .operandY ({24'b0, i_b}),
    .result   (tmpResult)
  );
`endif
  assign o_prod = tmpResult[7:0];
endmodule
