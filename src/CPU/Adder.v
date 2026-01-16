module Adder (
    input [31:0] x,
    input [31:0] y,
    input cin,
    output [31:0] s,
    output cout
);
  assign {cout, s} = x + y + cin;
endmodule
