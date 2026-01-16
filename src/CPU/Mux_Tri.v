module Mux_Tri (
    input [31:0] in_00,
    input [31:0] in_01,
    input [31:0] in_10,
    input [1:0] sel,
    output reg [31:0] out
);

  always @(*) begin
    case (sel)
      2'b00: out <= in_00;
      2'b01: out <= in_01;
      2'b10: out <= in_10;
    endcase
  end
  //assign out = sel[1] ? in_10 : (sel[0] ? in_01 : in_00);

endmodule
