// Include dependencies here (or compile-list include)
`include "./src/epu_sa_dma_shell.sv"   // contains module epu_sa_dma_shell
// epu_sa_top.sv
`timescale 1ns/1ps
`default_nettype none

module epu_sa_top #(
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
  output logic        done
);

  // ------------------------------------------------------------
  // Top cannot expose MMIO ports, so tie-off here.
  // TB will override these via hierarchical force.
  // ------------------------------------------------------------
  logic              mem_cmd_valid;
  logic              mem_cmd_ready;
  logic              mem_cmd_is_write;
  logic [ADDR_W-1:0] mem_cmd_addr;
  logic [DATA_W-1:0] mem_cmd_wdata;
  logic [BYTE_W-1:0] mem_cmd_wmask;
  logic              mem_rsp_valid;
  logic [DATA_W-1:0] mem_rsp_rdata;

  assign mem_cmd_valid    = 1'b0;
  assign mem_cmd_is_write = 1'b0;
  assign mem_cmd_addr     = '0;
  assign mem_cmd_wdata    = '0;
  assign mem_cmd_wmask    = '0;

  // IMPORTANT: instance name MUST be u_shell (TB expects dut.u_shell.*)
  epu_sa_dma_shell #(
    .M(M), .N(N), .KMAX(KMAX),
    .ADDR_W(ADDR_W), .DATA_W(DATA_W), .BYTE_W(BYTE_W),
    .BANKS(BANKS), .MEM_ADDR_W(MEM_ADDR_W),
    .W_BASE(W_BASE), .X_BASE(X_BASE), .C_BASE(C_BASE)
  ) u_shell (
    .clk(clk),
    .rst(rst),

    .start(start),
    .K_len(K_len),
    .busy(busy),
    .done(done),

    .mem_cmd_valid   (mem_cmd_valid),
    .mem_cmd_ready   (mem_cmd_ready),
    .mem_cmd_is_write(mem_cmd_is_write),
    .mem_cmd_addr    (mem_cmd_addr),
    .mem_cmd_wdata   (mem_cmd_wdata),
    .mem_cmd_wmask   (mem_cmd_wmask),
    .mem_rsp_valid   (mem_rsp_valid),
    .mem_rsp_rdata   (mem_rsp_rdata)
  );

endmodule

`default_nettype wire
