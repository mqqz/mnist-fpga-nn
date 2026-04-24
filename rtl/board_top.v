// Tang Nano 9K board wrapper.
//
// Ports match cst/fpga_mlp.cst:
//   clk   - onboard clock
//   rst_i - active-low pushbutton reset
//   RXD   - USB-serial RX into FPGA
//   TXD   - USB-serial TX out of FPGA
module board_top #(
    parameter CLK_FRE = 27,
    parameter BAUD_RATE = 115200,
    parameter RESET_CYCLES = 1024
) (
    input  wire clk,
    input  wire rst_i,
    input  wire RXD,
    output wire TXD
);
  localparam RESET_COUNT_W = $clog2(RESET_CYCLES + 1);
  localparam [RESET_COUNT_W-1:0] RESET_LAST = RESET_CYCLES[RESET_COUNT_W-1:0];

  reg [RESET_COUNT_W-1:0] reset_count = {RESET_COUNT_W{1'b0}};
  reg power_on_reset = 1'b1;

  always @(posedge clk or negedge rst_i) begin
    if (!rst_i) begin
      reset_count <= {RESET_COUNT_W{1'b0}};
      power_on_reset <= 1'b1;
    end else if (power_on_reset) begin
      if (reset_count == RESET_LAST) begin
        power_on_reset <= 1'b0;
      end else begin
        reset_count <= reset_count + 1'b1;
      end
    end
  end

  mlp_uart #(
      .CLK_FRE(CLK_FRE),
      .BAUD_RATE(BAUD_RATE)
  ) accelerator (
      .clk(clk),
      .reset(!rst_i || power_on_reset),
      .rx_pin(RXD),
      .tx_pin(TXD)
  );
endmodule
