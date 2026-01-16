module Reg_E (
    input             clk,
    input             rst,
    input             stall,
    input             jb,
    input      [31:0] pc,
    input      [31:0] rs1_data,
    input      [31:0] rs2_data,
    input      [ 4:0] rd_index,
    input      [31:0] sext_imm,
    output reg [31:0] pc_out,
    output reg [31:0] rs1_data_out,
    output reg [31:0] rs2_data_out,
    output reg [ 4:0] rd_index_out,
    output reg [31:0] sext_imm_out
);

  always @(posedge clk or posedge rst) begin
    if (rst || ~jb || stall) begin  //jb:0
      pc_out <= 32'b0;
      rs1_data_out <= 32'b0;
      rs2_data_out <= 32'b0;
      rd_index_out <= 5'b0;
      sext_imm_out <= 32'b0;
    end else begin  //jb:1, stall:0
      pc_out <= pc;
      rs1_data_out <= rs1_data;
      rs2_data_out <= rs2_data;
      rd_index_out <= rd_index;
      sext_imm_out <= sext_imm;
    end
  end
endmodule
