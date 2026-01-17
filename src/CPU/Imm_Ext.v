`include "./src/CPU/define.v"

module Imm_Ext (
    input [31:0] inst,
    output reg [31:0] imm_ext_out
);
  always @(*) begin
    case (inst[6:2])
      `_R_TYPE: imm_ext_out <= 32'b0;
      `_I_TYPE: imm_ext_out <= {{20{inst[31]}}, inst[31:20]};
      `_S_TYPE: imm_ext_out <= {{20{inst[31]}}, inst[31:25], inst[11:7]};
      `_B_TYPE: imm_ext_out <= {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
      `_U_TYPE: imm_ext_out <= {inst[31:12], 12'b0};
      `_J_TYPE: imm_ext_out <= {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
      default:  imm_ext_out <= 32'bx;
    endcase
  end
endmodule
