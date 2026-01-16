module Reg_W (
    input             clk,
    input             rst,
    input      [31:0] alu,
    input      [31:0] ld_data,
    input      [ 4:0] rd_index,
    output reg [31:0] alu_out,
    output reg [31:0] ld_data_out,
    output reg [ 4:0] rd_index_out
);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      alu_out <= 32'd0;
      ld_data_out <= 32'd0;
      rd_index_out <= 5'd0;
    end else begin
      alu_out <= alu;
      ld_data_out <= ld_data;
      rd_index_out <= rd_index;
    end
  end

endmodule
