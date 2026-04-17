// Simple input buffer for storing pixel data.
// This module is designed to hold a single image of 28x28 pixels (784 bytes),
// and allows for both writing and reading of pixel data.
module input_buffer #(
    parameter DEPTH = 784,
    parameter ADDR_WIDTH = $clog2(DEPTH)
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] write_addr,
    input  wire [           7:0] write_data,
    input  wire [ADDR_WIDTH-1:0] read_addr,
    output wire [           7:0] read_data
);

  reg [7:0] mem[0:DEPTH-1];

  always @(posedge clk) begin
    if (we) mem[write_addr] <= write_data;
  end

  assign read_data = mem[read_addr];

endmodule
