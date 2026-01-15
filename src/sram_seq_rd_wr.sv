//sram_seq_rd to wr.sv
`include "./src/axi_sram_slave.sv"
`timescale 1ns/1ps
`default_nettype none


module sram_seq_rd_wr #(
  parameter int ADDR_W = 16,
  parameter int DATA_W = 32,
  parameter int BYTE_W = (DATA_W/8),
  parameter int BANKS  = 8,
  parameter int MEM_ADDR_W = 10,
  parameter int CONFLICT_POLICY = 1
)(
  input  wire                 clk,
  input  wire                 rst,

  input  wire                 start,
  output reg                  busy,
  output reg                  done,

  // step0: read
  input  wire [ADDR_W-1:0]    rd_addr,
  output reg                  rd_valid,
  output reg  [DATA_W-1:0]    rd_data,

  // step1: write
  input  wire [ADDR_W-1:0]    wr_addr,
  input  wire [DATA_W-1:0]    wr_data,
  input  wire [BYTE_W-1:0]    wr_mask
);

  // -------------------------
  // internal cmd/rsp wires
  // -------------------------
  reg                  cmd_valid;
  wire                 cmd_ready;
  reg                  cmd_is_write;
  reg  [ADDR_W-1:0]    cmd_addr;
  reg  [DATA_W-1:0]    cmd_wdata;
  reg  [BYTE_W-1:0]    cmd_wmask;

  wire                 rsp_valid;
  wire [DATA_W-1:0]    rsp_rdata;

  sram_8bank_1op_ctrl #(
    .ADDR_W(ADDR_W),
    .DATA_W(DATA_W),
    .BYTE_W(BYTE_W),
    .BANKS(BANKS),
    .MEM_ADDR_W(MEM_ADDR_W),
    .CONFLICT_POLICY(CONFLICT_POLICY)
  ) u_mem (
    .clk(clk),
    .rst(rst),

    .cmd_valid  (cmd_valid),
    .cmd_ready  (cmd_ready),
    .cmd_is_write(cmd_is_write),
    .cmd_addr   (cmd_addr),
    .cmd_wdata  (cmd_wdata),
    .cmd_wmask  (cmd_wmask),

    .rsp_valid  (rsp_valid),
    .rsp_rdata  (rsp_rdata)
  );

  // -------------------------
  // FSM
  // -------------------------
  typedef enum logic [2:0] {
    IDLE,
    ISSUE_RD,
    WAIT_RD,
    ISSUE_WR,
    DONE
  } state_t;

  state_t st;

  always @(posedge clk) begin
    if (rst) begin
      st         <= IDLE;
      busy       <= 1'b0;
      done       <= 1'b0;

      cmd_valid  <= 1'b0;
      cmd_is_write <= 1'b0;
      cmd_addr   <= '0;
      cmd_wdata  <= '0;
      cmd_wmask  <= '0;

      rd_valid   <= 1'b0;
      rd_data    <= '0;
    end else begin
      // defaults
      done     <= 1'b0;
      rd_valid <= 1'b0;
      cmd_valid <= 1'b0;

      case (st)
        IDLE: begin
          busy <= 1'b0;
          if (start) begin
            busy <= 1'b1;
            st   <= ISSUE_RD;
          end
        end

        ISSUE_RD: begin
          // fire read 1 cycle
          cmd_valid    <= 1'b1;
          cmd_is_write <= 1'b0;
          cmd_addr     <= rd_addr;
          cmd_wdata    <= '0;
          cmd_wmask    <= '0;

          // 你這版 cmd_ready 永遠 1，但保留寫法可擴充
          if (cmd_ready) st <= WAIT_RD;
        end

        WAIT_RD: begin
          if (rsp_valid) begin
            rd_data  <= rsp_rdata;
            rd_valid <= 1'b1;  // pulse
            st       <= ISSUE_WR;
          end
        end

        ISSUE_WR: begin
          cmd_valid    <= 1'b1;
          cmd_is_write <= 1'b1;
          cmd_addr     <= wr_addr;
          cmd_wdata    <= wr_data;
          cmd_wmask    <= wr_mask;

          if (cmd_ready) st <= DONE;
        end

        DONE: begin
          busy <= 1'b0;
          done <= 1'b1;   // pulse 1 cycle
          st   <= IDLE;
        end

        default: st <= IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
