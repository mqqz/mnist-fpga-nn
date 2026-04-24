`include "rtl/protocol.vh"

module tb_controller (
    input wire clk
);
  reg reset;
  reg [7:0] rx_data;
  reg rx_data_valid;
  wire rx_data_ready;

  wire [7:0] tx_data;
  wire tx_data_valid;
  reg tx_data_ready;

  wire input_we;
  wire [1:0] input_addr;
  wire [7:0] input_data;

  wire mlp_start;
  reg mlp_busy;
  reg mlp_done;

  reg [0:0] class_id;
  reg signed [31:0] class_score;
  wire [0:0] logit_addr;
  wire signed [31:0] logit_data;

  wire image_loaded;
  wire result_valid;
  wire [2:0] state_debug;

  reg [7:0] loaded[0:3];
  reg [7:0] sent[0:15];
  integer sent_count;
  integer step;

  assign logit_data = (logit_addr == 1'd0) ? 32'h0102_0304 : 32'hffff_fff0;

  controller #(
      .IMAGE_SIZE(4),
      .OUTPUT_SIZE(2),
      .INPUT_ADDR_W(2),
      .OUTPUT_ADDR_W(1)
  ) dut (
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
      .image_loaded(image_loaded),
      .result_valid(result_valid),
      .state_debug(state_debug)
  );

  initial begin
    reset = 1'b1;
    rx_data = 8'd0;
    rx_data_valid = 1'b0;
    tx_data_ready = 1'b1;
    mlp_busy = 1'b0;
    mlp_done = 1'b0;
    class_id = 1'b1;
    class_score = 32'h1234_abcd;
    loaded[0] = 8'd0;
    loaded[1] = 8'd0;
    loaded[2] = 8'd0;
    loaded[3] = 8'd0;
    sent[0] = 8'd0;
    sent[1] = 8'd0;
    sent[2] = 8'd0;
    sent[3] = 8'd0;
    sent[4] = 8'd0;
    sent[5] = 8'd0;
    sent[6] = 8'd0;
    sent[7] = 8'd0;
    sent[8] = 8'd0;
    sent[9] = 8'd0;
    sent[10] = 8'd0;
    sent[11] = 8'd0;
    sent[12] = 8'd0;
    sent[13] = 8'd0;
    sent[14] = 8'd0;
    sent[15] = 8'd0;
    sent_count = 0;
    step = 0;
  end

  always @(posedge clk) begin
    if (input_we) begin
      loaded[input_addr] <= input_data;
    end

    if (tx_data_valid) begin
      sent[sent_count] <= tx_data;
      sent_count <= sent_count + 1;
    end
  end

  always @(posedge clk) begin
    rx_data_valid <= 1'b0;
    mlp_done <= 1'b0;

    case (step)
      0: begin
        reset <= 1'b0;
        step <= 1;
      end

      1: begin
        if (rx_data_ready !== 1'b1) begin
          $display("[FAIL] controller expected ready in IDLE");
          $fatal(1);
        end

        rx_data <= `CMD_LOAD_INPUT;
        rx_data_valid <= 1'b1;
        step <= 2;
      end

      2: begin
        rx_data <= 8'h11;
        rx_data_valid <= 1'b1;
        step <= 3;
      end

      3: begin
        rx_data <= 8'h22;
        rx_data_valid <= 1'b1;
        step <= 4;
      end

      4: begin
        rx_data <= 8'h80;
        rx_data_valid <= 1'b1;
        step <= 5;
      end

      5: begin
        rx_data <= 8'hff;
        rx_data_valid <= 1'b1;
        step <= 6;
      end

      6, 7, 8: begin
        step <= step + 1;
      end

      9: begin
        if (image_loaded !== 1'b1 || sent[0] !== `RESP_LOAD_DONE) begin
          $display("[FAIL] controller expected LOAD_DONE after image load");
          $fatal(1);
        end

        if (loaded[0] !== 8'h11 || loaded[1] !== 8'h22 ||
            loaded[2] !== 8'h80 || loaded[3] !== 8'hff) begin
          $display("[FAIL] controller input load mismatch [%0h %0h %0h %0h]",
                   loaded[0], loaded[1], loaded[2], loaded[3]);
          $fatal(1);
        end

        rx_data <= `CMD_RUN;
        rx_data_valid <= 1'b1;
        step <= 10;
      end

      10: begin
        step <= 11;
      end

      11: begin
        if (mlp_start !== 1'b1) begin
          $display("[FAIL] controller expected mlp_start on RUN");
          $fatal(1);
        end

        mlp_busy <= 1'b1;
        step <= 12;
      end

      12: begin
        mlp_busy <= 1'b1;
        step <= 13;
      end

      13: begin
        if (state_debug !== 3'd3) begin
          $display("[FAIL] controller expected WAIT_RUN state got %0d", state_debug);
          $fatal(1);
        end

        mlp_busy <= 1'b0;
        mlp_done <= 1'b1;
        step <= 14;
      end

      14, 15, 16: begin
        step <= step + 1;
      end

      17: begin
        if (result_valid !== 1'b1 || sent[1] !== `RESP_RUN_DONE) begin
          $display("[FAIL] controller expected RUN_DONE and result_valid");
          $fatal(1);
        end

        rx_data <= `CMD_READ_OUTPUT;
        rx_data_valid <= 1'b1;
        step <= 18;
      end

      18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33: begin
        step <= step + 1;
      end

      34: begin
        if (sent_count !== 16) begin
          $display("[FAIL] controller expected 16 tx bytes got %0d", sent_count);
          $fatal(1);
        end

        if (sent[2] !== `RESP_OUTPUT || sent[3] !== 8'h01 ||
            sent[4] !== 8'hcd || sent[5] !== 8'hab ||
            sent[6] !== 8'h34 || sent[7] !== 8'h12 ||
            sent[8] !== 8'h04 || sent[9] !== 8'h03 ||
            sent[10] !== 8'h02 || sent[11] !== 8'h01 ||
            sent[12] !== 8'hf0 || sent[13] !== 8'hff ||
            sent[14] !== 8'hff || sent[15] !== 8'hff) begin
          $display("[FAIL] controller output frame mismatch");
          $fatal(1);
        end

        $display("[PASS] controller protocol loads input, runs MLP, and sends logits");
        $finish;
      end
    endcase
  end
endmodule
