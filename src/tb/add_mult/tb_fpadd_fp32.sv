`timescale 1ns/1ps
import FpuPkg::*;

module tb_fpadd_fp32;

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

  // "safe" f32 (normal, mid exponent range)
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
  // Reference model (ADD only)
  // -----------------------------
  function automatic logic [31:0] ref_add_fp32(input logic [31:0] x, input logic [31:0] y);
    shortreal sx, sy, sr;
    begin
      sx = $bitstoshortreal(x);
      sy = $bitstoshortreal(y);
      sr = sx + sy;
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
      opcode = FOP_ADD;
      X = x;
      Y = y;

      repeat (LAT) @(posedge clk);

      expR = ref_add_fp32(x, y);

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
          expR = ref_add_fp32(x, y);

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
    opcode = FOP_ADD;
    X = '0; Y = '0;
    // -----------------------------
    // Boundary & Random tests
    // -----------------------------
    $display("Running boundary test (X=1.0, Y=-(1.0+eps))...");
    run_one(32'h3F80_0000, 32'hBF80_0001, "boundary_fp32"); // for abs_comparator. cin_hi
    // -----------------------------------------------------------------
    // 丸めと指数部伝搬の特定ケース
    // -----------------------------------------------------------------

    // 1. Exponent Propagation (仮数部全1への繰り上がり)
    // A = 1.111...11 * 2^0  (0x3F7F_FFFF)
    // B = 微小値。加算により丸めが発生し、結果が 1.0 * 2^1 (0x4000_0000) になるケース
    $display("Test: Exponent Propagation (1.11...1 + small_delta)...");
    run_one(32'h3F7F_FFFF, 32'h3400_0000, "exp_prop"); 

    // 2. GRS = 100 (Tie to Even) 
    // IEEE 754 の Round to Nearest, Ties to Even を検証
    // 内部的に LSB=0, G=1, R=0, S=0 となるパターン

    // CASE A: LSB=0 且つ GRS=100 -> 「偶数」である0の方へ丸める（切り捨て）
    // A = 1.0...00 * 2^0 (0x3F80_0000)
    // B = (1.0...00 * 2^-24) -> GRS=100 を狙う
    $display("Test: GRS=100, LSB=0 (Round Down to Even)...");
    run_one(32'h3F80_0000, 32'h3380_0000, "grs_100_lsb0");

    // CASE B: LSB=1 且つ GRS=100 -> 「偶数」である次の方へ丸める（切り上げ）
    // A = 1.0...01 * 2^0 (0x3F80_0001)
    $display("Test: GRS=100, LSB=1 (Round Up to Even)...");
    run_one(32'h3F80_0001, 32'h3380_0000, "grs_100_lsb1");

    // 3. GRS = 101 (Always Round Up)
    // G=1 且つ (R|S)=1 のため、LSBに関わらず常に切り上げ
    $display("Test: GRS=101 (Round Up)...");
    run_one(32'h3F80_0000, 32'h33A0_0000, "grs_101");

    // 4. Catastrophic Cancellation (近接値の減算)
    // 指数部が大きく動き、Normalizer の挙動を検証
    $display("Test: Catastrophic Cancellation...");
    run_one(32'h3F80_0001, 32'hBF80_0000, "cancellation");
    run_random_normal_only(N_RANDOM);

    $display("PASS: fp32 ADD normal-only tests completed");
    $display("SUMMARY: pass=%0d mismatch=%0d", pass_count, mismatch_count);
    $finish;
  end

endmodule
