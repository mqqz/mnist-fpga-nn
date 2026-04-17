module top #(
    parameter CLK_FRE = 50,
    parameter BAUD_RATE = 115200,
    parameter INPUT_SIZE = 784,
    parameter HIDDEN_SIZE = 32,
    parameter OUTPUT_SIZE = 10,
    parameter INPUT_ADDR_W = 10,
    parameter HIDDEN_ADDR_W = 5,
    parameter OUTPUT_ADDR_W = 4,
    parameter FC1_WEIGHT_FILE = "mem/fc1_weight.mem",
    parameter FC1_BIAS_FILE = "mem/fc1_bias.mem",
    parameter FC2_WEIGHT_FILE = "mem/fc2_weight.mem",
    parameter FC2_BIAS_FILE = "mem/fc2_bias.mem",
    parameter FC1_REQUANT_MULT = 26456,
    parameter FC1_REQUANT_SHIFT = 27
) (
    input  wire clk,
    input  wire reset,
    input  wire rx_pin,
    output wire tx_pin
);
  wire [7:0] rx_data;
  wire rx_data_valid;
  wire rx_data_ready;

  wire [7:0] tx_data;
  wire tx_data_valid;
  wire tx_data_ready;

  wire input_we;
  wire [INPUT_ADDR_W-1:0] input_addr;
  wire [7:0] input_data;

  wire mlp_start;
  wire mlp_busy;
  wire mlp_done;

  wire [OUTPUT_ADDR_W-1:0] class_id;
  wire signed [31:0] class_score;
  wire [OUTPUT_ADDR_W-1:0] logit_addr;
  wire signed [31:0] logit_data;
  wire image_loaded_unused;
  wire result_valid_unused;
  wire [2:0] state_debug_unused;


  uart_rx #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) rx (
      .clk(clk),
      .rst_n(!reset),
      .rx_data(rx_data),
      .rx_data_valid(rx_data_valid),
      .rx_data_ready(rx_data_ready),
      .rx_pin(rx_pin)
  );

  controller #(
      .IMAGE_SIZE(INPUT_SIZE),
      .OUTPUT_SIZE(OUTPUT_SIZE),
      .INPUT_ADDR_W(INPUT_ADDR_W),
      .OUTPUT_ADDR_W(OUTPUT_ADDR_W)
  ) control (
      .clk(clk),
      .reset(reset),
      .rx_data(rx_data),
      .rx_data_valid(rx_data_valid),
      .rx_data_ready(rx_data_ready),
      .tx_data(tx_data),
      .tx_data_valid(tx_data_valid),
      .tx_data_ready(tx_data_ready),
      .input_we(input_we),
      .input_addr(input_addr),
      .input_data(input_data),
      .mlp_start(mlp_start),
      .mlp_busy(mlp_busy),
      .mlp_done(mlp_done),
      .class_id(class_id),
      .class_score(class_score),
      .logit_addr(logit_addr),
      .logit_data(logit_data),
      .image_loaded(image_loaded_unused),
      .result_valid(result_valid_unused),
      .state_debug(state_debug_unused)
  );

  mlp #(
      .INPUT_SIZE(INPUT_SIZE),
      .HIDDEN_SIZE(HIDDEN_SIZE),
      .OUTPUT_SIZE(OUTPUT_SIZE),
      .INPUT_ADDR_W(INPUT_ADDR_W),
      .HIDDEN_ADDR_W(HIDDEN_ADDR_W),
      .OUTPUT_ADDR_W(OUTPUT_ADDR_W),
      .FC1_WEIGHT_FILE(FC1_WEIGHT_FILE),
      .FC1_BIAS_FILE(FC1_BIAS_FILE),
      .FC2_WEIGHT_FILE(FC2_WEIGHT_FILE),
      .FC2_BIAS_FILE(FC2_BIAS_FILE),
      .FC1_REQUANT_MULT(FC1_REQUANT_MULT),
      .FC1_REQUANT_SHIFT(FC1_REQUANT_SHIFT)
  ) core (
      .clk(clk),
      .reset(reset),
      .start(mlp_start),
      .busy(mlp_busy),
      .done(mlp_done),
      .input_we(input_we),
      .input_addr(input_addr),
      .input_data(input_data),
      .logit_addr(logit_addr),
      .logit_data(logit_data),
      .class_id(class_id),
      .class_score(class_score)
  );

  uart_tx #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) tx (
      .clk(clk),
      .rst_n(!reset),
      .tx_data(tx_data),
      .tx_data_valid(tx_data_valid),
      .tx_data_ready(tx_data_ready),
      .tx_pin(tx_pin)
  );
endmodule
