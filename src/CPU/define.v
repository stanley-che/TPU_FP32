`define R_TYPE(op) ((op)==5'b01100)
`define I_ARTH(op) ((op)==5'b00100)
`define I_LOAD(op) ((op)==5'b00000)
`define I_JALR(op) ((op)==5'b11001)
`define I_TYPE(op) (`I_ARTH(op)||`I_LOAD(op)||`I_JALR(op))
`define S_TYPE(op) ((op)==5'b01000)
`define B_TYPE(op) ((op)==5'b11000)
`define LUI(op) ((op)==5'b01101)
`define AUIPC(op) ((op)==5'b00101)
`define U_TYPE(op) (`LUI(op)||`AUIPC(op))
`define J_TYPE(op) ((op)==5'b11011)

`define ADD_SUB(f3) ((f3)==3'b000)
`define SLL(f3) ((f3)==3'b001)
`define SLT(f3) ((f3)==3'b010)
`define SLTU(f3) ((f3)==3'b011)
`define XOR(f3) ((f3)==3'b100)
`define SRL_SRA(f3) ((f3)==3'b101)
`define OR(f3) ((f3)==3'b110)
`define AND(f3) ((f3)==3'b111)
`define BEQ(f3) ((f3)==3'b000)
`define BNE(f3) ((f3)==3'b001)
`define BLT(f3) ((f3)==3'b100)
`define BGE(f3) ((f3)==3'b101)
`define BLTU(f3) ((f3)==3'b110)
`define BGEU(f3) ((f3)==3'b111)

`define _R_TYPE 5'b01100
`define _I_ARTH 5'b00100
`define _I_LOAD 5'b00000
`define _I_JALR 5'b11001
`define _I_TYPE `_I_ARTH, `_I_LOAD, `_I_JALR
`define _S_TYPE 5'b01000
`define _B_TYPE 5'b11000
`define _LUI 5'b01101
`define _AUIPC 5'b00101
`define _U_TYPE `_LUI, `_AUIPC
`define _J_TYPE 5'b11011

`define _ADD_SUB 3'b000
`define _SLL 3'b001
`define _SLT 3'b010
`define _SLTU 3'b011
`define _XOR 3'b100
`define _SRL_SRA 3'b101
`define _OR 3'b110
`define _AND 3'b111
`define _BEQ 3'b000
`define _BNE 3'b001
`define _BLT 3'b100
`define _BGE 3'b101
`define _BLTU 3'b110
`define _BGEU 3'b111
