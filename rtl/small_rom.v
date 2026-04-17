module small_rom #(
    parameter WIDTH = 8,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_FILE = ""
) (
    input  wire                        clk,
    input  wire       [ADDR_WIDTH-1:0] addr,
    output reg signed [     WIDTH-1:0] data
);

  (* mem2reg *) reg signed [WIDTH-1:0] mem[0:DEPTH-1];

  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  always @(posedge clk) begin
    data <= mem[addr];
  end

endmodule
