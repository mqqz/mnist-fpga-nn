module relu #(
    parameter REQUANT_MULT = 1,
    parameter REQUANT_SHIFT = 0
) (
    input  wire               clk,
    input  wire               valid_in,
    input  wire signed [31:0] in_data,
    output reg signed  [31:0] out_data,
    output reg signed  [ 7:0] out_q8
);
  function signed [7:0] requant_relu;
    input signed [31:0] value;
    reg signed [63:0] rounded;
    reg signed [63:0] scaled;
    begin
      if (value <= 0) begin
        requant_relu = 8'sd0;
      end else if (REQUANT_SHIFT == 0) begin
        if (value > 32'sd127) requant_relu = 8'sd127;
        else requant_relu = value[7:0];
      end else begin
        rounded = (value * REQUANT_MULT) + (64'sd1 <<< (REQUANT_SHIFT - 1));
        scaled  = rounded >>> REQUANT_SHIFT;

        if (scaled > 64'sd127) requant_relu = 8'sd127;
        else requant_relu = scaled[7:0];
      end
    end
  endfunction

  always @(posedge clk) begin
    if (valid_in) begin
      if (in_data[31] == 0) begin
        out_data <= in_data;
      end else begin
        out_data <= 0;
      end

      out_q8 <= requant_relu(in_data);
    end
  end
endmodule
