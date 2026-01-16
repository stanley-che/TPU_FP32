module Decoder (
    input  [31:0] inst,
    output [ 4:0] opcode,
    output [ 2:0] func3,
    output        func7,
    output [ 4:0] rs1_index,
    output [ 4:0] rs2_index,
    output [ 4:0] rd_index
);
  assign opcode = inst[6:2];
  assign func3 = inst[14:12];
  assign func7 = inst[30];
  assign rs1_index = inst[19:15];
  assign rs2_index = inst[24:20];
  assign rd_index = inst[11:7];
endmodule
