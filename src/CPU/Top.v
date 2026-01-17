`include "./src/CPU/ALU.v"
`include "./src/CPU/Adder.v"
`include "./src/CPU/Controller.v"
`include "./src/CPU/Decoder.v"
`include "./src/CPU/Imm_Ext.v"
`include "./src/CPU/JB_Unit.v"
`include "./src/CPU/LD_Filter.v"
`include "./src/CPU/Mux.v"
`include "./src/CPU/Mux_Tri.v"
`include "./src/CPU/Reg_D.v"
`include "./src/CPU/Reg_E.v"
`include "./src/CPU/Reg_File.v"
`include "./src/CPU/Reg_M.v"
`include "./src/CPU/Reg_PC.v"
`include "./src/CPU/Reg_W.v"
`include "./src/CPU/SRAM.v"
`include "./src/CPU/define.v"

module Top (
    input clk,
    input rst
);

  // Reg_PC
  wire noneed;

  // add delay to rst
  reg  rst_reg;
  wire rst_in;

  always @(posedge clk) begin
    rst_reg <= rst;
  end
  assign rst_in = rst_reg;

  Controller u_Controller (
      .clk           (clk),
      .rst           (rst_in),
      .D_op          (u_Decoder.opcode),
      .D_f3          (u_Decoder.func3),
      .D_f7          (u_Decoder.func7),
      .D_rs1         (u_Decoder.rs1_index),
      .D_rs2         (u_Decoder.rs2_index),
      .D_rd          (u_Decoder.rd_index),
      .E_alu0        (u_ALU.out[0]),
      .stall         (),
      .next_pc_sel   (),
      .F_im_w_en     (u_SRAM_im.w_en),
      .D_rs1_data_sel(u_Mux_D_rs1.sel),
      .D_rs2_data_sel(u_Mux_D_rs2.sel),
      .E_rs1_data_sel(u_Mux_E_rs1.sel),
      .E_rs2_data_sel(u_Mux_E_rs2.sel),
      .E_jb_op1_sel  (u_Mux_jb_op1.sel),
      .E_alu_op1_sel (u_Mux_alu_op1.sel),
      .E_alu_op2_sel (u_Mux_alu_op2.sel),
      .E_op          (u_ALU.opcode),
      .E_f3          (u_ALU.func3),
      .E_f7          (u_ALU.func7),
      .M_dm_w_en     (u_SRAM_dm.w_en),
      .W_wb_data_sel (u_Mux_wb.sel),
      .W_wb_en       (u_Reg_File.wb_en)
  );

  Adder u_adder_pc (
      .x   (u_Reg_PC.current_pc),
      .y   (32'd4),
      .cin (1'b0),
      .s   (u_Mux_next_pc.in_1),
      .cout(noneed)
  );

  Mux u_Mux_next_pc (
      .in_0(u_JB_Unit.out),
      .in_1(u_adder_pc.s),
      .sel (u_Controller.next_pc_sel),
      .out (u_Reg_PC.next_pc)
  );

  Reg_PC u_Reg_PC (
      .clk       (clk),
      .rst       (rst_in),
      .stall     (u_Controller.stall),
      .next_pc   (u_Mux_next_pc.out),
      .current_pc()
  );

  SRAM u_SRAM_im (
      .clk       (clk),
      .w_en      (),
      .address   (u_Reg_PC.current_pc[15:0]),
      .write_data(u_Mux_wb.out),
      .read_data (u_Reg_D.inst)
  );

  Reg_D u_Reg_D (
      .clk     (clk),
      .rst     (rst_in),
      .stall   (u_Controller.stall),
      .jb      (u_Controller.next_pc_sel),
      .pc      (u_Reg_PC.current_pc),
      .inst    (),
      .pc_out  (u_Reg_E.pc),
      .inst_out(u_Imm_Ext.inst)
  );

  Decoder u_Decoder (
      .inst     (u_Reg_D.inst_out),
      .opcode   (u_Controller.D_op),
      .func3    (u_Controller.D_f3),
      .func7    (u_Controller.D_f7),
      .rs1_index(u_Reg_File.rs1_index),
      .rs2_index(u_Reg_File.rs2_index),
      .rd_index (u_Reg_E.rd_index)
  );

  Imm_Ext u_Imm_Ext (
      .inst       (u_Reg_D.inst_out),
      .imm_ext_out(u_Reg_E.sext_imm)
  );

  Reg_File u_Reg_File (
      .clk         (clk),
      .wb_en       (u_Controller.W_wb_en),
      .wb_data     (u_Mux_wb.out),
      .rd_index    (u_Reg_W.rd_index_out),
      .rs1_index   (u_Decoder.rs1_index),
      .rs2_index   (u_Decoder.rs2_index),
      .rs1_data_out(u_Mux_D_rs1.in_0),
      .rs2_data_out(u_Mux_D_rs2.in_0)
  );

  Mux u_Mux_D_rs1 (
      .in_0(u_Reg_File.rs1_data_out),
      .in_1(u_Mux_wb.out),
      .sel (),
      .out (u_Reg_E.rs1_data)
  );
  Mux u_Mux_D_rs2 (
      .in_0(u_Reg_File.rs2_data_out),
      .in_1(u_Mux_wb.out),
      .sel (),
      .out (u_Reg_E.rs2_data)
  );

  Reg_E u_Reg_E (
      .clk         (clk),
      .rst         (rst_in),
      .stall       (u_Controller.stall),
      .jb          (u_Controller.next_pc_sel),
      .pc          (u_Reg_D.pc_out),
      .rs1_data    (),
      .rs2_data    (),
      .rd_index    (u_Decoder.rd_index),
      .sext_imm    (u_Imm_Ext.imm_ext_out),
      .pc_out      (),
      .rs1_data_out(u_Mux_E_rs1.in_10),
      .rs2_data_out(u_Mux_E_rs2.in_10),
      .rd_index_out(u_Reg_M.rd_index),
      .sext_imm_out()
  );

  Mux_Tri u_Mux_E_rs1 (
      .in_00(u_Mux_wb.out),
      .in_01(u_Reg_M.alu_out),
      .in_10(u_Reg_E.rs1_data_out),
      .sel  (),
      .out  ()
  );

  Mux_Tri u_Mux_E_rs2 (
      .in_00(u_Mux_wb.out),
      .in_01(u_Reg_M.alu_out),
      .in_10(u_Reg_E.rs2_data_out),
      .sel  (),
      .out  ()
  );

  Mux u_Mux_alu_op1 (
      .in_0(u_Mux_E_rs1.out),
      .in_1(u_Reg_E.pc_out),
      .sel (u_Controller.E_alu_op1_sel),
      .out (u_ALU.op1)
  );

  Mux u_Mux_alu_op2 (
      .in_0(u_Mux_E_rs2.out),
      .in_1(u_Reg_E.sext_imm_out),
      .sel (u_Controller.E_alu_op2_sel),
      .out (u_ALU.op2)
  );

  Mux u_Mux_jb_op1 (
      .in_0(u_Mux_E_rs1.out),
      .in_1(u_Reg_E.pc_out),
      .sel (u_Controller.E_jb_op1_sel),
      .out (u_JB_Unit.op1)
  );

  ALU u_ALU (
      .opcode(u_Controller.E_op),
      .func3 (u_Controller.E_f3),
      .func7 (u_Controller.E_f7),
      .op1   (u_Mux_alu_op1.out),
      .op2   (u_Mux_alu_op2.out),
      .out   (u_Reg_M.alu)
  );

  JB_Unit u_JB_Unit (
      .op1(),
      .op2(u_Reg_E.sext_imm_out),
      .out(u_Mux_next_pc.in_0)
  );

  Reg_M u_Reg_M (
      .clk         (clk),
      .rst         (rst_in),
      .alu         (u_ALU.out),
      .rs2_data    (u_Mux_E_rs2.out),
      .rd_index    (u_Reg_E.rd_index_out),
      .alu_out     (u_Reg_W.alu),
      .rs2_data_out(u_SRAM_dm.write_data),
      .rd_index_out(u_Reg_W.rd_index)
  );

  SRAM u_SRAM_dm (
      .clk       (clk),
      .w_en      (u_Controller.M_dm_w_en),
      .address   (u_Reg_M.alu_out[15:0]),
      .write_data(u_Reg_M.rs2_data_out),
      .read_data (u_Reg_W.ld_data)
  );

  Reg_W u_Reg_W (
      .clk         (clk),
      .rst         (rst_in),
      .alu         (u_Reg_M.alu_out),
      .ld_data     (),
      .rd_index    (u_Reg_M.rd_index_out),
      .alu_out     (u_Mux_wb.in_1),
      .ld_data_out (u_LD_Filter.ld_data),
      .rd_index_out(u_Reg_File.rd_index)
  );

  LD_Filter u_LD_Filter (
      .func3    (u_Controller.W_f3),
      .ld_data  (u_Reg_W.ld_data_out),
      .ld_data_f(u_Mux_wb.in_0)
  );

  Mux u_Mux_wb (
      .in_0(u_LD_Filter.ld_data_f),
      .in_1(u_Reg_W.alu_out),
      .sel (u_Controller.W_wb_data_sel),
      .out (u_Reg_File.wb_data)
  );


endmodule
