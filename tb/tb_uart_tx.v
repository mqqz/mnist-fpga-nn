module tb_uart_tx (
    input wire clk
);
  localparam integer CLK_FRE = 1;
  localparam integer BAUD_RATE = 250000;

  reg rst_n;
  reg [7:0] tx_data;
  reg tx_data_valid;
  wire tx_data_ready;
  wire tx_pin;

  integer step;

  uart_tx #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .tx_data(tx_data),
      .tx_data_valid(tx_data_valid),
      .tx_data_ready(tx_data_ready),
      .tx_pin(tx_pin)
  );

  task expect_line;
    input expected_value;
    input integer phase;
    begin
      if (tx_pin !== expected_value) begin
        $display("[FAIL] uart_tx phase=%0d expected=%0b got=%0b",
                 phase, expected_value, tx_pin);
        $fatal(1);
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    tx_data = 8'hA5;
    tx_data_valid = 1'b0;
    step = 0;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        rst_n <= 1'b1;
        step <= 1;
      end
      1: begin
        step <= 2;
      end
      2: begin
        if (tx_data_ready !== 1'b1) begin
          $display("[FAIL] uart_tx expected idle ready");
          $fatal(1);
        end
        tx_data_valid <= 1'b1;
        step <= 3;
      end
      3: begin
        tx_data_valid <= 1'b0;
        step <= 4;
      end
      44: begin
        if (tx_data_ready !== 1'b1) begin
          $display("[FAIL] uart_tx expected ready after frame");
          $fatal(1);
        end
        $display("[PASS] uart_tx serialized one frame correctly");
        $finish;
      end
      default: begin
        step <= step + 1;
      end
    endcase
  end

  always @(negedge clk) begin
    case (step)
      5, 6, 7, 8: expect_line(1'b0, step - 5);
      9, 10, 11, 12: expect_line(tx_data[0], 1);
      13, 14, 15, 16: expect_line(tx_data[1], 2);
      17, 18, 19, 20: expect_line(tx_data[2], 3);
      21, 22, 23, 24: expect_line(tx_data[3], 4);
      25, 26, 27, 28: expect_line(tx_data[4], 5);
      29, 30, 31, 32: expect_line(tx_data[5], 6);
      33, 34, 35, 36: expect_line(tx_data[6], 7);
      37, 38, 39, 40: expect_line(tx_data[7], 8);
      41, 42, 43, 44: expect_line(1'b1, 9);
    endcase
  end
endmodule
