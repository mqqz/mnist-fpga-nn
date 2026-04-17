module tb_input_buffer (
    input wire clk
);
  localparam integer DEPTH = 8;
  localparam integer ADDR_WIDTH = 3;

  reg we;
  reg [ADDR_WIDTH-1:0] write_addr;
  reg [7:0] write_data;
  reg [ADDR_WIDTH-1:0] read_addr;
  wire [7:0] read_data;

  reg [7:0] expected[0:DEPTH-1];
  integer step;

  input_buffer #(
      .DEPTH(DEPTH),
      .ADDR_WIDTH(ADDR_WIDTH)
  ) dut (
      .clk(clk),
      .we(we),
      .write_addr(write_addr),
      .write_data(write_data),
      .read_addr(read_addr),
      .read_data(read_data)
  );

  task expect_read;
    input integer addr;
    input [7:0] expected_value;
    begin
      if (read_data !== expected_value) begin
        $display("[FAIL] input_buffer addr=%0d expected=%0d got=%0d",
                 addr, expected_value, read_data);
        $fatal(1);
      end
    end
  endtask

  initial begin
    we = 0;
    write_addr = 0;
    write_data = 0;
    read_addr = 0;
    step = 0;

    expected[0] = 8'd11;
    expected[1] = 8'd22;
    expected[2] = 8'd33;
    expected[3] = 8'd44;
    expected[4] = 8'd55;
    expected[5] = 8'd66;
    expected[6] = 8'd77;
    expected[7] = 8'd88;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        we <= 1'b1;
        write_addr <= 0;
        write_data <= expected[0];
        step <= 1;
      end
      1, 2, 3, 4, 5, 6, 7: begin
        write_addr <= step[ADDR_WIDTH-1:0];
        write_data <= expected[step];
        step <= step + 1;
      end
      8: begin
        we <= 1'b0;
        read_addr <= 0;
        step <= 9;
      end
      9: begin read_addr <= 1; step <= 10; end
      10: begin read_addr <= 2; step <= 11; end
      11: begin read_addr <= 3; step <= 12; end
      12: begin read_addr <= 4; step <= 13; end
      13: begin read_addr <= 5; step <= 14; end
      14: begin read_addr <= 6; step <= 15; end
      15: begin read_addr <= 7; step <= 16; end
      16: begin
        write_addr <= 0;
        write_data <= 8'hFF;
        read_addr <= 0;
        step <= 17;
      end
      17: begin
        $display("[PASS] input_buffer wrote and read back all entries");
        $finish;
      end
    endcase
  end

  always @(negedge clk) begin
    case (step)
      9:  expect_read(0, expected[0]);
      10: expect_read(1, expected[1]);
      11: expect_read(2, expected[2]);
      12: expect_read(3, expected[3]);
      13: expect_read(4, expected[4]);
      14: expect_read(5, expected[5]);
      15: expect_read(6, expected[6]);
      16: expect_read(7, expected[7]);
      17: expect_read(0, expected[0]);
    endcase
  end
endmodule
