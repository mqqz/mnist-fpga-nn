module tb_relu (
    input wire clk
);
  reg valid_in;
  reg signed [31:0] in_data;
  wire signed [31:0] out_data;
  wire signed [7:0] out_q8;
  integer step;

  relu dut (
      .clk(clk),
      .valid_in(valid_in),
      .in_data(in_data),
      .out_data(out_data),
      .out_q8(out_q8)
  );

  task expect_out;
    input signed [31:0] expected_value;
    input signed [7:0] expected_q8;
    begin
      if (out_data !== expected_value) begin
        $display("[FAIL] relu expected=%0d got=%0d", expected_value, out_data);
        $fatal(1);
      end

      if (out_q8 !== expected_q8) begin
        $display("[FAIL] relu q8 expected=%0d got=%0d", expected_q8, out_q8);
        $fatal(1);
      end
    end
  endtask

  initial begin
    valid_in = 1'b0;
    in_data = 0;
    step = 0;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        valid_in <= 1'b1;
        in_data <= 32'sd15;
        step <= 1;
      end
      1: begin
        in_data <= -32'sd9;
        step <= 2;
      end
      2: begin
        valid_in <= 1'b0;
        in_data <= 32'sd99;
        step <= 3;
      end
      3: begin
        $display("[PASS] relu positive and negative clamp behavior");
        $finish;
      end
    endcase
  end

  always @(negedge clk) begin
    case (step)
      2: expect_out(32'sd15, 8'sd15);
      3: expect_out(32'sd0, 8'sd0);
      4: expect_out(32'sd0, 8'sd0);
    endcase
  end
endmodule
