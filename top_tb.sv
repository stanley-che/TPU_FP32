// Copyright (c) 2020 Sonal Pinto
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns/10ps

`define CYCLE 10.0    // Cycle time
`define MAX 100000    // Max cycle number
`define prog_path "./test/prog0/main.hex"
`define gold_path "./test/prog0/golden.hex"

`define mem_word(addr) \
  {top.u_SRAM_dm.mem[addr+3], \
   top.u_SRAM_dm.mem[addr+2], \
   top.u_SRAM_dm.mem[addr+1], \
   top.u_SRAM_dm.mem[addr]}

`define ANSWER_START 'h9000

module top_tb;

  logic clk;
  logic rst;

  logic [31:0] GOLDEN [128];
  integer gf;               // pointer of golden file
  integer num;              // total golden data
  integer err;              // total number of errors compared to golden data

  integer i;

  Top top (
    .clk(clk),
    .rst(rst)
  );

  always #(`CYCLE/2) clk = ~clk;

  initial begin

    clk = 0; rst = 1;
    #(`CYCLE) rst = 0;


    // Load program and preset data to im & dm 
    $readmemh(`prog_path, top.u_SRAM_im.mem);
    $readmemh(`prog_path, top.u_SRAM_dm.mem);


    // Initialize part of the memory (needed by the test program)
    `mem_word('h9078) = 32'd0;
    `mem_word('h907c) = 32'd0;
    `mem_word('h9080) = 32'd0;
    `mem_word('h9084) = 32'd0;
    `mem_word('hfffc) = 32'd0;


    // Initialize register[0] = 0 (hardwire to ground)
    top.u_Reg_File.registers[0] = 32'd0;


    // Load Gloden Data
    num = 0;
    gf = $fopen(`gold_path, "r");
    while (!$feof(gf)) begin
    	$fscanf(gf, "%h\n", GOLDEN[num]);
      num++;
    end
    $fclose(gf);


    // Wait until end of execution
    wait(top.u_SRAM_dm.mem[16'hfffc] == 8'hff);
    $display("\nDone\n");


    // Compare result with Golden Data
    err = 0;
    for (i = 0; i < num; i++)
    begin
      if (`mem_word(`ANSWER_START + i*4) !== GOLDEN[i])
      begin
        $display("DM['h%4h] = %h, expect = %h", `ANSWER_START + i*4, `mem_word(`ANSWER_START + i*4), GOLDEN[i]);
        err = err + 1;
      end
      else
      begin
        $display("DM['h%4h] = %h, pass", `ANSWER_START + i*4, `mem_word(`ANSWER_START + i*4));
      end
    end


    // Print result
    result(err, num);
    $finish;

  end

  task result;
    input integer err;
    input integer num;
    begin
      if (err === 0)
      begin
        $display("\n");
        $display("\n");
        $display("                                      `;-.          ___,");
        $display("        ****************************    `.`\\_...._/`.-\"`");
        $display("        **                        **      \\        /      ,");
        $display("        **                        **      /()   () \\   .' `-._");
        $display("        **   Congratulations !!   **     |)  .    ()\\ /   _.'");
        $display("        **                        **     \\  -'-     ,; '. <");
        $display("        **                        **      ;.__     ,;|   > \\");
        $display("        **   Simulation PASS!!    **     / ,    / ,  |.-'.-'");
        $display("        **                        **    (_/    (_/ ,;|.<`");
        $display("        **                        **      \\    ,     ;-`");
        $display("        ****************************       >   \\    /");
        $display("                                          (_,-'`> .'");
        $display("                                               (_,'");
        $display("\n");
      end
      else
      begin
        $display("\n");
        $display("\n");
        $display("        ****************************     /*\\_...._/*^\\");
        $display("        **                        **    (/^\\       / \\)  ,");
        $display("        **                        **      / X   X  \\   .' `-._");
        $display("        **   OOPS!                **     |)  .    ()\\ /   _.'");
        $display("        **                        **     \\   ^     ,; '. <");
        $display("        **                        **      ;.__     ,;|   > \\");
        $display("        **   Simulation Failed!!  **     / ,    / ,  |.-'.-'");
        $display("        **                        **    (_/    (_/ ,;|.<`");
        $display("        **                        **      \\    ,     ;-`");
        $display("        ****************************       >   \\    /");
        $display("                                          (_,-'`> .'");
        $display("                                               (_,'");
        $display("         Totally has %d errors"                     , err);
        $display("\n");
      end
    end
  endtask

  initial begin
    #(`CYCLE*`MAX)
    $finish;
  end

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(2,top);
    $dumpvars(0,top.u_Reg_File);
  end

endmodule
