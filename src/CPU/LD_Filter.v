`define LB 3'b000
`define LH 3'b001
`define LW 3'b010
`define LBU 3'b100
`define LHU 3'b101

module LD_Filter (
    input      [ 2:0] func3,
    input      [31:0] ld_data,
    output reg [31:0] ld_data_f
);
  always @(*) begin
    case (func3)
      `LB:     ld_data_f <= {{25{ld_data[7]}}, ld_data[6:0]};
      `LH:     ld_data_f <= {{17{ld_data[15]}}, ld_data[14:0]};
      `LW:     ld_data_f <= ld_data;
      `LBU:    ld_data_f <= {24'b0, ld_data[7:0]};
      `LHU:    ld_data_f <= {16'b0, ld_data[15:0]};
      default: ld_data_f <= 32'bx;
    endcase
  end
endmodule
