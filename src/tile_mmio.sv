// epu_sa_dma_shell_mmio.sv
`include "./src/axi_sram_slave.sv"   // must contain sram_8bank_1op_ctrl
`include "./src/tile_core.sv"        // must contain sa_compute_block
`timescale 1ns/1ps
`default_nettype none
// tile_mmio.sv
// - External simple MMIO bus <-> 3 SRAM ports (W/X/C)
// - Single outstanding transaction for MMIO
// - Arbitration: when busy=1, internal ports own SRAM; external is blocked
`timescale 1ns/1ps
`default_nettype none

module tile_mmio #(
  parameter int ADDR_W = 16,
  parameter int DATA_W = 32,
  parameter int BYTE_W = (DATA_W/8),

  parameter int M    = 8,
  parameter int N    = 8,
  parameter int KMAX = 1024,

  parameter logic [ADDR_W-1:0] W_BASE = 'h0000,
  parameter logic [ADDR_W-1:0] X_BASE = 'h4000,
  parameter logic [ADDR_W-1:0] C_BASE = 'h8000
)(
  input  logic clk,
  input  logic rst,

  // engine busy: when 1 => internal owns SRAM, external blocked
  input  logic engine_busy,

  // ---------------- external MMIO bus ----------------
  input  logic              mem_cmd_valid,
  output logic              mem_cmd_ready,
  input  logic              mem_cmd_is_write,
  input  logic [ADDR_W-1:0] mem_cmd_addr,
  input  logic [DATA_W-1:0] mem_cmd_wdata,
  input  logic [BYTE_W-1:0] mem_cmd_wmask,
  output logic              mem_rsp_valid,
  output logic [DATA_W-1:0] mem_rsp_rdata,

  // ---------------- internal port to W SRAM ----------------
  input  logic              w_i_cmd_valid,
  output logic              w_i_cmd_ready,
  input  logic              w_i_cmd_is_write,
  input  logic [ADDR_W-1:0] w_i_cmd_addr,
  input  logic [DATA_W-1:0] w_i_cmd_wdata,
  input  logic [BYTE_W-1:0] w_i_cmd_wmask,
  output logic              w_i_rsp_valid,
  output logic [DATA_W-1:0] w_i_rsp_rdata,

  // ---------------- internal port to X SRAM ----------------
  input  logic              x_i_cmd_valid,
  output logic              x_i_cmd_ready,
  input  logic              x_i_cmd_is_write,
  input  logic [ADDR_W-1:0] x_i_cmd_addr,
  input  logic [DATA_W-1:0] x_i_cmd_wdata,
  input  logic [BYTE_W-1:0] x_i_cmd_wmask,
  output logic              x_i_rsp_valid,
  output logic [DATA_W-1:0] x_i_rsp_rdata,

  // ---------------- internal port to C SRAM ----------------
  input  logic              c_i_cmd_valid,
  output logic              c_i_cmd_ready,
  input  logic              c_i_cmd_is_write,
  input  logic [ADDR_W-1:0] c_i_cmd_addr,
  input  logic [DATA_W-1:0] c_i_cmd_wdata,
  input  logic [BYTE_W-1:0] c_i_cmd_wmask,
  output logic              c_i_rsp_valid,
  output logic [DATA_W-1:0] c_i_rsp_rdata,

  // ---------------- physical W SRAM port ----------------
  output logic              w_cmd_valid,
  input  logic              w_cmd_ready,
  output logic              w_cmd_is_write,
  output logic [ADDR_W-1:0] w_cmd_addr,
  output logic [DATA_W-1:0] w_cmd_wdata,
  output logic [BYTE_W-1:0] w_cmd_wmask,
  input  logic              w_rsp_valid,
  input  logic [DATA_W-1:0] w_rsp_rdata,

  // ---------------- physical X SRAM port ----------------
  output logic              x_cmd_valid,
  input  logic              x_cmd_ready,
  output logic              x_cmd_is_write,
  output logic [ADDR_W-1:0] x_cmd_addr,
  output logic [DATA_W-1:0] x_cmd_wdata,
  output logic [BYTE_W-1:0] x_cmd_wmask,
  input  logic              x_rsp_valid,
  input  logic [DATA_W-1:0] x_rsp_rdata,

  // ---------------- physical C SRAM port ----------------
  output logic              c_cmd_valid,
  input  logic              c_cmd_ready,
  output logic              c_cmd_is_write,
  output logic [ADDR_W-1:0] c_cmd_addr,
  output logic [DATA_W-1:0] c_cmd_wdata,
  output logic [BYTE_W-1:0] c_cmd_wmask,
  input  logic              c_rsp_valid,
  input  logic [DATA_W-1:0] c_rsp_rdata
);

  // ============================================================
  // Address decode (external only)
  // ============================================================
  localparam int W_BYTES = M*KMAX*4;
  localparam int X_BYTES = KMAX*N*4;
  localparam int C_BYTES = M*N*4;

  function automatic logic in_range(
    input logic [ADDR_W-1:0] a,
    input logic [ADDR_W-1:0] base,
    input int unsigned bytes
  );
    logic [ADDR_W:0] diff;
    begin
      diff = {1'b0,a} - {1'b0,base};
      in_range = (a >= base) && (diff < bytes);
    end
  endfunction

  typedef enum logic [1:0] {T_NONE=2'd0, T_W=2'd1, T_X=2'd2, T_C=2'd3} tgt_e;

  tgt_e ext_tgt;
  always_comb begin
    if      (in_range(mem_cmd_addr, W_BASE, W_BYTES)) ext_tgt = T_W;
    else if (in_range(mem_cmd_addr, X_BASE, X_BYTES)) ext_tgt = T_X;
    else if (in_range(mem_cmd_addr, C_BASE, C_BYTES)) ext_tgt = T_C;
    else                                              ext_tgt = T_NONE;
  end

  // ============================================================
  // External MMIO: single outstanding transaction
  // - If addr invalid => respond with rsp_valid + rdata=0 (for read) or 0 (for write)
  // - When engine_busy=1 => fully blocked (ready=0, rsp_valid=0)
  // ============================================================
  typedef enum logic [1:0] {E_IDLE, E_WAIT_W, E_WAIT_X, E_WAIT_C} ext_state_e;
  ext_state_e ext_state;

  logic [DATA_W-1:0] ext_rsp_rdata_q;
  logic              ext_rsp_valid_q;

  // latch which target for current outstanding
  tgt_e ext_tgt_q;

  // combinational external ready (only when not busy and idle and target ready)
  always_comb begin
    mem_cmd_ready = 1'b0;
    if (!engine_busy && (ext_state == E_IDLE) && mem_cmd_valid) begin
      case (ext_tgt)
        T_W: mem_cmd_ready = w_cmd_ready;  // will drive W port
        T_X: mem_cmd_ready = x_cmd_ready;
        T_C: mem_cmd_ready = c_cmd_ready;
        default: mem_cmd_ready = 1'b1;     // invalid addr: accept and respond immediately
      endcase
    end
    // If mem_cmd_valid is 0, you can optionally allow mem_cmd_ready high,
    // but keeping it dependent is fine for TB.
  end

  // ============================================================
  // External drives "ext_*" internal signals (then muxed with internal by engine_busy)
  // ============================================================
  logic              w_e_cmd_valid, w_e_cmd_is_write;
  logic [ADDR_W-1:0] w_e_cmd_addr;
  logic [DATA_W-1:0] w_e_cmd_wdata;
  logic [BYTE_W-1:0] w_e_cmd_wmask;

  logic              x_e_cmd_valid, x_e_cmd_is_write;
  logic [ADDR_W-1:0] x_e_cmd_addr;
  logic [DATA_W-1:0] x_e_cmd_wdata;
  logic [BYTE_W-1:0] x_e_cmd_wmask;

  logic              c_e_cmd_valid, c_e_cmd_is_write;
  logic [ADDR_W-1:0] c_e_cmd_addr;
  logic [DATA_W-1:0] c_e_cmd_wdata;
  logic [BYTE_W-1:0] c_e_cmd_wmask;

  always_comb begin
    // default none
    w_e_cmd_valid    = 1'b0; w_e_cmd_is_write = 1'b0; w_e_cmd_addr  = '0; w_e_cmd_wdata = '0; w_e_cmd_wmask = '0;
    x_e_cmd_valid    = 1'b0; x_e_cmd_is_write = 1'b0; x_e_cmd_addr  = '0; x_e_cmd_wdata = '0; x_e_cmd_wmask = '0;
    c_e_cmd_valid    = 1'b0; c_e_cmd_is_write = 1'b0; c_e_cmd_addr  = '0; c_e_cmd_wdata = '0; c_e_cmd_wmask = '0;

    if (!engine_busy && (ext_state == E_IDLE) && mem_cmd_valid && mem_cmd_ready) begin
      case (ext_tgt)
        T_W: begin
          w_e_cmd_valid    = 1'b1;
          w_e_cmd_is_write = mem_cmd_is_write;
          w_e_cmd_addr     = mem_cmd_addr;
          w_e_cmd_wdata    = mem_cmd_wdata;
          w_e_cmd_wmask    = mem_cmd_wmask;
        end
        T_X: begin
          x_e_cmd_valid    = 1'b1;
          x_e_cmd_is_write = mem_cmd_is_write;
          x_e_cmd_addr     = mem_cmd_addr;
          x_e_cmd_wdata    = mem_cmd_wdata;
          x_e_cmd_wmask    = mem_cmd_wmask;
        end
        T_C: begin
          c_e_cmd_valid    = 1'b1;
          c_e_cmd_is_write = mem_cmd_is_write;
          c_e_cmd_addr     = mem_cmd_addr;
          c_e_cmd_wdata    = mem_cmd_wdata;
          c_e_cmd_wmask    = mem_cmd_wmask;
        end
        default: ; // invalid addr handled in FSM
      endcase
    end
  end

  // FSM for external outstanding
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      ext_state       <= E_IDLE;
      ext_tgt_q       <= T_NONE;
      ext_rsp_valid_q <= 1'b0;
      ext_rsp_rdata_q <= '0;
    end else begin
      ext_rsp_valid_q <= 1'b0;

      if (engine_busy) begin
        // fully block external; also drop any outstanding for safety
        ext_state <= E_IDLE;
        ext_tgt_q <= T_NONE;
      end else begin
        case (ext_state)
          E_IDLE: begin
            if (mem_cmd_valid && mem_cmd_ready) begin
              ext_tgt_q <= ext_tgt;
              case (ext_tgt)
                T_W: ext_state <= E_WAIT_W;
                T_X: ext_state <= E_WAIT_X;
                T_C: ext_state <= E_WAIT_C;
                default: begin
                  // invalid address: immediate response
                  ext_rsp_valid_q <= 1'b1;
                  ext_rsp_rdata_q <= '0;
                  ext_state       <= E_IDLE;
                  ext_tgt_q       <= T_NONE;
                end
              endcase
            end
          end

          E_WAIT_W: begin
            if (w_rsp_valid) begin
              ext_rsp_valid_q <= 1'b1;
              ext_rsp_rdata_q <= w_rsp_rdata;
              ext_state       <= E_IDLE;
            end
          end

          E_WAIT_X: begin
            if (x_rsp_valid) begin
              ext_rsp_valid_q <= 1'b1;
              ext_rsp_rdata_q <= x_rsp_rdata;
              ext_state       <= E_IDLE;
            end
          end

          E_WAIT_C: begin
            if (c_rsp_valid) begin
              ext_rsp_valid_q <= 1'b1;
              ext_rsp_rdata_q <= c_rsp_rdata;
              ext_state       <= E_IDLE;
            end
          end
        endcase
      end
    end
  end

  assign mem_rsp_valid = ext_rsp_valid_q;
  assign mem_rsp_rdata = ext_rsp_rdata_q;

  // ============================================================
  // Arbitration mux: engine_busy ? internal : external
  // And route responses back to internal always (they own only when busy)
  // ============================================================
  // W mux
  always_comb begin
    if (engine_busy) begin
      w_cmd_valid    = w_i_cmd_valid;
      w_cmd_is_write = w_i_cmd_is_write;
      w_cmd_addr     = w_i_cmd_addr;
      w_cmd_wdata    = w_i_cmd_wdata;
      w_cmd_wmask    = w_i_cmd_wmask;
      w_i_cmd_ready  = w_cmd_ready;
      w_i_rsp_valid  = w_rsp_valid;
      w_i_rsp_rdata  = w_rsp_rdata;
    end else begin
      w_cmd_valid    = w_e_cmd_valid;
      w_cmd_is_write = w_e_cmd_is_write;
      w_cmd_addr     = w_e_cmd_addr;
      w_cmd_wdata    = w_e_cmd_wdata;
      w_cmd_wmask    = w_e_cmd_wmask;
      w_i_cmd_ready  = 1'b0;
      w_i_rsp_valid  = 1'b0;
      w_i_rsp_rdata  = '0;
    end
  end

  // X mux
  always_comb begin
    if (engine_busy) begin
      x_cmd_valid    = x_i_cmd_valid;
      x_cmd_is_write = x_i_cmd_is_write;
      x_cmd_addr     = x_i_cmd_addr;
      x_cmd_wdata    = x_i_cmd_wdata;
      x_cmd_wmask    = x_i_cmd_wmask;
      x_i_cmd_ready  = x_cmd_ready;
      x_i_rsp_valid  = x_rsp_valid;
      x_i_rsp_rdata  = x_rsp_rdata;
    end else begin
      x_cmd_valid    = x_e_cmd_valid;
      x_cmd_is_write = x_e_cmd_is_write;
      x_cmd_addr     = x_e_cmd_addr;
      x_cmd_wdata    = x_e_cmd_wdata;
      x_cmd_wmask    = x_e_cmd_wmask;
      x_i_cmd_ready  = 1'b0;
      x_i_rsp_valid  = 1'b0;
      x_i_rsp_rdata  = '0;
    end
  end

  // C mux
  always_comb begin
    if (engine_busy) begin
      c_cmd_valid    = c_i_cmd_valid;
      c_cmd_is_write = c_i_cmd_is_write;
      c_cmd_addr     = c_i_cmd_addr;
      c_cmd_wdata    = c_i_cmd_wdata;
      c_cmd_wmask    = c_i_cmd_wmask;
      c_i_cmd_ready  = c_cmd_ready;
      c_i_rsp_valid  = c_rsp_valid;
      c_i_rsp_rdata  = c_rsp_rdata;
    end else begin
      c_cmd_valid    = c_e_cmd_valid;
      c_cmd_is_write = c_e_cmd_is_write;
      c_cmd_addr     = c_e_cmd_addr;
      c_cmd_wdata    = c_e_cmd_wdata;
      c_cmd_wmask    = c_e_cmd_wmask;
      c_i_cmd_ready  = 1'b0;
      c_i_rsp_valid  = 1'b0;
      c_i_rsp_rdata  = '0;
    end
  end

endmodule

`default_nettype wire
