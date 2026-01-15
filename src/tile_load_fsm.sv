`timescale 1ns/1ps
`default_nettype none

module tile_load_fsm #(
  parameter int M=8, N=8, KMAX=1024, AW=10
)(
  input  logic clk,
  input  logic rst,

  input  logic        load_start,
  input  logic [15:0] K_len,
  output logic        load_busy,
  output logic        load_done,

  output logic          w_ext_re   [M],
  output logic [AW-1:0] w_ext_addr [M],
  input  logic [31:0]   w_ext_rdata [M],
  input  logic          w_ext_rvalid[M],

  output logic          x_ext_re   [N],
  output logic [AW-1:0] x_ext_addr [N],
  input  logic [31:0]   x_ext_rdata [N],
  input  logic          x_ext_rvalid[N],

  output logic [31:0] W_tile [M][KMAX],
  output logic [31:0] X_tile [KMAX][N]
);

  typedef enum logic [1:0] {IDLE, RUN, DONE} state_t;
  state_t st;

  logic [15:0] K_eff;

  // widths
  localparam int WK_W = (KMAX<=1)?1:$clog2(KMAX);
  localparam int WM_W = (M<=1)?1:$clog2(M+1);     // wm 會到 M
  localparam int XK_W = (KMAX<=1)?1:$clog2(KMAX+1); // xk 會到 K_eff
  localparam int XN_W = (N<=1)?1:$clog2(N);

  logic [WK_W-1:0] wk;
  logic [WM_W-1:0] wm;
  logic [XK_W-1:0] xk;
  logic [XN_W-1:0] xn;

  logic            w_pending, x_pending;
  logic [WM_W-1:0] w_req_m;
  logic [WK_W-1:0] w_req_k;
  logic [XN_W-1:0] x_req_n;
  logic [WK_W-1:0] x_req_k;

  integer i;

  // helper ints for safe indexing
  int unsigned wm_idx;
  int unsigned xn_idx;

  always_comb begin
    wm_idx = wm;
    xn_idx = xn;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      for (i=0; i<M; i++) begin
        w_ext_re[i]   <= 1'b0;
        w_ext_addr[i] <= '0;
      end
      for (i=0; i<N; i++) begin
        x_ext_re[i]   <= 1'b0;
        x_ext_addr[i] <= '0;
      end

      st        <= IDLE;
      load_busy <= 1'b0;
      load_done <= 1'b0;

      K_eff <= 16'd0;

      wk <= '0; wm <= '0;
      xk <= '0; xn <= '0;

      w_pending <= 1'b0;
      x_pending <= 1'b0;

      w_req_m <= '0; w_req_k <= '0;
      x_req_n <= '0; x_req_k <= '0;

    end else begin
      // default deassert
      for (i=0; i<M; i++) begin
        w_ext_re[i]   <= 1'b0;
        w_ext_addr[i] <= '0;
      end
      for (i=0; i<N; i++) begin
        x_ext_re[i]   <= 1'b0;
        x_ext_addr[i] <= '0;
      end

      load_done <= 1'b0;

      case (st)
        IDLE: begin
          load_busy <= 1'b0;
          if (load_start) begin
            K_eff <= (K_len > KMAX) ? KMAX[15:0] : K_len;

            wk <= '0; wm <= '0;
            xk <= '0; xn <= '0;

            w_pending <= 1'b0;
            x_pending <= 1'b0;

            st <= RUN;
            load_busy <= 1'b1;
          end
        end

        RUN: begin
          // Issue W read
          if (!w_pending && (wm < M) && (K_eff != 0)) begin
            w_ext_re[wm_idx]   <= 1'b1;
            w_ext_addr[wm_idx] <= wk[AW-1:0];

            w_pending <= 1'b1;
            w_req_m   <= wm;
            w_req_k   <= wk;

            if ((wk + 1) >= K_eff[WK_W-1:0]) begin
              wk <= '0;
              wm <= wm + 1'b1;
            end else begin
              wk <= wk + 1'b1;
            end
          end

          // Issue X read
          if (!x_pending && (xk < K_eff[XK_W-1:0]) && (K_eff != 0)) begin
            x_ext_re[xn_idx]   <= 1'b1;
            x_ext_addr[xn_idx] <= xk[AW-1:0];

            x_pending <= 1'b1;
            x_req_n   <= xn;
            x_req_k   <= xk[WK_W-1:0];

            if (xn == (N-1)) begin
              xn <= '0;
              xk <= xk + 1'b1;
            end else begin
              xn <= xn + 1'b1;
            end
          end

          // Capture W
          if (w_pending && w_ext_rvalid[w_req_m]) begin
            W_tile[w_req_m][w_req_k] <= w_ext_rdata[w_req_m];
            w_pending <= 1'b0;
          end

          // Capture X
          if (x_pending && x_ext_rvalid[x_req_n]) begin
            X_tile[x_req_k][x_req_n] <= x_ext_rdata[x_req_n];
            x_pending <= 1'b0;
          end

          // Finish
          if ((K_eff == 0) ||
              ((wm >= M) && !w_pending &&
               (xk >= K_eff[XK_W-1:0]) && !x_pending)) begin
            st <= DONE;
          end
        end

        DONE: begin
          load_busy <= 1'b0;
          load_done <= 1'b1;
          st <= IDLE;
        end

        default: st <= IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
