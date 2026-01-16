
module JB_Unit (
    input  [31:0] op1,
    input  [31:0] op2,
    output [31:0] out
);
  assign out = (op1 + op2) & {{31{1'b1}}, 1'b0};
endmodule
