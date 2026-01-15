`timescale 1ns/1ps
`default_nettype none

module c_compute_ref #(
  parameter int M = 4,
  parameter int N = 4,
  parameter int KMAX = 16,
  parameter int DATA_W = 32,
  parameter int ROW_W = 2,
  parameter int COL_W = 2
)(
  input  logic clk,
  input  logic rst,

  input  logic start,
  input  logic [15:0] K_len,

  input  logic [M*KMAX*DATA_W-1:0] W_tile_flat,
  input  logic [KMAX*N*DATA_W-1:0] X_tile_flat,

  // C SRAM write port (abstracted)
  output logic              c_we,
  output logic [ROW_W-1:0]  c_row,
  output logic [COL_W-1:0]  c_col,
  output logic [DATA_W-1:0] c_wdata,

  output logic done
);

  int r, c, k;
  logic [63:0] acc;

  always_ff @(posedge clk) begin
    if (rst) begin
      done <= 1'b0;
      c_we <= 1'b0;
    end else begin
      c_we <= 1'b0;
      done <= 1'b0;

      if (start) begin
        // brute-force reference compute
        for (r = 0; r < M; r++) begin
          for (c = 0; c < N; c++) begin
            acc = 0;
            for (k = 0; k < K_len; k++) begin
              acc +=
                W_tile_flat[(r*KMAX + k)*DATA_W +: DATA_W] *
                X_tile_flat[(k*N + c)*DATA_W +: DATA_W];
            end
            // write C
            c_we    <= 1'b1;
            c_row   <= r[ROW_W-1:0];
            c_col   <= c[COL_W-1:0];
            c_wdata <= acc[DATA_W-1:0];
            @(posedge clk); // one write per cycle
          end
        end
        done <= 1'b1;
      end
    end
  end

endmodule

`default_nettype wire
