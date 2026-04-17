// Tang Nano 9K board wrapper.
//
// Ports match cst/fpga_mlp.cst:
//   clk   - onboard clock
//   rst_i - active-low pushbutton reset
//   RXD   - USB-serial RX into FPGA
//   TXD   - USB-serial TX out of FPGA
module board_top #(
    parameter CLK_FRE = 27,
    parameter BAUD_RATE = 115200
) (
    input  wire clk,
    input  wire rst_i,
    input  wire RXD,
    output wire TXD
);
  top #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) accelerator (
      .clk(clk),
      .reset(!rst_i),
      .rx_pin(RXD),
      .tx_pin(TXD)
  );
endmodule
