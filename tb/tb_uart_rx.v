module tb_uart_rx (
    input wire clk
);
  localparam integer CLK_FRE = 1;
  localparam integer BAUD_RATE = 250000;

  reg rst_n;
  reg rx_data_ready;
  reg rx_pin;
  wire [7:0] rx_data;
  wire rx_data_valid;

  integer step;
  reg [7:0] payload;

  uart_rx #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .rx_data(rx_data),
      .rx_data_valid(rx_data_valid),
      .rx_data_ready(rx_data_ready),
      .rx_pin(rx_pin)
  );

  task drive_bit;
    input value;
    begin
      rx_pin <= value;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    rx_data_ready = 1'b0;
    rx_pin = 1'b1;
    payload = 8'h3C;
    step = 0;
  end

  always @(posedge clk) begin
    case (step)
      0, 1: begin
        step <= step + 1;
      end
      2: begin
        rst_n <= 1'b1;
        step <= 3;
      end
      3, 4, 5: begin
        step <= step + 1;
      end
      6, 7, 8, 9: begin
        drive_bit(1'b0);
        step <= step + 1;
      end
      10, 11, 12, 13: begin
        drive_bit(payload[0]);
        step <= step + 1;
      end
      14, 15, 16, 17: begin
        drive_bit(payload[1]);
        step <= step + 1;
      end
      18, 19, 20, 21: begin
        drive_bit(payload[2]);
        step <= step + 1;
      end
      22, 23, 24, 25: begin
        drive_bit(payload[3]);
        step <= step + 1;
      end
      26, 27, 28, 29: begin
        drive_bit(payload[4]);
        step <= step + 1;
      end
      30, 31, 32, 33: begin
        drive_bit(payload[5]);
        step <= step + 1;
      end
      34, 35, 36, 37: begin
        drive_bit(payload[6]);
        step <= step + 1;
      end
      38, 39, 40, 41: begin
        drive_bit(payload[7]);
        step <= step + 1;
      end
      42, 43, 44, 45: begin
        drive_bit(1'b1);
        step <= step + 1;
      end
      46, 47, 48, 49, 50, 51, 52, 53, 54: begin
        if (rx_data_valid === 1'b1) begin
          if (rx_data !== payload) begin
            $display("[FAIL] uart_rx expected=%0h got=%0h", payload, rx_data);
            $fatal(1);
          end
          rx_data_ready <= 1'b1;
          step <= 56;
        end else begin
          step <= step + 1;
        end
      end
      55: begin
        $display("[FAIL] uart_rx expected valid frame");
        $fatal(1);
      end
      56: begin
        rx_data_ready <= 1'b0;
        step <= 57;
      end
      57: begin
        if (rx_data_valid !== 1'b0) begin
          $display("[FAIL] uart_rx valid did not clear");
          $fatal(1);
        end
        $display("[PASS] uart_rx received and acknowledged one frame");
        $finish;
      end
    endcase
  end
endmodule
