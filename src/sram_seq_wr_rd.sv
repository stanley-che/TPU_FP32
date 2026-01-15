//sram_seq_wr tord.sv
`include "./src/axi_sram_slave.sv"
`timescale 1ns/1ps
`default_nettype none

module sram_seq_wr_rd #(
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

  // step0: write
  input  wire [ADDR_W-1:0]    wr_addr,
  input  wire [DATA_W-1:0]    wr_data,
  input  wire [BYTE_W-1:0]    wr_mask,

  // step1: read
  input  wire [ADDR_W-1:0]    rd_addr,
  output reg                  rd_valid,
  output reg  [DATA_W-1:0]    rd_data
);

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

  typedef enum logic [2:0] {
    IDLE,
    ISSUE_WR,
    GAP1,       // 確保寫入在 bank 的 posedge 先完成
    ISSUE_RD,
    WAIT_RD,
    DONE
  } state_t;

  state_t st;

  always @(posedge clk) begin
    if (rst) begin
      st          <= IDLE;
      busy        <= 1'b0;
      done        <= 1'b0;

      cmd_valid   <= 1'b0;
      cmd_is_write<= 1'b0;
      cmd_addr    <= '0;
      cmd_wdata   <= '0;
      cmd_wmask   <= '0;

      rd_valid    <= 1'b0;
      rd_data     <= '0;
    end else begin
      done      <= 1'b0;
      rd_valid  <= 1'b0;
      cmd_valid <= 1'b0;

      case (st)
        IDLE: begin
          busy <= 1'b0;
          if (start) begin
            busy <= 1'b1;
            st   <= ISSUE_WR;
          end
        end

        ISSUE_WR: begin
          cmd_valid    <= 1'b1;
          cmd_is_write <= 1'b1;
          cmd_addr     <= wr_addr;
          cmd_wdata    <= wr_data;
          cmd_wmask    <= wr_mask;

          if (cmd_ready) st <= GAP1;
        end

        GAP1: begin
          // 1 cycle gap：write 在前一個 posedge 已經寫進 mem
          st <= ISSUE_RD;
        end

        ISSUE_RD: begin
          cmd_valid    <= 1'b1;
          cmd_is_write <= 1'b0;
          cmd_addr     <= rd_addr;
          cmd_wdata    <= '0;
          cmd_wmask    <= '0;

          if (cmd_ready) st <= WAIT_RD;
        end

        WAIT_RD: begin
          if (rsp_valid) begin
            rd_data  <= rsp_rdata;
            rd_valid <= 1'b1; // pulse
            st       <= DONE;
          end
        end

        DONE: begin
          busy <= 1'b0;
          done <= 1'b1;
          st   <= IDLE;
        end

        default: st <= IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
