// Simple dense-layer matrix-vector multiplication module.
// The weight and bias inputs are treated as synchronous memory outputs: the
// module drives an address, then consumes the matching data on the next clock.
// Each row is accumulated over IN_SIZE valid data cycles, with an optional
// signed int32 bias added to the row output.
module matvec #(
    parameter IN_SIZE  = 8,
    parameter OUT_SIZE = 4,
    parameter X_ADDR_W = 3,
    parameter Y_ADDR_W = 2,
    parameter W_ADDR_W = 5,
    parameter X_UNSIGNED = 0
) (
    input wire clk,
    input wire reset,
    input wire start,

    output reg         [X_ADDR_W-1:0] x_addr,
    input  wire        [         7:0] x_data,

    output reg         [W_ADDR_W-1:0] w_addr,
    input  wire signed [         7:0] w_data,

    output reg        [Y_ADDR_W-1:0] bias_addr,
    input wire signed [        31:0] bias_data,

    output reg                       y_we,
    output reg        [Y_ADDR_W-1:0] y_addr,
    output reg signed [        31:0] y_data,

    output reg done
);
  localparam integer LAST_COL = IN_SIZE - 1;
  localparam integer LAST_ROW = OUT_SIZE - 1;

  reg running;
  reg priming;
  reg [Y_ADDR_W-1:0] row;
  reg [X_ADDR_W-1:0] col;
  reg signed [31:0] acc;
  wire signed [8:0] x_operand;
  wire signed [31:0] product;
  wire [W_ADDR_W-1:0] row_base_addr;
  wire [W_ADDR_W-1:0] next_row_base_addr;
  wire [31:0] row_u32;

  assign row_u32 = {{(32 - Y_ADDR_W) {1'b0}}, row};
  assign x_operand = X_UNSIGNED ? $signed({1'b0, x_data}) : $signed({x_data[7], x_data});
  assign product = x_operand * w_data;
  assign row_base_addr = W_ADDR_W'(row * IN_SIZE);
  assign next_row_base_addr = W_ADDR_W'((row_u32 + 32'd1) * IN_SIZE);

  always @(posedge clk) begin
    if (reset) begin
      running <= 0;
      priming <= 0;
      row <= 0;
      col <= 0;
      x_addr <= 0;
      w_addr <= 0;
      bias_addr <= 0;
      y_we <= 0;
      y_addr <= 0;
      y_data <= 0;
      done <= 0;
      acc <= 0;
    end else begin
      y_we <= 0;
      done <= 0;

      if (start && !running) begin
        running <= 1;
        priming <= 1;
        row <= 0;
        col <= 0;
        acc <= 0;
        x_addr <= 0;
        w_addr <= 0;
        bias_addr <= 0;
      end else if (running) begin
        if (priming) begin
          priming <= 0;
          if (IN_SIZE > 1) begin
            w_addr <= row_base_addr + W_ADDR_W'(1);
          end
        end else if (col == LAST_COL[X_ADDR_W-1:0]) begin
          y_we <= 1;
          y_addr <= row;
          y_data <= acc + product + bias_data;
          acc <= 0;
          col <= 0;

          if (row == LAST_ROW[Y_ADDR_W-1:0]) begin
            running <= 0;
            priming <= 0;
            done <= 1;
            x_addr <= 0;
            w_addr <= 0;
            bias_addr <= 0;
          end else begin
            row <= row + 1'b1;
            priming <= 1;
            x_addr <= 0;
            w_addr <= next_row_base_addr;
            bias_addr <= row + 1'b1;
          end
        end else begin
          acc <= acc + product;
          col <= col + 1'b1;
          x_addr <= col + 1'b1;
          if (IN_SIZE > 1 && W_ADDR_W'(col) < W_ADDR_W'(IN_SIZE - 2)) begin
            w_addr <= row_base_addr + W_ADDR_W'(col) + W_ADDR_W'(2);
          end
          bias_addr <= row;
        end
      end
    end
  end
endmodule
