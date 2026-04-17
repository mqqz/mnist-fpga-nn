`include "rtl/protocol.vh"

module tb_controller_uart (
    input wire clk
);
  localparam integer CLK_FRE = 1;
  localparam integer BAUD_RATE = 250000;
  localparam integer BIT_CYCLES = 4;
  localparam integer FRAME_TICKS = BIT_CYCLES * 10;
  localparam integer IMAGE_SIZE = 4;

  reg reset;
  reg rx_pin;
  wire [7:0] rx_data;
  wire rx_data_valid;
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

  reg [7:0] loaded[0:IMAGE_SIZE-1];
  reg [7:0] sent[0:0];
  integer sent_count;
  integer step;
  integer frame_tick;
  integer byte_index;
  integer gap_tick;

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
      .IMAGE_SIZE(IMAGE_SIZE),
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

  assign logit_data = 32'sd0;

  function [7:0] stream_byte;
    input integer index;
    begin
      case (index)
        0: stream_byte = `CMD_LOAD_INPUT;
        1: stream_byte = 8'h11;
        2: stream_byte = 8'h22;
        3: stream_byte = 8'h80;
        4: stream_byte = 8'hff;
        default: stream_byte = 8'h00;
      endcase
    end
  endfunction

  function uart_bit_level;
    input [7:0] value;
    input integer tick;
    integer bit_slot;
    begin
      bit_slot = tick / BIT_CYCLES;

      if (bit_slot == 0) uart_bit_level = 1'b0;
      else if (bit_slot >= 1 && bit_slot <= 8) uart_bit_level = value[bit_slot-1];
      else uart_bit_level = 1'b1;
    end
  endfunction

  initial begin
    reset = 1'b1;
    rx_pin = 1'b1;
    tx_data_ready = 1'b1;
    mlp_busy = 1'b0;
    mlp_done = 1'b0;
    class_id = 1'b0;
    class_score = 32'sd0;
    loaded[0] = 8'd0;
    loaded[1] = 8'd0;
    loaded[2] = 8'd0;
    loaded[3] = 8'd0;
    sent[0] = 8'd0;
    sent_count = 0;
    step = 0;
    frame_tick = 0;
    byte_index = 0;
    gap_tick = 0;
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
    case (step)
      0, 1, 2: begin
        reset <= 1'b1;
        rx_pin <= 1'b1;
        step <= step + 1;
      end

      3: begin
        reset <= 1'b0;
        rx_pin <= 1'b1;
        step <= 4;
      end

      4: begin
        if (gap_tick != 0) begin
          rx_pin <= 1'b1;
          gap_tick <= gap_tick - 1;
        end else begin
          rx_pin <= uart_bit_level(stream_byte(byte_index), frame_tick);

          if (frame_tick == FRAME_TICKS - 1) begin
            frame_tick <= 0;
            gap_tick <= 2;

            if (byte_index == IMAGE_SIZE) begin
              byte_index <= byte_index + 1;
              step <= 5;
            end else begin
              byte_index <= byte_index + 1;
            end
          end else begin
            frame_tick <= frame_tick + 1;
          end
        end
      end

      5: begin
        rx_pin <= 1'b1;

        if (image_loaded && state_debug == 3'd0 && sent_count == 1) begin
          step <= 6;
        end
      end

      6: begin
        if (loaded[0] !== 8'h11 || loaded[1] !== 8'h22 ||
            loaded[2] !== 8'h80 || loaded[3] !== 8'hff) begin
          $display("[FAIL] controller_uart input load mismatch [%0h %0h %0h %0h]",
                   loaded[0], loaded[1], loaded[2], loaded[3]);
          $fatal(1);
        end

        if (state_debug !== 3'd0 || rx_data_ready !== 1'b1 ||
            sent_count !== 1 || sent[0] !== `RESP_LOAD_DONE) begin
          $display("[FAIL] controller_uart expected controller back in IDLE/ready");
          $fatal(1);
        end

        $display("[PASS] controller received UART LOAD_INPUT frame and wrote pixels");
        $finish;
      end
    endcase
  end
endmodule
