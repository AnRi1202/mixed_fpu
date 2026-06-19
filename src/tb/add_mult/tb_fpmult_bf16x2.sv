`timescale 1ns/1ps
import FpuPkg::*;

module tb_fpmult_bf16x2;

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
  localparam int LAT = 2;            // how many posedges until R is valid
  localparam int N_RANDOM = 4000;

  // -----------------------------
  // bf16 helpers
  // -----------------------------
  function automatic logic [31:0] bf16_to_f32_bits(input logic [15:0] b); //16bit -> 32bit
    return {b, 16'h0000};
  endfunction

  function automatic logic [15:0] f32_bits_to_bf16_rne(input logic [31:0] f);
    logic [15:0] upper, lower;
    logic round_bit, sticky, lsb, inc;
    upper = f[31:16];
    lower = f[15:0];
    round_bit = lower[15];
    sticky    = |lower[14:0];
    lsb       = upper[0];
    inc       = round_bit & (sticky | lsb);
    return upper + inc;
  endfunction

  function automatic shortreal bf16_to_sr(input logic [15:0] b); //sr is shortreal
    return $bitstoshortreal(bf16_to_f32_bits(b));
  endfunction

  function automatic logic [15:0] sr_to_bf16(input shortreal s);
    return f32_bits_to_bf16_rne($shortrealtobits(s));
  endfunction

  function automatic bit is_nan_bf16(input logic [15:0] b);
    return (&b[14:7]) && (|b[6:0]);
  endfunction

  function automatic bit is_inf_bf16(input logic [15:0] b);
    return (&b[14:7]) && (~|b[6:0]);
  endfunction

  function automatic bit is_zero_or_subnormal_bf16(input logic [15:0] b);
    return (b[14:7] == 8'h00);
  endfunction

  function automatic bit is_normal_bf16(input logic [15:0] b);
    return (b[14:7] != 8'h00) && (b[14:7] != 8'hFF);
  endfunction

  // "safe" bf16 (normal, mid exponent range)
  function automatic logic [15:0] rand_bf16_safe(bit allow_neg = 1);
    logic sign;
    logic [7:0] exp;
    logic [6:0] frac;
    sign = allow_neg ? $urandom_range(0,1) : 1'b0;
    exp  = $urandom_range(8'h40, 8'h7A); // middle band
    frac = $urandom_range(0, 127);
    return {sign, exp, frac};
  endfunction

  function automatic logic [31:0] rand_bf16x2_safe(bit allow_neg = 1);
    return {rand_bf16_safe(allow_neg), rand_bf16_safe(allow_neg)};
  endfunction

  // -----------------------------
  // Reference model (MUL only)
  // -----------------------------
  function automatic logic [31:0] ref_mul_bf16x2(input logic [31:0] x, input logic [31:0] y);
    logic [15:0] xh, xl, yh, yl;
    shortreal sh, sl;
    xh = x[31:16]; xl = x[15:0];
    yh = y[31:16]; yl = y[15:0];
    sh = bf16_to_sr(xh) * bf16_to_sr(yh);
    sl = bf16_to_sr(xl) * bf16_to_sr(yl);
    return {sr_to_bf16(sh), sr_to_bf16(sl)};
  endfunction

  // -----------------------------
  // Drive & check
  // -----------------------------
  int mismatch_count = 0;
  int pass_count = 0;

  task automatic run_one(input logic [31:0] x, input logic [31:0] y, input string tag="");
    logic [31:0] expR;
    begin
      fmt    = FMT_BF16;
      opcode = FOP_MUL;
      X = x;
      Y = y;

      repeat (LAT) @(posedge clk);

      expR = ref_mul_bf16x2(x, y);

      // If you truly want to avoid over/under/NaN/Inf in *tests*, assert here.
      if (!(is_normal_bf16(expR[31:16]) && is_normal_bf16(expR[15:0]))) begin
        $fatal(1, "Ref produced non-normal (filtered test expected normal). tag=%s X=%h Y=%h expR=%h", tag, x, y, expR);
      end

      // Strict bit-exact compare
      if (R !== expR) begin
        mismatch_count++;
        $display("Mismatch tag=%s X=%h Y=%h got=%s exp=%s", tag, x, y, disp_32(R), disp_32(expR));
      end else begin
        pass_count++;
      end
    end
  endtask

  // generate random vectors but ACCEPT ONLY when expected result is normal on both lanes
  task automatic run_random_normal_only(int n);
    int unsigned i;
    int tries;
    logic [31:0] x, y, expR;
    begin
      for (i = 0; i < n; i++) begin
        tries = 0;
        while (1) begin
          tries++;
          x = rand_bf16x2_safe(/*allow_neg=*/1);
          y = rand_bf16x2_safe(/*allow_neg=*/1);
          expR = ref_mul_bf16x2(x, y);

          if (is_normal_bf16(expR[31:16]) && is_normal_bf16(expR[15:0])) break;
          if (tries > 2000) $fatal(1, "Could not find normal-only vector");
        end

        run_one(x, y, $sformatf("rand[%0d]", i));
      end
    end
  endtask

  initial begin
    // init
    fmt    = FMT_BF16;
    opcode = FOP_MUL;
    X = '0; Y = '0;
    repeat (LAT) @(posedge clk);
    // -----------------------------
    // Random normal-only tests
    // -----------------------------
    run_random_normal_only(N_RANDOM);

    $display("PASS: bf16x2 MUL normal-only tests completed");
    $display("SUMMARY: pass=%0d mismatch=%0d", pass_count, mismatch_count);
    $finish;
  end

endmodule
