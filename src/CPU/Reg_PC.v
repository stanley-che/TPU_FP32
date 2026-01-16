module Reg_PC (
    input             clk,
    input             rst,
    input             stall,
    input      [31:0] next_pc,
    output reg [31:0] current_pc
);
  always @(posedge clk or posedge rst) begin
    if (rst) current_pc <= 32'd0;
    else if (stall) begin
      current_pc <= current_pc;
    end else begin
      current_pc <= next_pc;
    end
  end
endmodule
