// tb_rv32i_rtype_TRANSPOSE_top.sv
/*
iverilog -g2012 -Wall -I./src \
  -o ./vvp/tb_tp.vvp \
  ./test/tb_rv32i_rtype_TRANSPOSE_to.sv

vvp ./vvp/tb_tp.vvp
*/

`include "./src/EPU/rv32i_rtype_TRANSPOSE_top.sv"
`timescale 1ns/1ps
`default_nettype none


module tb_rv32i_rtype_TRANSPOSE_top_iverilog;

  // ----------------------------
  // Match DUT parameters
  // ----------------------------
  localparam integer NRows  = 8;
  localparam integer NCols  = 8;
  localparam integer DATA_W = 32;
  localparam integer ADDR_W = 16;
  localparam integer NB     = 2;
  localparam integer M      = 6;

  // ----------------------------
  // Clock / Reset
  // ----------------------------
  reg clk;
  reg rst;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ----------------------------
  // DUT CPU custom instruction IF
  // ----------------------------
  reg         instr_valid;
  wire        instr_ready;
  reg  [31:0] instr;
  reg  [31:0] rs1_val;
  reg  [31:0] rs2_val;
  reg  [4:0]  rd_addr;

  wire        rd_we;
  wire [4:0]  rd_waddr;
  wire [31:0] rd_wdata;

  wire        accel_done;

  rv32i_rtype_TRANSPOSE_top #(
    .NRows(NRows),
    .NCols(NCols),
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W),
    .NB(NB),
    .M(M)
  ) dut (
    .clk(clk),
    .rst(rst),

    .instr_valid(instr_valid),
    .instr_ready(instr_ready),
    .instr(instr),
    .rs1_val(rs1_val),
    .rs2_val(rs2_val),
    .rd_addr(rd_addr),

    .rd_we(rd_we),
    .rd_waddr(rd_waddr),
    .rd_wdata(rd_wdata),

    .accel_done(accel_done)
  );

  // ----------------------------
  // funct3 codes
  // ----------------------------
  localparam [2:0] TP_AWR   = 3'b000;
  localparam [2:0] TP_START = 3'b001;
  localparam [2:0] TP_STAT  = 3'b010;
  localparam [2:0] TP_BRD   = 3'b011;

  // ----------------------------
  // Helpers: build instr / pack rc
  // ----------------------------
  function [31:0] mk_instr;
    input [2:0] f3;
    reg [31:0] x;
    begin
      x = 32'b0;
      x[14:12] = f3;
      mk_instr = x;
    end
  endfunction

  function [31:0] pack_rc;
    input integer r;
    input integer c;
    reg [31:0] x;
    begin
      x = 32'b0;
      x[15:8] = r[7:0];
      x[7:0]  = c[7:0];
      pack_rc = x;
    end
  endfunction

  function [31:0] gen_a;
    input integer r;
    input integer c;
    begin
      // unique pattern for debug
      gen_a = {r[15:0], c[15:0]} ^ 32'hA5A5_0000;
    end
  endfunction

  // ----------------------------
  // Basic waits
  // ----------------------------
  task wait_cycles;
    input integer n;
    integer i;
    begin
      for (i = 0; i < n; i = i + 1) @(posedge clk);
    end
  endtask

  // ----------------------------
  // Issue one instruction handshake (NO break)
  // Hold instr_valid until instr_ready observed high at posedge.
  // ----------------------------
  task issue_instr;
    input [2:0]  f3;
    input [31:0] rs1;
    input [31:0] rs2;
    input [4:0]  rd;
    integer guard;
    reg accepted;
    begin
      instr       <= mk_instr(f3);
      rs1_val     <= rs1;
      rs2_val     <= rs2;
      rd_addr     <= rd;
      instr_valid <= 1'b1;

      guard    = 0;
      accepted = 0;

      while (!accepted) begin
        @(posedge clk);
        guard = guard + 1;
        if (instr_ready) accepted = 1;
        if (guard > 5000) begin
          $display("[TB] issue_instr TIMEOUT f3=%b (instr_ready stuck low)", f3);
          $fatal(1);
        end
      end

      // drop valid after accept
      @(negedge clk);
      instr_valid <= 1'b0;
      instr       <= 32'b0;
      rs1_val     <= 32'b0;
      rs2_val     <= 32'b0;
      rd_addr     <= 5'd0;
    end
  endtask

  // ----------------------------
  // Wait for rd_we (STAT or BRD returns)
  // ----------------------------
  task wait_rd;
    output reg [31:0] data;
    input integer max_cycles;
    integer k;
    reg seen;
    begin
      data = 32'h0;
      k    = 0;
      seen = 0;

      while ((k < max_cycles) && (!seen)) begin
        @(posedge clk);
        k = k + 1;
        if (rd_we) begin
          data = rd_wdata;
          seen = 1;
        end
      end

      if (!seen) begin
        $display("[TB] wait_rd TIMEOUT (never saw rd_we)");
        $fatal(1);
      end
    end
  endtask

  // ----------------------------
  // High-level ops
  // ----------------------------
  task tp_awr;
    input integer r;
    input integer c;
    input [31:0] data;
    begin
      issue_instr(TP_AWR, pack_rc(r,c), data, 5'd0);
      // note: DUT's TP_AWR doesn't return rd
    end
  endtask

  task tp_start;
    begin
      issue_instr(TP_START, 32'b0, 32'b0, 5'd0);
    end
  endtask

  task tp_stat;
  output reg busy;
  output reg done;
  reg seen;
  begin
    seen = 0;

    // 發送 STAT
    instr       <= mk_instr(TP_STAT);
    rs1_val     <= 32'b0;
    rs2_val     <= 32'b0;
    rd_addr     <= 5'd1;
    instr_valid <= 1'b1;

    // 等 accept + 立刻抓 rd
    while (!seen) begin
      @(posedge clk);
      if (instr_ready) begin
        // 同一拍 rd_we 就有效
        busy = rd_wdata[1];
        done = rd_wdata[0];
        seen = 1;
      end
    end

    @(negedge clk);
    instr_valid <= 1'b0;
    instr       <= 32'b0;
  end
endtask


  task tp_brd;
    input integer r;
    input integer c;
    output reg [31:0] data;
    begin
      issue_instr(TP_BRD, pack_rc(r,c), 32'b0, 5'd2);
      wait_rd(data, 5000);
    end
  endtask
  task scan_b_for_x;
  integer rr, cc;
  reg [31:0] d;
  integer xcnt, tot;
  begin
    xcnt = 0; tot = 0;
    for (rr = 0; rr < NRows; rr = rr + 1) begin
      for (cc = 0; cc < NCols; cc = cc + 1) begin
        tp_brd(rr, cc, d);
        tot = tot + 1;
        if (^d === 1'bx) xcnt = xcnt + 1; // reduction XOR becomes X if any bit X
      end
    end
    $display("[TB] B scan: X_count=%0d / %0d", xcnt, tot);
  end
endtask
  task tp_brd_dbg;
  input integer r;
  input integer c;
  output reg [31:0] data;
  integer cyc;
  begin
    // issue BRD
    issue_instr(TP_BRD, pack_rc(r,c), 32'b0, 5'd2);

    // wait for rd_we (which happens on B_rsp_v)
    cyc = 0;
    data = 32'h0;
    while (cyc < 5000) begin
      @(posedge clk);
      cyc = cyc + 1;
      if (rd_we) begin
        data = rd_wdata;
        $display("[TB] BRD(r=%0d,c=%0d) rd_we@+%0d data=0x%08x", r,c,cyc,data);
        cyc = 5000;
      end
    end
    if (!rd_we) begin
      $display("[TB] BRD timeout r=%0d c=%0d", r, c);
      $fatal(1);
    end
  end
endtask

  // ----------------------------
  // Main test
  // ----------------------------
  integer r, c;
  reg busy, done;
  reg [31:0] got;
  integer polls;

  initial begin
    $dumpfile("./vvp/tb_tp.vcd");
    $dumpvars(0, tb_rv32i_rtype_TRANSPOSE_top_iverilog);

    // init inputs
    instr_valid = 1'b0;
    instr       = 32'b0;
    rs1_val     = 32'b0;
    rs2_val     = 32'b0;
    rd_addr     = 5'd0;

    // reset
    rst = 1'b1;
    wait_cycles(5);
    rst = 1'b0;
    wait_cycles(5);

    // preload A
    $display("[TB] Preload A SRAM...");
    for (r = 0; r < NRows; r = r + 1) begin
      for (c = 0; c < NCols; c = c + 1) begin
        tp_awr(r, c, gen_a(r,c));
      end
    end

    // start transpose
    $display("[TB] TP_START...");
    tp_start();

    // poll stat
    $display("[TB] Poll TP_STAT until done...");
    done  = 1'b0;
    polls = 0;
    while ((!done) && (polls < 20000)) begin
      tp_stat(busy, done);
      polls = polls + 1;
    end
    if (!done) begin
      $display("[TB] FAIL: never saw done=1 (polls=%0d)", polls);
      $fatal(1);
    end
    $display("[TB] Done seen! busy=%0d done=%0d polls=%0d", busy, done, polls);

    // readback & check
    $display("[TB] Read back via TP_BRD and check BRD(r,c)==A[r,c] ...");
    for (r = 0; r < NRows; r = r + 1) begin
      for (c = 0; c < NCols; c = c + 1) begin
        tp_brd(r, c, got);
        if (got !== gen_a(r,c)) begin
          $display("[TB][FAIL] r=%0d c=%0d got=0x%08x exp=0x%08x",
                   r, c, got, gen_a(r,c));
          $fatal(1);
        end
      end
    end

    $display("[TB][PASS] All checks passed.");
    wait_cycles(10);
    $finish;
  end

endmodule

`default_nettype wire
