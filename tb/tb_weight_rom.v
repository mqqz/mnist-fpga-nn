module tb_weight_rom (
    input wire clk
);
  reg [1:0] addr;
  wire signed [7:0] data;
  integer step;

  weight_rom #(
      .WIDTH(8),
      .DEPTH(4),
      .ADDR_WIDTH(2),
      .INIT_FILE("tb/data/weight_rom_test.mem")
  ) dut (
      .clk(clk),
      .addr(addr),
      .data(data)
  );

  task expect_data;
    input [1:0] expected_addr;
    input signed [7:0] expected_value;
    begin
      if (data !== expected_value) begin
        $display("[FAIL] weight_rom addr=%0d expected=%0d got=%0d",
                 expected_addr, expected_value, data);
        $fatal(1);
      end
    end
  endtask

  initial begin
    addr = 0;
    step = 0;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        addr <= 2'd0;
        step <= 1;
      end
      1: begin
        addr <= 2'd1;
        step <= 2;
      end
      2: begin
        addr <= 2'd2;
        step <= 3;
      end
      3: begin
        addr <= 2'd3;
        step <= 4;
      end
      4: begin
        $display("[PASS] weight_rom initialized contents match fixture");
        $finish;
      end
    endcase
  end

  always @(negedge clk) begin
    case (step)
      2: expect_data(2'd0, 8'sd1);
      3: expect_data(2'd1, -8'sd2);
      4: expect_data(2'd2, 8'sd15);
      5: expect_data(2'd3, -8'sd8);
    endcase
  end
endmodule
