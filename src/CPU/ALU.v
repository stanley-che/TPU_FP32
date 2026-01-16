`include "src/define.v"

module ALU (
    input      [ 4:0] opcode,
    input      [ 2:0] func3,
    input             func7,
    input      [31:0] op1,
    input      [31:0] op2,
    output reg [31:0] out
);
  always @(*) begin
    case (opcode)
      `_R_TYPE, `_I_ARTH: begin
        case (func3)
          `_ADD_SUB: begin
            if (`R_TYPE(opcode)) begin
              out <= (~func7) ? (op1 + op2) : (op1 - op2);
            end else if (`I_ARTH(opcode)) begin
              out <= op1 + op2;
            end else begin
              out <= 32'bx;
            end
          end
          `_SLL:     out <= op1 << op2[4:0];
          `_SLT:     out <= {{31{1'b0}}, ($signed(op1) < $signed(op2))};
          `_SLTU:    out <= {{31{1'b0}}, (op1 < op2)};
          `_XOR:     out <= op1 ^ op2;
          `_SRL_SRA: out <= (~func7) ? ($signed(op1) >> op2[4:0]) : ($signed(op1) >>> op2[4:0]);
          `_OR:      out <= op1 | op2;
          `_AND:     out <= op1 & op2;
          default:   out <= 32'bx;
        endcase
      end
      `_LUI:              out <= op2;
      `_AUIPC:            out <= op1 + op2;
      `_I_LOAD, `_S_TYPE: out <= op1 + op2;
      `_J_TYPE, `_I_JALR: out <= op1 + 4;  //PC=PC+4
      `_B_TYPE: begin
        out[31:1] <= 31'b0;
        case (func3)
          `_BEQ:   out[0] <= (op1 === op2);
          `_BNE:   out[0] <= (op1 !== op2);
          `_BLT:   out[0] <= ($signed(op1) < $signed(op2));
          `_BGE:   out[0] <= ($signed(op1) >= $signed(op2));
          `_BLTU:  out[0] <= (op1 < op2);
          `_BGEU:  out[0] <= (op1 >= op2);
          default: out[0] <= 1'bx;
        endcase
      end
      default:            out <= 32'bx;
    endcase
  end
endmodule
