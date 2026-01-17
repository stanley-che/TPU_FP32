`include "./src/CPU/define.v"
module Controller (
    input            clk,
    input            rst,
    input      [4:0] D_op,
    input      [2:0] D_f3,
    input            D_f7,
    input      [4:0] D_rs1,
    input      [4:0] D_rs2,
    input      [4:0] D_rd,
    input            E_alu0,
    output           stall,
    output reg       next_pc_sel,
    output     [3:0] F_im_w_en,
    output           D_rs1_data_sel,
    output           D_rs2_data_sel,
    output     [1:0] E_rs1_data_sel,
    output     [1:0] E_rs2_data_sel,
    output reg       E_jb_op1_sel,
    output reg       E_alu_op1_sel,
    output reg       E_alu_op2_sel,
    output reg [4:0] E_op,
    output reg [2:0] E_f3,
    output reg       E_f7,
    output reg [3:0] M_dm_w_en,
    output reg       W_wb_data_sel,
    output reg       W_wb_en
);

  reg [4:0] E_rd;
  reg [4:0] E_rs1;
  reg [4:0] E_rs2;
  reg [4:0] M_op;
  reg [2:0] M_f3;
  reg [4:0] M_rd;
  reg [4:0] W_op;
  reg [2:0] W_f3;
  reg [4:0] W_rd;


  assign F_im_w_en = 4'b0;

  // pipeline registers
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      E_op  <= 5'd0;
      E_f3  <= 3'd0;
      E_f7  <= 1'd0;
      E_rs1 <= 5'd0;
      E_rs2 <= 5'd0;
      E_rd  <= 5'd0;
      M_op  <= 5'd0;
      M_f3  <= 3'd0;
      M_rd  <= 1'd0;
      W_op  <= 5'd0;
      W_f3  <= 3'd0;
      W_rd  <= 1'd0;
    end else if (stall | !next_pc_sel) begin
      E_op  <= 5'd0;
      E_f3  <= 3'd0;
      E_f7  <= 1'd0;
      E_rs1 <= 5'd0;
      E_rs2 <= 5'd0;
      E_rd  <= 5'd0;
      M_op  <= E_op;
      M_f3  <= E_f3;
      M_rd  <= E_rd;
      W_op  <= M_op;
      W_f3  <= M_f3;
      W_rd  <= M_rd;
    end else begin
      E_op  <= D_op;
      E_f3  <= D_f3;
      E_f7  <= D_f7;
      E_rs1 <= D_rs1;
      E_rs2 <= D_rs2;
      E_rd  <= D_rd;
      M_op  <= E_op;
      M_f3  <= E_f3;
      M_rd  <= E_rd;
      W_op  <= M_op;
      W_f3  <= M_f3;
      W_rd  <= M_rd;
    end
  end

  // stall
  assign is_D_use_rs1 = (`R_TYPE(D_op) || `I_TYPE(D_op) || `S_TYPE(D_op) || `B_TYPE(D_op));
  assign is_D_rs1_E_rd_overlap = is_D_use_rs1 & (D_rs1 == E_rd) & E_rd != 0;
  assign is_D_use_rs2 = (`R_TYPE(D_op) || `S_TYPE(D_op) || `B_TYPE(D_op));
  assign is_D_rs2_E_rd_overlap = is_D_use_rs2 & (D_rs2 == E_rd) & E_rd != 0;
  assign is_DE_overlap = (is_D_rs1_E_rd_overlap || is_D_rs2_E_rd_overlap);
  assign stall = (`I_LOAD(E_op)) & is_DE_overlap;

  // next_pc_sel
  always @(rst or E_op or E_alu0) begin
    if (`J_TYPE(E_op) || `I_JALR(E_op) || (`B_TYPE(E_op) && E_alu0)) begin
      next_pc_sel <= 0;
    end else begin
      next_pc_sel <= 1;  //pc=pc+4
    end
  end

  // D_rs1_data_sel
  assign is_W_use_rd = (`R_TYPE(W_op) || `I_TYPE(W_op) || `U_TYPE(W_op) || `J_TYPE(W_op));
  assign is_D_rs1_W_rd_overlap = is_D_use_rs1 & is_W_use_rd & (D_rs1 == W_rd) & W_rd != 0;
  assign D_rs1_data_sel = is_D_rs1_W_rd_overlap ? 1'd1 : 1'd0;

  // D_rs2_data_sel
  assign is_D_rs2_W_rd_overlap = is_D_use_rs2 & is_W_use_rd & (D_rs2 == W_rd) & W_rd != 0;
  assign D_rs2_data_sel = is_D_rs2_W_rd_overlap ? 1'd1 : 1'd0;

  // W_wb_en
  always @(W_op) begin
    if (
        `R_TYPE(W_op)
        ||
        `I_TYPE(W_op)
        ||
        `U_TYPE(W_op)
        ||
        `J_TYPE(W_op)
        ) begin  // consider U-type !
      W_wb_en <= 1;
    end else begin
      W_wb_en <= 0;
    end
  end

  // E_rs1_data_sel
  assign is_E_use_rs1 = (`R_TYPE(E_op) || `I_TYPE(E_op) || `S_TYPE(E_op) || `B_TYPE(E_op));
  assign is_M_use_rd = (`R_TYPE(M_op) || `I_TYPE(M_op) || `U_TYPE(M_op) || `J_TYPE(M_op));
  assign is_E_rs1_W_rd_overlap = is_E_use_rs1 & is_W_use_rd & (E_rs1 == W_rd) & W_rd != 0;
  assign is_E_rs1_M_rd_overlap = is_E_use_rs1 & is_M_use_rd & (E_rs1 == M_rd) & M_rd != 0;
  assign E_rs1_data_sel = is_E_rs1_M_rd_overlap ? 2'd1 : is_E_rs1_W_rd_overlap ? 2'd0 : 2'd2;

  // E_rs2_data_sel
  assign is_E_use_rs2 = (`R_TYPE(E_op) || `S_TYPE(E_op) || `B_TYPE(E_op));
  assign is_E_rs2_W_rd_overlap = is_E_use_rs2 & is_W_use_rd & (E_rs2 == W_rd) & W_rd != 0;
  assign is_E_rs2_M_rd_overlap = is_E_use_rs2 & is_M_use_rd & (E_rs2 == M_rd) & M_rd != 0;
  assign E_rs2_data_sel = is_E_rs2_M_rd_overlap ? 2'd1 : is_E_rs2_W_rd_overlap ? 2'd0 : 2'd2;

  // E_jb_op1_sel
  always @(E_op) begin
    if (`I_JALR(E_op)) begin
      E_jb_op1_sel <= 0;  //mux=rs1
    end else begin
      E_jb_op1_sel <= 1;  //mux=pc
    end
  end

  // E_alu_op1_sel
  always @(E_op) begin
    if (`U_TYPE(E_op) || `J_TYPE(E_op) || `I_JALR(E_op)) begin
      E_alu_op1_sel <= 1;  // op1 uses pc instead of rs1
    end else begin
      E_alu_op1_sel <= 0;
    end
  end

  // E_alu_op2_sel
  always @(E_op) begin
    if (`R_TYPE(E_op) || `B_TYPE(E_op)) begin  // consider B type!
      E_alu_op2_sel <= 0;
    end else begin
      E_alu_op2_sel <= 1;
    end
  end

  // W_wb_data_sel
  always @(W_op) begin
    if (`I_LOAD(W_op)) begin
      W_wb_data_sel <= 0;  // from mem
    end else begin
      W_wb_data_sel <= 1;  // from alu
    end
  end

  // M_dm_w_en
  always @(M_op or M_f3) begin
    if (`S_TYPE(M_op)) begin
      M_dm_w_en[0]   <= 1'b1;
      M_dm_w_en[1]   <= M_f3[0] || M_f3[1];
      M_dm_w_en[3:2] <= {2{M_f3[1]}};
    end else begin
      M_dm_w_en <= 4'b0000;
    end
  end
endmodule
