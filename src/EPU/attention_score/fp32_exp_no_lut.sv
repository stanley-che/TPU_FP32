`ifndef FP32_EXP_NO_LUT_SV
`define FP32_EXP_NO_LUT_SV
`include "./src/EPU/attention_score/fp_adder_driver_ba.sv"
`include "./src/EPU/attention_score/fp_mul_driver.sv"
`timescale 1ns/1ps
`default_nettype none

module fp32_exp_no_lut (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        in_valid,
  input  logic [31:0] in_fp32,

  output logic        out_valid,
  output logic [31:0] out_fp32
);

  // ----------------------------
  // constants (FP32)
  // ----------------------------
  localparam logic [31:0] FP32_ONE   = 32'h3f800000;
  localparam logic [31:0] FP32_LOG2E = 32'h3fb8aa3b;
  localparam logic [31:0] FP32_LN2   = 32'h3f317218;

  localparam logic [31:0] C2 = 32'h3f000000; // 0.5
  localparam logic [31:0] C3 = 32'h3e2aaaab; // 1/6
  localparam logic [31:0] C4 = 32'h3d2aaaab; // 1/24
  localparam logic [31:0] C5 = 32'h3c088889; // 1/120

  // ----------------------------
  // helpers
  // ----------------------------
  function automatic logic [31:0] fp32_neg(input logic [31:0] x);
    fp32_neg = {~x[31], x[30:0]};
  endfunction

  function automatic int fp32_to_int_floor(input logic [31:0] f);
    logic sign;
    int   exp_u, exp;
    logic [23:0] mant;
    int   shift;
    int   val;
    begin
      sign  = f[31];
      exp_u = f[30:23];
      if (exp_u == 0) begin
        fp32_to_int_floor = (sign && (f[22:0]!=0)) ? -1 : 0;
      end else if (exp_u == 8'hFF) begin
        fp32_to_int_floor = sign ? -2147483648 : 2147483647;
      end else begin
        exp  = exp_u - 127;
        mant = {1'b1, f[22:0]};
        shift = exp - 23;

        if (exp < 0) begin
          fp32_to_int_floor = sign ? -1 : 0;
        end else if (exp > 30) begin
          fp32_to_int_floor = sign ? -2147483648 : 2147483647;
        end else begin
          if (shift >= 0) val = (mant << shift);
          else            val = (mant >> (-shift));

          if (!sign) begin
            fp32_to_int_floor = val;
          end else begin
            if (shift < 0) begin
              int frac_mask;
              frac_mask = (1 << (-shift)) - 1;
              fp32_to_int_floor = -val - (((mant & frac_mask) != 0) ? 1 : 0);
            end else begin
              fp32_to_int_floor = -val;
            end
          end
        end
      end
    end
  endfunction

  function automatic logic [31:0] fp32_pow2_int(input int n);
    int e;
    begin
      e = n + 127;
      if (e <= 0)        fp32_pow2_int = 32'h0000_0000;
      else if (e >= 255) fp32_pow2_int = 32'h7f80_0000;
      else               fp32_pow2_int = {1'b0, e[7:0], 23'd0};
    end
  endfunction

  function automatic logic [31:0] int_to_fp32_bits(input int n);
    logic sign;
    int   a;
    int   p;
    int   exp_u;
    logic [55:0] norm;
    logic [23:0] mant24;
    begin
      if (n == 0) begin
        int_to_fp32_bits = 32'h0000_0000;
      end else begin
        sign = (n < 0);
        a    = sign ? -n : n;

        p = 31;
        while (p > 0 && (((a >> p) & 1) == 0)) p--;

        exp_u = p + 127;
        if (exp_u <= 0) begin
          int_to_fp32_bits = 32'h0000_0000;
        end else if (exp_u >= 255) begin
          int_to_fp32_bits = sign ? 32'hff80_0000 : 32'h7f80_0000;
        end else begin
          norm = a;
          if (p > 23) norm = norm >> (p - 23);
          else        norm = norm << (23 - p);

          mant24 = norm[23:0];
          int_to_fp32_bits = {sign, exp_u[7:0], mant24[22:0]};
        end
      end
    end
  endfunction

  // ----------------------------
  // FP mul / add drivers
  // ----------------------------
  logic        mul_start, mul_busy, mul_done;
  logic [31:0] mul_a, mul_b, mul_z;

  logic        add_start, add_busy, add_done;
  logic [31:0] add_a, add_b, add_z;

  fp_mul_driver u_mul (
    .clk    (clk),
    .rst    (~rst_n),
    .start  (mul_start),
    .a_bits (mul_a),
    .b_bits (mul_b),
    .busy   (mul_busy),
    .done   (mul_done),
    .z_bits (mul_z)
  );

  fp_adder_driver_ba u_add (
    .clk    (clk),
    .rst    (~rst_n),
    .start  (add_start),
    .a_bits (add_a),
    .b_bits (add_b),
    .busy   (add_busy),
    .done   (add_done),
    .z_bits (add_z)
  );

  // ----------------------------
  // unified request handshakes
  // ----------------------------
  logic mul_req, add_req;
  assign mul_start = mul_req;
  assign add_start = add_req;

  // ----------------------------
  // FSM states
  // ----------------------------
  typedef enum logic [4:0] {
    S_IDLE,

    S_T_MUL_ISSUE,   S_T_MUL_WAIT,
    S_F_SUB_ISSUE,   S_F_SUB_WAIT,
    S_U_MUL_ISSUE,   S_U_MUL_WAIT,

    S_H1_MUL_ISSUE,  S_H1_MUL_WAIT,  S_H1_ADD_ISSUE,  S_H1_ADD_WAIT,
    S_H2_MUL_ISSUE,  S_H2_MUL_WAIT,  S_H2_ADD_ISSUE,  S_H2_ADD_WAIT,
    S_H3_MUL_ISSUE,  S_H3_MUL_WAIT,  S_H3_ADD_ISSUE,  S_H3_ADD_WAIT,
    S_H4_MUL_ISSUE,  S_H4_MUL_WAIT,  S_H4_ADD_ISSUE,  S_H4_ADD_WAIT,

    S_E_MUL_ISSUE,   S_E_MUL_WAIT,   S_E_ADD_ISSUE,   S_E_ADD_WAIT,

    S_SCALE_MUL_ISSUE, S_SCALE_MUL_WAIT,
    S_DONE
  } state_t;

  state_t st;

  // regs
  logic [31:0] x_fp, t_fp, f_fp, u_fp;
  logic [31:0] n_fp, pow2n_fp;
  logic [31:0] h_fp, e_fp;

  // ----------------------------
  // sequential
  // ----------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st        <= S_IDLE;
      out_valid <= 1'b0;
      out_fp32  <= 32'd0;

      x_fp      <= 32'd0;
      t_fp      <= 32'd0;
      f_fp      <= 32'd0;
      u_fp      <= 32'd0;
      n_fp      <= 32'd0;
      pow2n_fp  <= 32'd0;
      h_fp      <= C5;
      e_fp      <= 32'd0;

      mul_req   <= 1'b0;
      add_req   <= 1'b0;
      mul_a     <= 32'd0;
      mul_b     <= 32'd0;
      add_a     <= 32'd0;
      add_b     <= 32'd0;

    end else begin
      out_valid <= 1'b0;

      case (st)
        // accept input
        S_IDLE: begin
          if (in_valid) begin
            x_fp <= in_fp32;
            st   <= S_T_MUL_ISSUE;
          end
        end

        // ---------------- t = x * log2e ----------------
        S_T_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= x_fp;
            mul_b   <= FP32_LOG2E;
            mul_req <= 1'b1;           // hold start until busy rises
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;           // accepted
            st      <= S_T_MUL_WAIT;
          end
        end

        S_T_MUL_WAIT: begin
          if (mul_done) begin
            int n;
            t_fp <= mul_z;
            n    = fp32_to_int_floor(mul_z);
            n_fp <= int_to_fp32_bits(n);
            pow2n_fp <= fp32_pow2_int(n);
            st   <= S_F_SUB_ISSUE;
          end
        end

        // ---------------- f = t - n ----------------
        S_F_SUB_ISSUE: begin
          if (!add_req && !add_busy) begin
            add_a   <= t_fp;
            add_b   <= fp32_neg(n_fp);
            add_req <= 1'b1;
          end
          if (add_req && add_busy) begin
            add_req <= 1'b0;
            st      <= S_F_SUB_WAIT;
          end
        end

        S_F_SUB_WAIT: begin
          if (add_done) begin
            f_fp <= add_z;
            st   <= S_U_MUL_ISSUE;
          end
        end

        // ---------------- u = f * ln2 ----------------
        S_U_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= f_fp;
            mul_b   <= FP32_LN2;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_U_MUL_WAIT;
          end
        end

        S_U_MUL_WAIT: begin
          if (mul_done) begin
            u_fp <= mul_z;
            h_fp <= C5;
            st   <= S_H1_MUL_ISSUE;
          end
        end

        // ---------------- h = C4 + u*h ----------------
        S_H1_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= u_fp;
            mul_b   <= h_fp;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_H1_MUL_WAIT;
          end
        end
        S_H1_MUL_WAIT: begin
          if (mul_done) begin
            st <= S_H1_ADD_ISSUE;
          end
        end
        S_H1_ADD_ISSUE: begin
          if (!add_req && !add_busy) begin
            add_a   <= C4;
            add_b   <= mul_z;
            add_req <= 1'b1;
          end
          if (add_req && add_busy) begin
            add_req <= 1'b0;
            st      <= S_H1_ADD_WAIT;
          end
        end
        S_H1_ADD_WAIT: begin
          if (add_done) begin
            h_fp <= add_z;
            st   <= S_H2_MUL_ISSUE;
          end
        end

        // ---------------- h = C3 + u*h ----------------
        S_H2_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= u_fp;
            mul_b   <= h_fp;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_H2_MUL_WAIT;
          end
        end
        S_H2_MUL_WAIT: begin
          if (mul_done) begin
            st <= S_H2_ADD_ISSUE;
          end
        end
        S_H2_ADD_ISSUE: begin
          if (!add_req && !add_busy) begin
            add_a   <= C3;
            add_b   <= mul_z;
            add_req <= 1'b1;
          end
          if (add_req && add_busy) begin
            add_req <= 1'b0;
            st      <= S_H2_ADD_WAIT;
          end
        end
        S_H2_ADD_WAIT: begin
          if (add_done) begin
            h_fp <= add_z;
            st   <= S_H3_MUL_ISSUE;
          end
        end

        // ---------------- h = C2 + u*h ----------------
        S_H3_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= u_fp;
            mul_b   <= h_fp;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_H3_MUL_WAIT;
          end
        end
        S_H3_MUL_WAIT: begin
          if (mul_done) begin
            st <= S_H3_ADD_ISSUE;
          end
        end
        S_H3_ADD_ISSUE: begin
          if (!add_req && !add_busy) begin
            add_a   <= C2;
            add_b   <= mul_z;
            add_req <= 1'b1;
          end
          if (add_req && add_busy) begin
            add_req <= 1'b0;
            st      <= S_H3_ADD_WAIT;
          end
        end
        S_H3_ADD_WAIT: begin
          if (add_done) begin
            h_fp <= add_z;
            st   <= S_H4_MUL_ISSUE;
          end
        end

        // ---------------- h = 1 + u*h ----------------
        S_H4_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= u_fp;
            mul_b   <= h_fp;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_H4_MUL_WAIT;
          end
        end
        S_H4_MUL_WAIT: begin
          if (mul_done) begin
            st <= S_H4_ADD_ISSUE;
          end
        end
        S_H4_ADD_ISSUE: begin
          if (!add_req && !add_busy) begin
            add_a   <= FP32_ONE;
            add_b   <= mul_z;
            add_req <= 1'b1;
          end
          if (add_req && add_busy) begin
            add_req <= 1'b0;
            st      <= S_H4_ADD_WAIT;
          end
        end
        S_H4_ADD_WAIT: begin
          if (add_done) begin
            h_fp <= add_z;
            st   <= S_E_MUL_ISSUE;
          end
        end

        // ---------------- e = 1 + u*h ----------------
        S_E_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= u_fp;
            mul_b   <= h_fp;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_E_MUL_WAIT;
          end
        end
        S_E_MUL_WAIT: begin
          if (mul_done) begin
            st <= S_E_ADD_ISSUE;
          end
        end
        S_E_ADD_ISSUE: begin
          if (!add_req && !add_busy) begin
            add_a   <= FP32_ONE;
            add_b   <= mul_z;
            add_req <= 1'b1;
          end
          if (add_req && add_busy) begin
            add_req <= 1'b0;
            st      <= S_E_ADD_WAIT;
          end
        end
        S_E_ADD_WAIT: begin
          if (add_done) begin
            e_fp <= add_z;
            st   <= S_SCALE_MUL_ISSUE;
          end
        end

        // ---------------- out = 2^n * e ----------------
        S_SCALE_MUL_ISSUE: begin
          if (!mul_req && !mul_busy) begin
            mul_a   <= pow2n_fp;
            mul_b   <= e_fp;
            mul_req <= 1'b1;
          end
          if (mul_req && mul_busy) begin
            mul_req <= 1'b0;
            st      <= S_SCALE_MUL_WAIT;
          end
        end
        S_SCALE_MUL_WAIT: begin
          if (mul_done) begin
            out_fp32 <= mul_z;
            st       <= S_DONE;
          end
        end

        S_DONE: begin
          out_valid <= 1'b1;
          st        <= S_IDLE;
        end

        default: st <= S_IDLE;
      endcase
    end
  end

endmodule

`default_nettype wire
`endif