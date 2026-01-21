/*
=============================================================================
  fp_adder_driver.sv
  - Author : Shao Wei Chen
  - Goal :
    * Provide a fully IEEE-754 compliant single-precision (FP32)
      floating-point addition operation
    * Correctly handle NaN, Infinity, Zero, and Denormal numbers
    * Serve as a golden reference for FP32 arithmetic verification

  - Architecture :
    * FSM-based serial floating-point adder
    * One operation processed at a time
    * Variable latency depending on data values

  - Characteristics :
    * Exponent alignment performed by 1-bit right shift per cycle
    * Leading-zero normalization performed by 1-bit left shift per cycle
    * Round-to-nearest-even rounding using Guard / Round / Sticky (GRS) bits
    * Fully deterministic and bit-accurate behavior

  - Suitable for :
    * Golden reference computation
    * Functional verification of FP32 datapaths
    * Educational and research purposes
    * Control-dominated or low-throughput designs

  - Not suitable for :
    * Softmax / Attention inner loops
    * AI accelerators and high-throughput datapaths
    * Performance-critical numerical workloads

  ----------------------------------------------------------------------------
  Description:
    Floating-point adder driver wrapper for an FSM-based IEEE-754 FP32
    serial floating-point adder.

    This module converts a low-level stb/ack handshake interface into a
    simplified start / busy / done control interface.

  ----------------------------------------------------------------------------
  FUNCTIONAL OVERVIEW
  ----------------------------------------------------------------------------
    - Accepts one FP32 addition request at a time
    - Internally performs:
        * Send operand A via stb/ack
        * Send operand B via stb/ack
        * Wait for result Z via stb
    - Returns result using a sticky 'done' signal

  ----------------------------------------------------------------------------
  INPUT SIGNALS
  ----------------------------------------------------------------------------
    clk :
      - System clock

    rst :
      - Active-high synchronous reset
      - Resets internal FSM to IDLE
      - Clears busy and done flags

    start :
      - Start request signal
      - Sampled only when busy == 0 (IDLE state)
      - Recommended usage:
          * Assert for exactly 1 clock cycle (pulse)
      - Level assertion is allowed, but must be deasserted once busy == 1

    a_bits [31:0] :
      - IEEE-754 single-precision floating-point operand A
      - Format:
          [31]    Sign
          [30:23] Exponent (bias = 127)
          [22:0]  Fraction (mantissa)

    b_bits [31:0] :
      - IEEE-754 single-precision floating-point operand B
      - Same format as a_bits

  ----------------------------------------------------------------------------
  OUTPUT SIGNALS
  ----------------------------------------------------------------------------
    busy :
      - Indicates an operation is in progress
      - busy == 1 : driver is processing a request
      - busy == 0 : driver is idle and can accept a new start

    done :
      - Completion indicator (LEVEL, sticky)
      - Asserted when the FP32 addition result is available
      - Remains high until a new start request is accepted
      - Must NOT be treated as a pulse

    z_bits [31:0] :
      - IEEE-754 single-precision floating-point result (A + B)
      - Valid when done == 1
      - Remains stable while done == 1

  ----------------------------------------------------------------------------
  OPERATION SEQUENCE (RECOMMENDED USAGE)
  ----------------------------------------------------------------------------
    1) Wait until busy == 0
    2) Drive a_bits and b_bits with valid FP32 operands
    3) Assert start for exactly 1 clock cycle
    4) Wait until done == 1
    5) Read z_bits
    6) Repeat for next operation

  ----------------------------------------------------------------------------
  TIMING AND PERFORMANCE NOTES
  ----------------------------------------------------------------------------
    - Only one operation can be processed at a time
    - Latency is variable and depends on:
        * Exponent difference (alignment stage)
        * Number of leading zeros (normalization stage)
    - No output backpressure:
        * Internal output_z_ack is tied to 1'b1

  ----------------------------------------------------------------------------
  INTENDED USE CASES
  ----------------------------------------------------------------------------
    - Golden reference computation
    - Functional verification of FP32 datapaths
    - Control-dominated or low-throughput designs

  ----------------------------------------------------------------------------
  NOT RECOMMENDED FOR
  ----------------------------------------------------------------------------
    - High-throughput datapaths
    - Softmax / Attention inner loops
    - AI accelerator arithmetic cores

=============================================================================
*/

`ifndef FP_ADDER_DRIVER_SV
`define FP_ADDER_DRIVER_SV
// Floating-point adder driver
// Wraps around adder module
// Provides simple start/done handshake interface
// parameterized for 32-bit single-precision FP
`include "./src/EPU/attention_score/adder.sv"
`timescale 1ns/1ps
module fp_adder_driver (
    input  logic        clk,
    input  logic        rst,        // active-high reset (sync)

    // request
    input  logic        start,      // pulse or level; sampled when idle
    input  logic [31:0] a_bits,
    input  logic [31:0] b_bits,

    // response
    output logic        busy,
    output logic        done,       // LEVEL: stays 1 until next start accepted
    output logic [31:0] z_bits
);

    // -----------------------------
    // Wires to DUT (stb/ack)
    // -----------------------------
    logic [31:0] dut_input_a, dut_input_b;
    logic        dut_input_a_stb, dut_input_b_stb;
    wire         dut_input_a_ack,dut_input_b_ack;
    wire  [31:0] dut_output_z;
    wire         dut_output_z_stb,dut_output_z_ack;

    assign dut_output_z_ack = 1'b1;  // always ready (no backpressure)

    adder dut (
        .input_a      (dut_input_a),
        .input_b      (dut_input_b),
        .input_a_stb  (dut_input_a_stb),
        .input_b_stb  (dut_input_b_stb),
        .output_z_ack (dut_output_z_ack),
        .clk          (clk),
        .rst          (rst),
        .output_z     (dut_output_z),
        .output_z_stb (dut_output_z_stb),
        .input_a_ack  (dut_input_a_ack),
        .input_b_ack  (dut_input_b_ack)
    );

    // -----------------------------
    // Driver FSM
    // -----------------------------
    typedef enum logic [1:0] {
        IDLE   = 2'd0,
        SEND_A = 2'd1,
        SEND_B = 2'd2,
        WAIT_Z = 2'd3
    } state_t;

    state_t state;

    logic [31:0] a_lat, b_lat;

    always_comb begin
        busy = (state != IDLE);
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state           <= IDLE;
            a_lat           <= 32'd0;
            b_lat           <= 32'd0;

            dut_input_a     <= 32'd0;
            dut_input_b     <= 32'd0;
            dut_input_a_stb <= 1'b0;
            dut_input_b_stb <= 1'b0;

            z_bits          <= 32'd0;
            done            <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    dut_input_a_stb <= 1'b0;
                    dut_input_b_stb <= 1'b0;

                    if (start) begin
                        // accept new request → clear done
                        done  <= 1'b0;

                        a_lat <= a_bits;
                        b_lat <= b_bits;

                        dut_input_a <= a_bits;
                        dut_input_b <= b_bits;

                        dut_input_a_stb <= 1'b1;
                        state <= SEND_A;
                    end
                end

                SEND_A: begin
                    dut_input_a <= a_lat;
                    if (dut_input_a_ack && dut_input_a_stb) begin
                        dut_input_a_stb <= 1'b0;
                        dut_input_b_stb <= 1'b1;
                        state <= SEND_B;
                    end
                end

                SEND_B: begin
                    dut_input_b <= b_lat;
                    if (dut_input_b_ack && dut_input_b_stb) begin
                        dut_input_b_stb <= 1'b0;
                        state <= WAIT_Z;
                    end
                end

                WAIT_Z: begin
                    if (dut_output_z_stb) begin
                        z_bits <= dut_output_z;
                        done   <= 1'b1;   // sticky
                        state  <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
`endif