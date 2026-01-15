`include "./src/systolic_array_os.sv"
`timescale 1ns/1ps

module systolic_wrapper #(
  parameter int M=8, N=8
)(
  input  logic clk, rst,
  input  logic start,
  input  logic done_clear,
  input  logic [15:0] K,

  input  logic [31:0] a_row_in [M],
  input  logic [31:0] b_col_in [N],

  output logic busy,
  output logic done,

  output logic [31:0] c_out [M][N],
  output logic c_valid [M][N]
);

  // regs to feed systolic_array_os
  logic        step_valid;
  logic [31:0] a_row [M];
  logic [31:0] b_col [N];
  logic        k_first, k_last;
  logic        step_ready;

  systolic_array_os #(.M(M), .N(N)) u_sa (
    .clk(clk), .rst(rst),
    .step_valid(step_valid),
    .a_row(a_row), .b_col(b_col),
    .k_first(k_first), .k_last(k_last),
    .step_ready(step_ready),
    .c_out(c_out),
    .c_valid(c_valid)
  );

  // start pulse
  logic start_q;
  wire start_pulse = start & ~start_q;
  always_ff @(posedge clk) start_q <= start;

  logic [15:0] k_idx, K_lat;

  typedef enum logic [2:0] {W_IDLE, W_PREP, W_LAUNCH, W_WAIT_LAST, W_DONE} wst_t;
  wst_t st;

  assign busy = (st != W_IDLE) && (st != W_DONE);
  assign done = (st == W_DONE);

  always_ff @(posedge clk) begin
    if (rst) begin
      st <= W_IDLE;
      step_valid <= 1'b0;
      k_idx <= 0;
      K_lat <= 0;
      k_first <= 1'b0;
      k_last  <= 1'b0;
      for (int i=0;i<M;i++) a_row[i] <= 32'h0;
      for (int j=0;j<N;j++) b_col[j] <= 32'h0;
    end else begin
      step_valid <= 1'b0; // default pulse low

      case (st)
        W_IDLE: begin
          k_idx <= 0;
          if (start_pulse) begin
            K_lat <= K;
            if (K == 0) st <= W_DONE;
            else        st <= W_PREP;
          end
        end

        // PREP: latch inputs one full cycle BEFORE valid
        W_PREP: begin
          if (step_ready) begin
            for (int i=0;i<M;i++) a_row[i] <= a_row_in[i];
            for (int j=0;j<N;j++) b_col[j] <= b_col_in[j];
            k_first <= (k_idx == 0);
            k_last  <= (k_idx == (K_lat-1));
            st <= W_LAUNCH;
          end
        end

        // LAUNCH: pulse valid 1 cycle
        W_LAUNCH: begin
          step_valid <= 1'b1;
          if (k_idx == (K_lat-1)) begin
            st <= W_WAIT_LAST;
          end else begin
            k_idx <= k_idx + 1;
            st <= W_PREP;
          end
        end

        // wait until array returns idle after last step
        W_WAIT_LAST: begin
          if (step_ready) st <= W_DONE;
        end

        W_DONE: begin
          if (done_clear) st <= W_IDLE;
        end
      endcase
    end
  end

endmodule

