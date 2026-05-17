


package fp_pkg;

  localparam  int DATA_W  = 24;
  localparam  int COUNT_W = $clog2(DATA_W+1);
  localparam int SHIFT_W = $clog2(DATA_W + 1);

  typedef logic [DATA_W-1:0]  data_t;
  typedef logic [DATA_W:0] wide_t;
  typedef logic [COUNT_W-1:0] count_t;
  typedef logic [SHIFT_W-1:0] shift_t;

  typedef struct packed {
    logic         sign;
    logic [7:0]   exp;
    logic [22:0]  man;
  } fp32_t;

  typedef struct packed {
    logic       sign;
    logic [4:0] exp;
    logic [9:0] man;
  } fp16_t;

  typedef struct packed {
    logic       sign;
    logic [7:0] exp;
    logic [6:0] man;
  } bf16_t;


  typedef union packed {
    fp32_t        fp_32;
    fp16_t  [1:0] fp_16;
    bf16_t  [1:0] bf_16;
  } fp_fmt_t;



  typedef struct packed {
    data_t  sum;
    logic   carry;
  } add_sub_res_t;

  typedef struct packed {
    data_t  sum;
    data_t  carry;
  } csa_res_t;

  typedef struct packed {
    count_t count;
    logic   is_zero;
  } lzc_res_t;



  function automatic add_sub_res_t add_sub (
    input data_t  data_a,
    input data_t  data_b,
    input logic   sub,
    input logic   carry
  );



    data_t  b_eff;
    logic   cin_eff;
    logic [DATA_W:0]  wide;

    b_eff = sub ? ~data_b : data_b;
    cin_eff = sub ? ~carry : carry;

    wide = data_a + b_eff + wide_t'(cin_eff);

    add_sub.sum = wide[DATA_W-1:0];
    add_sub.carry = wide[DATA_W];
  endfunction


  function automatic csa_res_t csa (
    input data_t  data_a,
    input data_t  data_b,
    input data_t  carry
  );
    csa.sum = data_a ^ data_b ^ carry;
    csa.carry = (data_a & data_b) | (data_a & carry) | (data_b & carry);

  endfunction




  function automatic lzc_res_t lzc (input data_t  data);
    lzc_res_t res;
    int zeros;

    res.is_zero = (data == 'b0);

    if (res.is_zero) begin
      res.count = COUNT_W'(DATA_W);
    end else begin
      zeros = 0;
      //
      for (int i = DATA_W-1; i >= 0; i--) begin
        if (data[i] == 1'b0) begin
          zeros++;
        end else begin
          break;
        end
      end
      res.count = COUNT_W'(zeros);
    end
    return res;
  endfunction

  function automatic logic round_rne (
    input logic lsb,
    input logic guard,
    input logic sticky
  );

    round_rne = guard & (sticky | lsb);

  endfunction


  function automatic data_t rshift_sticky (
    input data_t  data,
    input shift_t shift_amount
  );
    data_t  shr;
    logic   sticky;

    unique case (1'b1)
      // condition 1
      (shift_amount == 'b0): begin
        shr = data;
        sticky = 1'b0;
      end
      // condition 2
      (shift_amount >= SHIFT_W'(DATA_W)): begin
        shr = 'b0;
        sticky = | data;
      end
      // condition 3
      default: begin
        shr = data >> shift_amount;
        sticky = |(data & (data_t'(1) << shift_amount) -1'b1);
      end
    endcase


    return shr | data_t'(sticky);



  endfunction



endpackage


package test_pkg;
  virtual class utils #(parameter int DATA_W = 32);
    typedef logic [DATA_W-1:0]  data_t;
    typedef struct packed {
      logic   v;
      logic   s;
      data_t  diff;
      logic   bout;
    } sub_res_t;

    static function automatic sub_res_t sub_signed (
      input data_t  a,
      input data_t  b,
      input logic   bin,
      input logic   is_msb_uint
    );
      data_t  full_sub;

      full_sub = a - b - bin;
      sub_signed.diff = full_sub[DATA_W-1:0];
      sub_signed.bout = full_sub[DATA_W];
      sub_signed.s = full_sub[DATA_W-1];

      if (is_msb_uint) begin
        sub_signed.v = (a[DATA_W-1] ^ b[DATA_W-1]) & (full_sub[DATA_W-1] ^ a[DATA_W-1]);
      end else begin
        sub_signed.v = 1'b0;
      end
    endfunction


  endclass


endpackage
