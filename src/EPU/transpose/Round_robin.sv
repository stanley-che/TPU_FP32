`timescale 1ns/1ps
`default_nettype none

module RR_single #(
  parameter integer N = 8
)(
  input  wire              clk,
  input  wire              rst_n,
  input  wire [N-1:0]      req,      // multi request
  output wire [N-1:0]      gnt,      // one-hot grant
  output wire              gnt_flag  // whether any grant occurs
);

  // ===== Registers / wires =====
  reg  [N-1:0] post_base, pre_base;

  // Double-length helper buses for wrap-around one-hot pick
  reg  [2*N-1:0] dbl_req;
  reg  [2*N-1:0] dbl_base;
  reg  [2*N-1:0] pick;

  wire [N-1:0] gnt_pick;

  // ===== Base register (round-robin pointer) =====
  always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // initialize pointer as 1-hot at bit 0
      post_base <= {{(N-1){1'b0}}, 1'b1};
    end else begin
      post_base <= pre_base;
    end
  end

  // ===== Combinational choose-next (read-first) =====
  always @* begin
    // replicate requests to handle wrap-around window
    dbl_req  = {req, req};
    // align base to the lower half; upper half zeros
    dbl_base = {{(N){1'b0}}, post_base};
    // first-one detect after base (classic trick: x & ~(x - base))
    pick     = dbl_req & ~(dbl_req - dbl_base);
  end

  assign gnt_pick = pick[N-1:0] | pick[2*N-1:N]; // fold upper half back
  assign gnt      = gnt_pick;
  assign gnt_flag = |gnt_pick;

  // ===== Next base (rotate one-hot after a grant) =====
  always @* begin
    if (gnt_flag) begin
      // rotate granted bit left by 1 to form next base
      pre_base = {gnt_pick[N-2:0], gnt_pick[N-1]};
    end else begin
      // no request -> hold base
      pre_base = post_base;
    end
  end

endmodule

`default_nettype wire

