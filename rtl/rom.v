module rom #(
    parameter WIDTH = 8,
    parameter DEPTH = 256,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_FILE = "",
    parameter DISTRIBUTED = 0
) (
    input  wire                        clk,
    input  wire       [ADDR_WIDTH-1:0] addr,
    output reg signed [     WIDTH-1:0] data
);
  generate
    if (DISTRIBUTED) begin : distributed_rom
      (* mem2reg *) reg signed [WIDTH-1:0] mem[0:DEPTH-1];

      initial begin
        if (INIT_FILE != "") begin
          $readmemh(INIT_FILE, mem);
        end
      end

      always @(posedge clk) begin
        data <= mem[addr];
      end
    end else begin : block_rom
      (* rom_style = "block", ram_style = "block" *) reg signed [WIDTH-1:0] mem[0:DEPTH-1];

      initial begin
        if (INIT_FILE != "") begin
          $readmemh(INIT_FILE, mem);
        end
      end

      always @(posedge clk) begin
        data <= mem[addr];
      end
    end
  endgenerate
endmodule
