/*

|     inst      | opcode | funct7 | funct3 | func explain                                      |
| ------------- | ------ | ------ | ------ | --------------------------------------------------|
|   `TP_AWR`    | 0x33   | 0x02   | 3'b000 | read A SRAM：`rs1={row,col}`，`rs2=data`          |
|  `TP_START`   | 0x33   | 0x02   | 3'b001 | start transpose                                   |
|   `TP_STAT`   | 0x33   | 0x02   | 3'b010 | read status `{done,busy}`）                       |
|   `TP_BRD`    | 0x33   | 0x02   | 3'b011 | read B SRAM：`rs1={row,col}` → `rd`               |
*/


`include "./src/EPU/transpose/bank_sram.sv"
`timescale 1ns/1ps
`default_nettype none

module rv32i_rtype_TRANSPOSE_top_iverilog #(
  parameter int unsigned NRows  = 8,
  parameter int unsigned NCols  = 8,
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 16,
  parameter int unsigned NB     = 2,
  parameter int unsigned M      = 6,

  parameter int unsigned ROW_W  = (NRows<=1)?1:$clog2(NRows),
  parameter int unsigned COL_W  = (NCols<=1)?1:$clog2(NCols)
)(
  input  logic clk,
  input  logic rst,                 // active-high

  // CPU custom instruction IF
  input  logic        instr_valid,
  output logic        instr_ready,
  input  logic [31:0] instr,
  input  logic [31:0] rs1_val,
  input  logic [31:0] rs2_val,
  input  logic [4:0]  rd_addr,

  output logic        rd_we,
  output logic [4:0]  rd_waddr,
  output logic [31:0] rd_wdata,

  output logic        accel_done,
  output logic        accel_busy
);

  // ---------------- decode ----------------
  wire [6:0] opcode = instr[6:0];
  wire [6:0] funct7 = instr[31:25];
  wire [2:0] funct3 = instr[14:12];

  localparam logic [6:0] OPC_RTYPE = 7'h33;
  localparam logic [6:0] FUNCT7_TP = 7'h02;

  wire is_tp = (opcode == OPC_RTYPE) && (funct7 == FUNCT7_TP);

  localparam logic [2:0]
    TP_AWR   = 3'b000,
    TP_START = 3'b001,
    TP_STAT  = 3'b010,
    TP_BRD   = 3'b011;

  // rs1 packing: low16 = {row[7:0], col[7:0]}
  // Icarus-safe: avoid chained indexing
  wire [7:0] rs1_row8 = rs1_val[15:8];
  wire [7:0] rs1_col8 = rs1_val[7:0];

  wire [ROW_W-1:0] row_idx = rs1_row8[ROW_W-1:0];
  wire [COL_W-1:0] col_idx = rs1_col8[COL_W-1:0];

  // ---------------- linear address helpers ----------------
  function automatic [ADDR_W-1:0] lin_addr_A(input logic [ROW_W-1:0] r, input logic [COL_W-1:0] c);
    automatic int unsigned t;
    begin
      t = r * NCols + c;
      lin_addr_A = t[ADDR_W-1:0];
    end
  endfunction

  function automatic [ADDR_W-1:0] lin_addr_B(input logic [COL_W-1:0] r, input logic [ROW_W-1:0] c);
    automatic int unsigned t;
    begin
      t = r * NRows + c;
      lin_addr_B = t[ADDR_W-1:0];
    end
  endfunction

  // =========================================================
  // bank_sram A/B
  // =========================================================
  logic               A_req_v, A_req_we;
  logic [ADDR_W-1:0]  A_req_addr;
  logic [DATA_W-1:0]  A_req_wdata;
  logic               A_req_ready;
  logic [DATA_W-1:0]  A_rsp_rdata;
  logic               A_rsp_v;

  logic               B_req_v, B_req_we;
  logic [ADDR_W-1:0]  B_req_addr;
  logic [DATA_W-1:0]  B_req_wdata;
  logic               B_req_ready;
  logic [DATA_W-1:0]  B_rsp_rdata;
  logic               B_rsp_v;

  bank_sram #(.NB(NB), .ADDR_W(ADDR_W), .Data_W(DATA_W), .M(M)) u_mem_A (
    .clk(clk), .rst_n(!rst),
    .req_v(A_req_v), .req_we(A_req_we),
    .Req_addr(A_req_addr), .Req_wData(A_req_wdata),
    .req_ready(A_req_ready),
    .Rsp_rData(A_rsp_rdata),
    .rsp_v(A_rsp_v)
  );

  bank_sram #(.NB(NB), .ADDR_W(ADDR_W), .Data_W(DATA_W), .M(M)) u_mem_B (
    .clk(clk), .rst_n(!rst),
    .req_v(B_req_v), .req_we(B_req_we),
    .Req_addr(B_req_addr), .Req_wData(B_req_wdata),
    .req_ready(B_req_ready),
    .Rsp_rData(B_rsp_rdata),
    .rsp_v(B_rsp_v)
  );

  // =========================================================
  // Engine FSM (transpose) - owns mem when eng_busy=1
  // =========================================================
  localparam logic [2:0]
    ES_IDLE     = 3'd0,
    ES_ISSUE_RD = 3'd1,
    ES_WAIT_RD  = 3'd2,
    ES_ISSUE_WR = 3'd3,
    ES_NEXT     = 3'd4;

  logic [2:0]      est_q, est_d;
  logic [ROW_W-1:0] erow_q, erow_d;
  logic [COL_W-1:0] ecol_q, ecol_d;

  localparam int unsigned TOTAL_PIX = NRows * NCols;
  localparam int unsigned CNT_W     = (TOTAL_PIX<=1)?1:($clog2(TOTAL_PIX)+1);
  logic [CNT_W-1:0] pcnt_q, pcnt_d;

  logic [DATA_W-1:0] a_hold_q, a_hold_d;

  logic eng_start_pulse;
  logic eng_done_pulse;

  assign accel_busy = (est_q != ES_IDLE);

  // sticky done for TP_STAT polling
  logic done_flag_q;
  always_ff @(posedge clk or posedge rst) begin
    if (rst) done_flag_q <= 1'b0;
    else begin
      if (eng_done_pulse)  done_flag_q <= 1'b1;
      if (eng_start_pulse) done_flag_q <= 1'b0;
    end
  end

  // =========================================================
  // CPU FSM (for TP_BRD response waiting)
  // =========================================================
  typedef enum logic [1:0] {CS_IDLE=2'd0, CS_WAIT_B=2'd1} cpu_state_e;
  cpu_state_e cs_q;

  logic [4:0]      pend_rd_q;
  logic [ADDR_W-1:0] pend_baddr_q;

  // =========================================================
  // Arb MUX (SINGLE DRIVER) to memories
  //  - if accel_busy: engine drives
  //  - else: cpu drives
  // =========================================================
  // cpu-side request signals
  logic               cpu_A_req_v, cpu_A_req_we;
  logic [ADDR_W-1:0]  cpu_A_req_addr;
  logic [DATA_W-1:0]  cpu_A_req_wdata;

  logic               cpu_B_req_v, cpu_B_req_we;
  logic [ADDR_W-1:0]  cpu_B_req_addr;
  logic [DATA_W-1:0]  cpu_B_req_wdata;

  // engine-side request signals
  logic               eng_A_req_v, eng_A_req_we;
  logic [ADDR_W-1:0]  eng_A_req_addr;
  logic [DATA_W-1:0]  eng_A_req_wdata;

  logic               eng_B_req_v, eng_B_req_we;
  logic [ADDR_W-1:0]  eng_B_req_addr;
  logic [DATA_W-1:0]  eng_B_req_wdata;

  // mux into memories
  always @* begin
    if (accel_busy) begin
      A_req_v     = eng_A_req_v;
      A_req_we    = eng_A_req_we;
      A_req_addr  = eng_A_req_addr;
      A_req_wdata = eng_A_req_wdata;

      B_req_v     = eng_B_req_v;
      B_req_we    = eng_B_req_we;
      B_req_addr  = eng_B_req_addr;
      B_req_wdata = eng_B_req_wdata;
    end else begin
      A_req_v     = cpu_A_req_v;
      A_req_we    = cpu_A_req_we;
      A_req_addr  = cpu_A_req_addr;
      A_req_wdata = cpu_A_req_wdata;

      B_req_v     = cpu_B_req_v;
      B_req_we    = cpu_B_req_we;
      B_req_addr  = cpu_B_req_addr;
      B_req_wdata = cpu_B_req_wdata;
    end
  end

  // =========================================================
  // Engine combinational next-state + drive eng_* req
  // =========================================================
  always @* begin
    // defaults
    est_d = est_q;
    erow_d = erow_q;
    ecol_d = ecol_q;
    pcnt_d = pcnt_q;

    a_hold_d = a_hold_q;
    eng_done_pulse = 1'b0;

    eng_A_req_v = 1'b0; eng_A_req_we = 1'b0; eng_A_req_addr = '0; eng_A_req_wdata = '0;
    eng_B_req_v = 1'b0; eng_B_req_we = 1'b0; eng_B_req_addr = '0; eng_B_req_wdata = '0;

    case (est_q)
      ES_IDLE: begin
        // wait for eng_start_pulse in sequential
      end

      ES_ISSUE_RD: begin
        eng_A_req_v    = 1'b1;
        eng_A_req_we   = 1'b0;
        eng_A_req_addr = lin_addr_A(erow_q, ecol_q);
        if (A_req_ready) est_d = ES_WAIT_RD;
      end

      ES_WAIT_RD: begin
        if (A_rsp_v) begin
          a_hold_d = A_rsp_rdata;
          est_d    = ES_ISSUE_WR;
        end
      end

      ES_ISSUE_WR: begin
        eng_B_req_v     = 1'b1;
        eng_B_req_we    = 1'b1;
        eng_B_req_addr  = lin_addr_B(ecol_q, erow_q);
        eng_B_req_wdata = a_hold_q;
        if (B_req_ready) begin
          pcnt_d = pcnt_q + 1'b1;
          est_d  = ES_NEXT;
        end
      end

      ES_NEXT: begin
        if (pcnt_d >= TOTAL_PIX[CNT_W-1:0]) begin
          eng_done_pulse = 1'b1;
          est_d = ES_IDLE;
        end else begin
          if ((ecol_q + 1'b1) < NCols[COL_W-1:0]) begin
            ecol_d = ecol_q + 1'b1;
            est_d  = ES_ISSUE_RD;
          end else begin
            ecol_d = '0;
            if ((erow_q + 1'b1) < NRows[ROW_W-1:0]) begin
              erow_d = erow_q + 1'b1;
              est_d  = ES_ISSUE_RD;
            end else begin
              eng_done_pulse = 1'b1;
              est_d = ES_IDLE;
            end
          end
        end
      end

      default: est_d = ES_IDLE;
    endcase
  end

  // Engine sequential
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      est_q   <= ES_IDLE;
      erow_q  <= '0;
      ecol_q  <= '0;
      pcnt_q  <= '0;
      a_hold_q<= '0;
    end else begin
      // start pulse has priority
      if (eng_start_pulse) begin
        est_q  <= ES_ISSUE_RD;
        erow_q <= '0;
        ecol_q <= '0;
        pcnt_q <= '0;
      end else begin
        est_q   <= est_d;
        erow_q  <= erow_d;
        ecol_q  <= ecol_d;
        pcnt_q  <= pcnt_d;
        a_hold_q<= a_hold_d;
      end
    end
  end

  // =========================================================
  // CPU combinational: generate cpu_* req (only meaningful when !accel_busy)
  //  - TP_AWR: 1-beat write A
  //  - TP_BRD: issue read B when accepted -> CS_WAIT_B
  //  - others: no direct mem req
  // =========================================================
  // We'll do "accept" in sequential, but req signals are combinational from "fire" intent.
  // Use a one-cycle "cpu_fire" pulse from sequential to avoid glitchy req.
  logic cpu_fire_q;
  logic [2:0] cpu_f3_q;
  logic [ADDR_W-1:0] cpu_addrA_q;
  logic [DATA_W-1:0] cpu_wdataA_q;
  logic [ADDR_W-1:0] cpu_addrB_q;

  always @* begin
    cpu_A_req_v = 1'b0; cpu_A_req_we = 1'b0; cpu_A_req_addr='0; cpu_A_req_wdata='0;
    cpu_B_req_v = 1'b0; cpu_B_req_we = 1'b0; cpu_B_req_addr='0; cpu_B_req_wdata='0;

    if (!accel_busy && cpu_fire_q) begin
      if (cpu_f3_q == TP_AWR) begin
        cpu_A_req_v     = 1'b1;
        cpu_A_req_we    = 1'b1;
        cpu_A_req_addr  = cpu_addrA_q;
        cpu_A_req_wdata = cpu_wdataA_q;
      end else if (cpu_f3_q == TP_BRD) begin
        cpu_B_req_v    = 1'b1;
        cpu_B_req_we   = 1'b0;
        cpu_B_req_addr = cpu_addrB_q;
      end
    end
  end

  // =========================================================
  // instr_ready policy:
  // - not TP: always ready
  // - TP while CS_WAIT_B: stall
  // - TP while engine busy: only allow TP_STAT
  // =========================================================
  always @* begin
    if (!instr_valid) instr_ready = 1'b1;
    else if (!is_tp)  instr_ready = 1'b1;
    else begin
      if (cs_q != CS_IDLE) instr_ready = 1'b0;
      else if (accel_busy) instr_ready = (funct3 == TP_STAT);
      else                 instr_ready = 1'b1;
    end
  end

  // =========================================================
  // CPU sequential: generate pulses rd_we/accel_done/eng_start_pulse and manage CS_WAIT_B
  // =========================================================
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      rd_we          <= 1'b0;
      rd_waddr       <= 5'd0;
      rd_wdata       <= 32'd0;
      accel_done     <= 1'b0;
      eng_start_pulse<= 1'b0;

      cs_q           <= CS_IDLE;
      pend_rd_q      <= 5'd0;
      pend_baddr_q   <= '0;

      cpu_fire_q     <= 1'b0;
      cpu_f3_q       <= 3'd0;
      cpu_addrA_q    <= '0;
      cpu_wdataA_q   <= '0;
      cpu_addrB_q    <= '0;
    end else begin
      // default pulses
      rd_we           <= 1'b0;
      accel_done      <= 1'b0;
      eng_start_pulse <= 1'b0;
      cpu_fire_q      <= 1'b0;

      // If waiting for B response
      if (cs_q == CS_WAIT_B) begin
        if (B_rsp_v) begin
          rd_we      <= 1'b1;
          rd_waddr   <= pend_rd_q;
          rd_wdata   <= B_rsp_rdata;
          accel_done <= 1'b1;
          cs_q       <= CS_IDLE;
        end
      end

      // accept a new instruction
      if (instr_valid && instr_ready && is_tp) begin
        unique case (funct3)
          TP_AWR: begin
            // prepare 1-cycle cpu write request
            cpu_fire_q  <= 1'b1;
            cpu_f3_q    <= TP_AWR;
            cpu_addrA_q <= lin_addr_A(row_idx, col_idx);
            cpu_wdataA_q<= rs2_val[DATA_W-1:0];
            accel_done  <= 1'b1; // complete immediately
          end

          TP_START: begin
            eng_start_pulse <= 1'b1;
            accel_done      <= 1'b1;
          end

          TP_STAT: begin
            rd_we      <= 1'b1;
            rd_waddr   <= rd_addr;
            // {done,busy} => [1]=done, [0]=busy
            rd_wdata   <= {30'b0, done_flag_q, accel_busy};
            accel_done <= 1'b1;
          end

          TP_BRD: begin
            // issue B read request, only when !busy (guaranteed by instr_ready)
            cpu_fire_q  <= 1'b1;
            cpu_f3_q    <= TP_BRD;
            cpu_addrB_q <= lin_addr_B(col_idx, row_idx); // B(col,row)

            // if accepted same cycle (ready high), go wait state
            if (B_req_ready) begin
              cs_q      <= CS_WAIT_B;
              pend_rd_q <= rd_addr;
              pend_baddr_q <= lin_addr_B(col_idx, row_idx);
            end
          end

          default: begin
            accel_done <= 1'b1;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
