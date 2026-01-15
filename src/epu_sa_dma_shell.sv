// epu_sa_dma_shell_mmio.sv

`include "./src/tile_mmio.sv"
`timescale 1ns/1ps
`default_nettype none

module epu_sa_dma_shell #(
  parameter int M    = 8,
  parameter int N    = 8,
  parameter int KMAX = 1024,

  parameter int ADDR_W = 16,
  parameter int DATA_W = 32,
  parameter int BYTE_W = (DATA_W/8),
  parameter int BANKS  = 8,
  parameter int MEM_ADDR_W = 10,

  parameter logic [ADDR_W-1:0] W_BASE = 'h0000,
  parameter logic [ADDR_W-1:0] X_BASE = 'h4000,
  parameter logic [ADDR_W-1:0] C_BASE = 'h8000
)(
  input  logic clk,
  input  logic rst,

  input  logic        start,
  input  logic [15:0] K_len,
  output logic        busy,
  output logic        done,

  // external simple MMIO bus (TB/CPU)  ---- (blocked when busy=1)
  input  logic              mem_cmd_valid,
  output logic              mem_cmd_ready,
  input  logic              mem_cmd_is_write,
  input  logic [ADDR_W-1:0] mem_cmd_addr,
  input  logic [DATA_W-1:0] mem_cmd_wdata,
  input  logic [BYTE_W-1:0] mem_cmd_wmask,
  output logic              mem_rsp_valid,
  output logic [DATA_W-1:0] mem_rsp_rdata
);

  // ============================================================
  // Local buffers for compute
  // ============================================================
  logic [31:0] W_tile [M][KMAX];
  logic [31:0] X_tile [KMAX][N];
  logic [31:0] C_tile [M][N];
  logic        C_valid;

  // ============================================================
  // Compute block
  // ============================================================
  logic comp_start, comp_busy, comp_done;

  sa_compute_block #(.M(M), .N(N), .KMAX(KMAX)) u_comp (
    .clk(clk), .rst(rst),
    .start(comp_start),
    .K_len(K_len),
    .busy(comp_busy),
    .done(comp_done),
    .W_tile(W_tile),
    .X_tile(X_tile),
    .C_tile(C_tile),
    .C_valid(C_valid)
  );

  // ============================================================
  // 3x SRAM controllers (physical)
  // ============================================================
  logic              w_cmd_valid, w_cmd_ready, w_cmd_is_write;
  logic [ADDR_W-1:0] w_cmd_addr;
  logic [DATA_W-1:0] w_cmd_wdata;
  logic [BYTE_W-1:0] w_cmd_wmask;
  logic              w_rsp_valid;
  logic [DATA_W-1:0] w_rsp_rdata;

  sram_8bank_1op_ctrl #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .BYTE_W(BYTE_W),
    .BANKS(BANKS), .MEM_ADDR_W(MEM_ADDR_W)
  ) u_w_sram (
    .clk(clk), .rst(rst),
    .cmd_valid(w_cmd_valid),
    .cmd_ready(w_cmd_ready),
    .cmd_is_write(w_cmd_is_write),
    .cmd_addr(w_cmd_addr),
    .cmd_wdata(w_cmd_wdata),
    .cmd_wmask(w_cmd_wmask),
    .rsp_valid(w_rsp_valid),
    .rsp_rdata(w_rsp_rdata)
  );

  logic              x_cmd_valid, x_cmd_ready, x_cmd_is_write;
  logic [ADDR_W-1:0] x_cmd_addr;
  logic [DATA_W-1:0] x_cmd_wdata;
  logic [BYTE_W-1:0] x_cmd_wmask;
  logic              x_rsp_valid;
  logic [DATA_W-1:0] x_rsp_rdata;

  sram_8bank_1op_ctrl #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .BYTE_W(BYTE_W),
    .BANKS(BANKS), .MEM_ADDR_W(MEM_ADDR_W)
  ) u_x_sram (
    .clk(clk), .rst(rst),
    .cmd_valid(x_cmd_valid),
    .cmd_ready(x_cmd_ready),
    .cmd_is_write(x_cmd_is_write),
    .cmd_addr(x_cmd_addr),
    .cmd_wdata(x_cmd_wdata),
    .cmd_wmask(x_cmd_wmask),
    .rsp_valid(x_rsp_valid),
    .rsp_rdata(x_rsp_rdata)
  );

  logic              c_cmd_valid, c_cmd_ready, c_cmd_is_write;
  logic [ADDR_W-1:0] c_cmd_addr;
  logic [DATA_W-1:0] c_cmd_wdata;
  logic [BYTE_W-1:0] c_cmd_wmask;
  logic              c_rsp_valid;
  logic [DATA_W-1:0] c_rsp_rdata;

  sram_8bank_1op_ctrl #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .BYTE_W(BYTE_W),
    .BANKS(BANKS), .MEM_ADDR_W(MEM_ADDR_W)
  ) u_c_sram (
    .clk(clk), .rst(rst),
    .cmd_valid(c_cmd_valid),
    .cmd_ready(c_cmd_ready),
    .cmd_is_write(c_cmd_is_write),
    .cmd_addr(c_cmd_addr),
    .cmd_wdata(c_cmd_wdata),
    .cmd_wmask(c_cmd_wmask),
    .rsp_valid(c_rsp_valid),
    .rsp_rdata(c_rsp_rdata)
  );

  // ============================================================
  // Internal SRAM ports (to tile_mmio) for DMA/loader/store
  // ============================================================
  logic              w_i_cmd_valid, w_i_cmd_ready, w_i_cmd_is_write;
  logic [ADDR_W-1:0] w_i_cmd_addr;
  logic [DATA_W-1:0] w_i_cmd_wdata;
  logic [BYTE_W-1:0] w_i_cmd_wmask;
  logic              w_i_rsp_valid;
  logic [DATA_W-1:0] w_i_rsp_rdata;

  logic              x_i_cmd_valid, x_i_cmd_ready, x_i_cmd_is_write;
  logic [ADDR_W-1:0] x_i_cmd_addr;
  logic [DATA_W-1:0] x_i_cmd_wdata;
  logic [BYTE_W-1:0] x_i_cmd_wmask;
  logic              x_i_rsp_valid;
  logic [DATA_W-1:0] x_i_rsp_rdata;

  logic              c_i_cmd_valid, c_i_cmd_ready, c_i_cmd_is_write;
  logic [ADDR_W-1:0] c_i_cmd_addr;
  logic [DATA_W-1:0] c_i_cmd_wdata;
  logic [BYTE_W-1:0] c_i_cmd_wmask;
  logic              c_i_rsp_valid;
  logic [DATA_W-1:0] c_i_rsp_rdata;

  // ============================================================
  // Tile MMIO + arbitration
  // ============================================================
  tile_mmio #(
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .BYTE_W(BYTE_W),
    .M(M), .N(N), .KMAX(KMAX),
    .W_BASE(W_BASE), .X_BASE(X_BASE), .C_BASE(C_BASE)
  ) u_mmio (
    .clk(clk), .rst(rst),
    .engine_busy(busy),

    .mem_cmd_valid(mem_cmd_valid),
    .mem_cmd_ready(mem_cmd_ready),
    .mem_cmd_is_write(mem_cmd_is_write),
    .mem_cmd_addr(mem_cmd_addr),
    .mem_cmd_wdata(mem_cmd_wdata),
    .mem_cmd_wmask(mem_cmd_wmask),
    .mem_rsp_valid(mem_rsp_valid),
    .mem_rsp_rdata(mem_rsp_rdata),

    .w_i_cmd_valid(w_i_cmd_valid),
    .w_i_cmd_ready(w_i_cmd_ready),
    .w_i_cmd_is_write(w_i_cmd_is_write),
    .w_i_cmd_addr(w_i_cmd_addr),
    .w_i_cmd_wdata(w_i_cmd_wdata),
    .w_i_cmd_wmask(w_i_cmd_wmask),
    .w_i_rsp_valid(w_i_rsp_valid),
    .w_i_rsp_rdata(w_i_rsp_rdata),

    .x_i_cmd_valid(x_i_cmd_valid),
    .x_i_cmd_ready(x_i_cmd_ready),
    .x_i_cmd_is_write(x_i_cmd_is_write),
    .x_i_cmd_addr(x_i_cmd_addr),
    .x_i_cmd_wdata(x_i_cmd_wdata),
    .x_i_cmd_wmask(x_i_cmd_wmask),
    .x_i_rsp_valid(x_i_rsp_valid),
    .x_i_rsp_rdata(x_i_rsp_rdata),

    .c_i_cmd_valid(c_i_cmd_valid),
    .c_i_cmd_ready(c_i_cmd_ready),
    .c_i_cmd_is_write(c_i_cmd_is_write),
    .c_i_cmd_addr(c_i_cmd_addr),
    .c_i_cmd_wdata(c_i_cmd_wdata),
    .c_i_cmd_wmask(c_i_cmd_wmask),
    .c_i_rsp_valid(c_i_rsp_valid),
    .c_i_rsp_rdata(c_i_rsp_rdata),

    .w_cmd_valid(w_cmd_valid),
    .w_cmd_ready(w_cmd_ready),
    .w_cmd_is_write(w_cmd_is_write),
    .w_cmd_addr(w_cmd_addr),
    .w_cmd_wdata(w_cmd_wdata),
    .w_cmd_wmask(w_cmd_wmask),
    .w_rsp_valid(w_rsp_valid),
    .w_rsp_rdata(w_rsp_rdata),

    .x_cmd_valid(x_cmd_valid),
    .x_cmd_ready(x_cmd_ready),
    .x_cmd_is_write(x_cmd_is_write),
    .x_cmd_addr(x_cmd_addr),
    .x_cmd_wdata(x_cmd_wdata),
    .x_cmd_wmask(x_cmd_wmask),
    .x_rsp_valid(x_rsp_valid),
    .x_rsp_rdata(x_rsp_rdata),

    .c_cmd_valid(c_cmd_valid),
    .c_cmd_ready(c_cmd_ready),
    .c_cmd_is_write(c_cmd_is_write),
    .c_cmd_addr(c_cmd_addr),
    .c_cmd_wdata(c_cmd_wdata),
    .c_cmd_wmask(c_cmd_wmask),
    .c_rsp_valid(c_rsp_valid),
    .c_rsp_rdata(c_rsp_rdata)
  );

  // ============================================================
  // Orchestrator: start -> load(W/X) -> compute -> store(C)
  // ============================================================
  typedef enum logic [2:0] {S_IDLE, S_LOAD, S_COMP, S_STORE, S_DONE} state_e;
  state_e st;

  // --- W loader counters
  logic [15:0] wk;
  logic [$clog2(M)-1:0] wi;

  // --- X loader counters
  logic [15:0] xk;
  logic [$clog2(N)-1:0] xj;

  // --- C store counters
  logic [$clog2(M)-1:0] ci;
  logic [$clog2(N)-1:0] cj;

  logic w_load_done, x_load_done, c_store_done;

  // default internal cmd signals
  always_comb begin
    // defaults
    w_i_cmd_valid    = 1'b0; w_i_cmd_is_write = 1'b0; w_i_cmd_addr  = '0; w_i_cmd_wdata = '0; w_i_cmd_wmask = '0;
    x_i_cmd_valid    = 1'b0; x_i_cmd_is_write = 1'b0; x_i_cmd_addr  = '0; x_i_cmd_wdata = '0; x_i_cmd_wmask = '0;
    c_i_cmd_valid    = 1'b0; c_i_cmd_is_write = 1'b0; c_i_cmd_addr  = '0; c_i_cmd_wdata = '0; c_i_cmd_wmask = '0;

    comp_start = 1'b0;

    // LOAD state: read W and X in parallel
    if (st == S_LOAD) begin
      // W read
      if (!w_load_done) begin
        w_i_cmd_valid    = 1'b1;
        w_i_cmd_is_write = 1'b0;
        w_i_cmd_addr     = W_BASE + ( (wi*KMAX + wk) * 4 );
        w_i_cmd_wmask    = '0;
      end

      // X read
      if (!x_load_done) begin
        x_i_cmd_valid    = 1'b1;
        x_i_cmd_is_write = 1'b0;
        x_i_cmd_addr     = X_BASE + ( (xk*N + xj) * 4 );
        x_i_cmd_wmask    = '0;
      end
    end

    // COMP state: pulse start once (handled in FF by gating)
    if (st == S_COMP) begin
      // comp_start asserted in sequential logic for 1 cycle
    end

    // STORE state: write C sequentially
    if (st == S_STORE) begin
      if (!c_store_done) begin
        c_i_cmd_valid    = 1'b1;
        c_i_cmd_is_write = 1'b1;
        c_i_cmd_addr     = C_BASE + ( (ci*N + cj) * 4 );
        c_i_cmd_wdata    = C_tile[ci][cj];
        c_i_cmd_wmask    = {BYTE_W{1'b1}};
      end
    end
  end

  // loader/store done flags
  always_comb begin
    w_load_done  = (wi == M-1) && (wk == (K_len-1));
    x_load_done  = (xk == (K_len-1)) && (xj == N-1);
    c_store_done = (ci == M-1) && (cj == N-1);
  end

  // sequential orchestration + counters advance on handshakes
  logic comp_start_pulsed;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      st <= S_IDLE;
      busy <= 1'b0;
      done <= 1'b0;

      wi <= '0; wk <= '0;
      xk <= '0; xj <= '0;
      ci <= '0; cj <= '0;

      comp_start_pulsed <= 1'b0;
    end else begin
      done <= 1'b0;

      case (st)
        S_IDLE: begin
          busy <= 1'b0;
          comp_start_pulsed <= 1'b0;

          wi <= '0; wk <= '0;
          xk <= '0; xj <= '0;
          ci <= '0; cj <= '0;

          if (start) begin
            busy <= 1'b1;
            st   <= S_LOAD;
          end
        end

        S_LOAD: begin
          // W: accept cmd then wait rsp to write tile and advance
          if (!w_load_done) begin
            // cmd accepted
            if (w_i_cmd_valid && w_i_cmd_ready) begin
              // wait for rsp_valid to capture; counter advanced on rsp
            end
            if (w_i_rsp_valid) begin
              W_tile[wi][wk] <= w_i_rsp_rdata;
              if (wk == (K_len-1)) begin
                wk <= '0;
                wi <= wi + 1;
              end else begin
                wk <= wk + 1;
              end
            end
          end

          // X
          if (!x_load_done) begin
            if (x_i_rsp_valid) begin
              X_tile[xk][xj] <= x_i_rsp_rdata;
              if (xj == N-1) begin
                xj <= '0;
                xk <= xk + 1;
              end else begin
                xj <= xj + 1;
              end
            end
          end

          // when both loaders complete -> compute
          if (w_load_done && x_load_done) begin
            st <= S_COMP;
            comp_start_pulsed <= 1'b0;
          end
        end

        S_COMP: begin
          // pulse comp_start for 1 cycle
          if (!comp_start_pulsed) begin
            comp_start_pulsed <= 1'b1;
          end

          if (comp_done) begin
            st <= S_STORE;
            ci <= '0;
            cj <= '0;
          end
        end

        S_STORE: begin
          // advance on C rsp_valid (write response)
          if (!c_store_done) begin
            if (c_i_rsp_valid) begin
              if (cj == N-1) begin
                cj <= '0;
                ci <= ci + 1;
              end else begin
                cj <= cj + 1;
              end
            end
          end

          if (c_store_done && c_i_rsp_valid) begin
            st <= S_DONE;
          end
        end

        S_DONE: begin
          busy <= 1'b0;
          done <= 1'b1; // 1-cycle pulse
          st   <= S_IDLE;
        end
      endcase
    end
  end

  // comp_start is generated from comp_start_pulsed gating
  always_ff @(posedge clk or posedge rst) begin
    if (rst) comp_start <= 1'b0;
    else     comp_start <= (st == S_COMP) && (!comp_start_pulsed);
  end

endmodule

`default_nettype wire
