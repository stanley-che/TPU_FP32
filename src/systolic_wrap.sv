// systolic_wrap.sv
// Wrap: sa_tile_driver + systolic_array_os (synth-friendly, no hierarchical access)
`include "./src/sa_tile_driver.sv"
`timescale 1ns/1ps

module systolic_wrap #(
  parameter int M    = 8,
  parameter int N    = 8,
  parameter int KMAX = 1024
)(
  input  logic clk,
  input  logic rst,

  // ---------------- Tile command (from EPU controller) ----------------
  input  logic        start,      // pulse
  input  logic [15:0] K_len,
  output logic        busy,
  output logic        done,       // 1-cycle pulse when tile finished

  // ---------------- Tile buffers ----------------
  input  logic [31:0] W_tile [M][KMAX],
  input  logic [31:0] X_tile [KMAX][N],

  // ---------------- Result ----------------
  output logic [31:0] C_tile [M][N],
  output logic        C_valid      // here: pulse aligned with done
);

  // ---------------- Internal handshake between driver <-> SA ----------------
  wire         step_valid;
  wire [31:0]  a_row [M];
  wire [31:0]  b_col [N];
  wire         k_first;
  wire         k_last;

  wire         step_ready;

  wire [31:0]  c_out_int   [M][N];
  wire         c_valid_int [M][N];

  wire tile_busy;
  wire tile_done;

  // ---------------- sa_tile_driver ----------------
  sa_tile_driver #(.M(M), .N(N), .KMAX(KMAX)) drv (
    .clk       (clk),
    .rst       (rst),

    .tile_start(start),
    .K_len     (K_len),
    .tile_busy (tile_busy),
    .tile_done (tile_done),

    .W_tile    (W_tile),
    .X_tile    (X_tile),

    .step_valid(step_valid),
    .a_row     (a_row),
    .b_col     (b_col),
    .k_first   (k_first),
    .k_last    (k_last),

    .step_ready(step_ready),
    .c_out     (c_out_int),
    .c_valid   (c_valid_int)
  );

  // ---------------- systolic_array_os ----------------
  systolic_array_os #(.M(M), .N(N)) sa (
    .clk       (clk),
    .rst       (rst),

    .step_valid(step_valid),
    .a_row     (a_row),
    .b_col     (b_col),
    .k_first   (k_first),
    .k_last    (k_last),

    .step_ready(step_ready),
    .c_out     (c_out_int),
    .c_valid   (c_valid_int)
  );

  // ---------------- Outputs ----------------
  always_comb begin
    busy    = tile_busy;
    done    = tile_done;

    // Result matrix: continuously reflects SA output matrix.
    // After done, SA should hold the computed values until next start/k_first clears.
    for (int i = 0; i < M; i++) begin
      for (int j = 0; j < N; j++) begin
        C_tile[i][j] = c_out_int[i][j];
      end
    end

    // "tile result valid" pulse: simplest contract for controller
    C_valid = tile_done;
  end

endmodule
