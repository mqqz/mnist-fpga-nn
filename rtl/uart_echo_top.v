// Tang Nano 9K UART echo diagnostic.
//
// Uses the same board pins and UART timing as board_top, but bypasses the MLP
// pipeline so hardware bring-up can isolate USB-UART channel, pin mapping, and
// reset polarity.
module uart_echo_top #(
    parameter CLK_FRE = 27,
    parameter BAUD_RATE = 115200
) (
    input  wire clk,
    input  wire rst_i,
    input  wire RXD,
    output wire TXD
);
  wire [7:0] rx_data;
  wire rx_data_valid;
  wire rx_data_ready;
  wire tx_data_ready;
  reg [7:0] echo_data;
  reg echo_pending;
  reg tx_data_valid;

  assign rx_data_ready = !echo_pending;

  uart_rx #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) rx (
      .clk(clk),
      .rst_n(rst_i),
      .rx_data(rx_data),
      .rx_data_valid(rx_data_valid),
      .rx_data_ready(rx_data_ready),
      .rx_pin(RXD)
  );

  uart_tx #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) tx (
      .clk(clk),
      .rst_n(rst_i),
      .tx_data(echo_data),
      .tx_data_valid(tx_data_valid),
      .tx_data_ready(tx_data_ready),
      .tx_pin(TXD)
  );

  always @(posedge clk or negedge rst_i) begin
    if (!rst_i) begin
      echo_data <= 8'd0;
      echo_pending <= 1'b0;
      tx_data_valid <= 1'b0;
    end else begin
      tx_data_valid <= 1'b0;

      if (rx_data_valid && rx_data_ready) begin
        echo_data <= rx_data;
        echo_pending <= 1'b1;
      end else if (echo_pending && tx_data_ready) begin
        tx_data_valid <= 1'b1;
        echo_pending <= 1'b0;
      end
    end
  end
endmodule
