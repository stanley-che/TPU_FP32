`timescale 1ns/1ps
`default_nettype none

module w_sram_to_arow #(
  parameter int unsigned M      = 8,
  parameter int unsigned KMAX   = 1024,
  parameter int unsigned DATA_W = 32,
  parameter int unsigned BYTE_W = DATA_W/8,
  parameter int unsigned ROW_W  = (M<=1)?1:$clog2(M),
  parameter int unsigned K_W    = (KMAX<=1)?1:$clog2(KMAX)
)(
  input  logic clk,
  input  logic rst,

  // -------- control --------
  input  logic          start_k,     // pulse: begin loading this k
  input  logic [K_W-1:0] k_idx,       // which k
  output logic          arow_valid,   // level while row filled
  input  logic          arow_accept,  // 1-cycle pulse: consumer accepts

  // -------- SRAM (your sram_mem_mn port) --------
  output logic                 w_en,
  output logic                 w_re,
  output logic                 w_we,
  output logic [ROW_W-1:0]     w_row,
  output logic [K_W-1:0]       w_k,
  output logic [DATA_W-1:0]    w_wdata,
  output logic [BYTE_W-1:0]    w_wmask,
  input  logic [DATA_W-1:0]    w_rdata,
  input  logic                 w_rvalid,

  // -------- output to systolic side --------
  output logic [DATA_W-1:0]    a_row [M]
);

  // ------------------------------------------------------------
  // Write port not used (tie-off)
  // ------------------------------------------------------------
  always_comb begin
    w_we    = 1'b0;
    w_wdata = '0;
    w_wmask = '0;
  end

  typedef enum logic [1:0] {IDLE, REQ, WAIT, HOLD} st_t;
  st_t st;

  logic [ROW_W-1:0] row_ptr;     // next row to request
  logic [ROW_W-1:0] row_issued;  // ★ latch which row this returning data belongs to

  integer i;
    logic [K_W-1:0] k_latched;
  // ------------------------------------------------------------
  // Sequential FSM
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      st        <= IDLE;
      row_ptr   <= '0;
      row_issued<= '0;
      k_latched  <= '0;
      for (i=0; i<M; i++) a_row[i] <= '0;
    end else begin
      case (st)
        IDLE: begin
          row_ptr <= '0;
          if (start_k) begin 
              st <= REQ;
              k_latched <= k_idx; 
          end
        end

        // Issue read for current row_ptr (actual request is driven combinationally below)
        REQ: begin
          row_issued <= row_ptr;   // ★ latch the row index for this request
          st <= WAIT;
        end

        // Wait for SRAM response
        WAIT: begin
          if (w_rvalid) begin
            a_row[row_issued] <= w_rdata;  // ★ write using latched row_issued

            if (row_issued == M-1) begin
              st <= HOLD; // full row filled
            end else begin
              row_ptr <= row_ptr + 1;
              st <= REQ;
            end
          end
        end

        // Row is ready until accepted
        HOLD: begin
          if (arow_accept) st <= IDLE;
        end

        default: st <= IDLE;
      endcase
    end
  end

  // ------------------------------------------------------------
  // Outputs / SRAM command (combinational)
  // ------------------------------------------------------------
  always_comb begin
    // defaults
    w_en  = 1'b0;
    w_re  = 1'b0;
    w_row = row_ptr;
    w_k   = k_latched; 
    // valid level
    arow_valid = (st == HOLD);

    // drive read only in REQ state
    if (st == REQ) begin
      w_en = 1'b1;
      w_re = 1'b1;
    end
  end

endmodule

`default_nettype wire
