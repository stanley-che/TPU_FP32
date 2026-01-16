module Reg_D (
    input             clk,
    input             rst,
    input             stall,
    input             jb,
    input      [31:0] pc,
    input      [31:0] inst,
    output reg [31:0] pc_out,
    output reg [31:0] inst_out
);

  always @(posedge clk or posedge rst) begin
    case (1'b1)
      rst || ~jb: begin  //jb:0
        pc_out   <= 32'b0;
        inst_out <= 32'b0;
      end
      stall && jb: begin  //jb:1, stall:1
        pc_out   <= pc_out;
        inst_out <= inst_out;
      end
      default: begin  //jb:1, stall:0
        pc_out   <= pc;
        inst_out <= inst;
      end
    endcase
  end
endmodule
