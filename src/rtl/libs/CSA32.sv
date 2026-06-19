module FullAdder (
    input logic a,
    input logic b,
    input logic cin,
    output logic sum,
    output logic cout
);
    assign sum = a ^ b ^ cin;
    assign cout = (a & b) | ((a ^ b) & cin);
endmodule


module CSA32 #(
    parameter int N = 3,
    parameter int WIDTH_O = N + 2;
)(
    input logic [N-1:0] a, 
    input logic [N-1:0] b, 
    input logic [N-1:0] c, 
    output logic [WIDTH-1:0] sum,
    output logic [WIDTH-1:0] carry
);
    logic [N-1:0] sum_int;
    logic [N-1:0] carry_int;

    for (genvar i = 0; i < N; i++) begin : g_compress_3_2
        FullAdder FA(
            .a  (a[i]),
            .b  (b[i]),
            .cin  (c[i]),
            .sum  (sum_int[i]),
            .cout (carry_int[i])  
        );
    end

    assign sum = WIDTH_O'(sum_int);
    assign carry = WIDTH_O'({1'b0, carry_int, 1'b0}); 

endmodule

