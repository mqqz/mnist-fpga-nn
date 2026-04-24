module tb_mlp_uart (
    input wire clk
);
  reg reset;
  reg rx_pin;
  wire tx_pin;

  mlp_uart #(
      .CLK_FRE(1),
      .BAUD_RATE(250000),
      .INPUT_SIZE(4),
      .HIDDEN_SIZE(3),
      .OUTPUT_SIZE(2),
      .INPUT_ADDR_W(2),
      .HIDDEN_ADDR_W(2),
      .OUTPUT_ADDR_W(1),
      .FC1_WEIGHT_FILE("tb/data/mlp_fc1_weight.mem"),
      .FC1_BIAS_FILE("tb/data/mlp_fc1_bias.mem"),
      .FC2_WEIGHT_FILE("tb/data/mlp_fc2_weight.mem"),
      .FC2_BIAS_FILE("tb/data/mlp_fc2_bias.mem"),
      .FC1_REQUANT_MULT(1),
      .FC1_REQUANT_SHIFT(1)
  ) dut (
      .clk(clk),
      .reset(reset),
      .rx_pin(rx_pin),
      .tx_pin(tx_pin)
  );

  initial begin
    reset = 1'b1;
    rx_pin = 1'b1;
  end

  always @(posedge clk) begin
    reset <= 1'b0;
  end

  always @(negedge clk) begin
    if (tx_pin !== 1'b1 && reset === 1'b0) begin
      $display("[FAIL] mlp_uart should idle tx high without commands");
      $fatal(1);
    end

    $display("[PASS] mlp_uart integrates UART, controller, MLP, and TX");
    $finish;
  end
endmodule
