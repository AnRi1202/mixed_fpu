`timescale 1ns/1ps
import FpuPkg::*;

module tb_fpmult_fp32;

  logic     clk;
  FpFmt_e  fmt;
  FpOp_e   opcode;
  logic [31:0] X, Y;
  logic [31:0] R;

  // Adjust if your DUT has different ports
  fpall_shared_logic_wrapper dut (
    .clk(clk),
    .fmt_in(fmt),
    .opcode_in(opcode),
    .X(X),
    .Y(Y),
    .R(R)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  // -----------------------------
  // CONFIG
  // -----------------------------
  localparam int LAT      = 2;     // how many posedges until R is valid
  localparam int N_RANDOM = 4000;

  // -----------------------------
  // f32 helpers
  // -----------------------------
  function automatic bit is_nan_f32(input logic [31:0] f);
    return (&f[30:23]) && (|f[22:0]);
  endfunction

  function automatic bit is_inf_f32(input logic [31:0] f);
    return (&f[30:23]) && (~|f[22:0]);
  endfunction

  function automatic bit is_zero_or_subnormal_f32(input logic [31:0] f);
    return (f[30:23] == 8'h00);
  endfunction

  function automatic bit is_normal_f32(input logic [31:0] f);
    return (f[30:23] != 8'h00) && (f[30:23] != 8'hFF);
  endfunction

  function automatic logic [31:0] rand_f32_safe(bit allow_neg = 1);
    logic sign;
    logic [7:0] exp;
    logic [22:0] frac;
    sign = allow_neg ? $urandom_range(0,1) : 1'b0;
    exp  = $urandom_range(8'h40, 8'h7A); // middle band (avoid extremes)
    frac = $urandom();                   // take LSBs
    return {sign, exp, frac};
  endfunction

  // -----------------------------
  // Reference model (MUL only)
  // -----------------------------
  function automatic logic [31:0] ref_mul_fp32(input logic [31:0] x, input logic [31:0] y);
    shortreal sx, sy, sr;
    begin
      sx = $bitstoshortreal(x);
      sy = $bitstoshortreal(y);
      sr = sx * sy;
      return $shortrealtobits(sr);
    end
  endfunction

  // -----------------------------
  // Drive & check
  // -----------------------------
  int mismatch_count = 0;
  int pass_count = 0;

  task automatic run_one(input logic [31:0] x, input logic [31:0] y, input string tag="");
    logic [31:0] expR;
    begin
      fmt    = FMT_FP32;
      opcode = FOP_MUL;
      X = x;
      Y = y;

      repeat (LAT) @(posedge clk);

      expR = ref_mul_fp32(x, y);

      // normal-only test policy (bit-exact compare)
      if (!is_normal_f32(expR)) begin
        $fatal(1,
          "Ref produced non-normal (filtered test expected normal). tag=%s X=%h Y=%h expR=%h",
          tag, x, y, expR
        );
      end

      if (R !== expR) begin
        mismatch_count++;
        $display("Mismatch tag=%s X=%h Y=%h got=%s exp=%s", tag, x, y, disp_32(R), disp_32(expR));
      end else begin
        pass_count++;
      end
    end
  endtask

  // generate random vectors but ACCEPT ONLY when expected result is normal
  task automatic run_random_normal_only(int n);
    int unsigned i;
    int tries;
    logic [31:0] x, y, expR;
    begin
      for (i = 0; i < n; i++) begin
        tries = 0;
        while (1) begin
          tries++;
          x = rand_f32_safe(/*allow_neg=*/1);
          y = rand_f32_safe(/*allow_neg=*/1);
          expR = ref_mul_fp32(x, y);

          if (is_normal_f32(x) && is_normal_f32(y) && is_normal_f32(expR)) break;
          if (tries > 2000) $fatal(1, "Could not find normal-only vector");
        end

        run_one(x, y, $sformatf("rand[%0d]", i));
      end
    end
  endtask

  initial begin
    // init
    fmt    = FMT_FP32;
    opcode = FOP_MUL;
    X = '0; Y = '0;
    repeat (LAT) @(posedge clk);

    // -----------------------------
    // Random normal-only tests
    // -----------------------------
    run_random_normal_only(N_RANDOM);

    $display("PASS: fp32 MUL normal-only tests completed");
    $display("SUMMARY: pass=%0d mismatch=%0d", pass_count, mismatch_count);
    $finish;
  end

endmodule
