module tile_compute_system_top_ref #(
  parameter int M=4, N=4, KMAX=16, DATA_W=32,
  parameter int ROW_W=2, COL_W=2
)(
  input logic clk, rst,
  input logic start,
  input logic [15:0] K_len,

  // W/X tiles
  input logic [M*KMAX*DATA_W-1:0] W_tile_flat,
  input logic [KMAX*N*DATA_W-1:0] X_tile_flat,

  // CPU read C SRAM
  input  logic              c_rd_en,
  input  logic              c_rd_re,
  input  logic [ROW_W-1:0]  c_rd_row,
  input  logic [COL_W-1:0]  c_rd_col,
  output logic [DATA_W-1:0] c_rd_rdata,
  output logic              c_rd_rvalid
);

  logic c_we;
  logic [ROW_W-1:0] c_row;
  logic [COL_W-1:0] c_col;
  logic [DATA_W-1:0] c_wdata;

  // simple C SRAM
  logic [DATA_W-1:0] c_mem [0:M-1][0:N-1];

  always_ff @(posedge clk) begin
    if (c_we)
      c_mem[c_row][c_col] <= c_wdata;

    if (c_rd_en && c_rd_re) begin
      c_rd_rdata  <= c_mem[c_rd_row][c_rd_col];
      c_rd_rvalid <= 1'b1;
    end else begin
      c_rd_rvalid <= 1'b0;
    end
  end

  c_compute_ref #(
    .M(M), .N(N), .KMAX(KMAX),
    .DATA_W(DATA_W),
    .ROW_W(ROW_W), .COL_W(COL_W)
  ) u_ref (
    .clk(clk),
    .rst(rst),
    .start(start),
    .K_len(K_len),
    .W_tile_flat(W_tile_flat),
    .X_tile_flat(X_tile_flat),
    .c_we(c_we),
    .c_row(c_row),
    .c_col(c_col),
    .c_wdata(c_wdata),
    .done()
  );

endmodule
