module tb_params (
    input wire clk
);
  reg [14:0] fc1_w_addr;
  reg [4:0] fc1_b_addr;
  reg [8:0] fc2_w_addr;
  reg [3:0] fc2_b_addr;

  wire signed [7:0] fc1_w_data;
  wire signed [31:0] fc1_b_data;
  wire signed [7:0] fc2_w_data;
  wire signed [31:0] fc2_b_data;

  integer step;

  rom #(
      .WIDTH(8),
      .DEPTH(25088),
      .ADDR_WIDTH(15),
      .INIT_FILE("mem/fc1_weight.mem")
  ) fc1_weight (
      .clk(clk),
      .addr(fc1_w_addr),
      .data(fc1_w_data)
  );

  rom #(
      .WIDTH(32),
      .DEPTH(32),
      .ADDR_WIDTH(5),
      .INIT_FILE("mem/fc1_bias.mem")
  ) fc1_bias (
      .clk(clk),
      .addr(fc1_b_addr),
      .data(fc1_b_data)
  );

  rom #(
      .WIDTH(8),
      .DEPTH(320),
      .ADDR_WIDTH(9),
      .INIT_FILE("mem/fc2_weight.mem")
  ) fc2_weight (
      .clk(clk),
      .addr(fc2_w_addr),
      .data(fc2_w_data)
  );

  rom #(
      .WIDTH(32),
      .DEPTH(10),
      .ADDR_WIDTH(4),
      .INIT_FILE("mem/fc2_bias.mem")
  ) fc2_bias (
      .clk(clk),
      .addr(fc2_b_addr),
      .data(fc2_b_data)
  );

  initial begin
    fc1_w_addr = 15'd0;
    fc1_b_addr = 5'd0;
    fc2_w_addr = 9'd0;
    fc2_b_addr = 4'd0;
    step = 0;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        step <= 1;
      end

      1: begin
        fc1_w_addr <= 15'd3;
        fc1_b_addr <= 5'd4;
        fc2_w_addr <= 9'd5;
        fc2_b_addr <= 4'd5;
        step <= 2;
      end

      2: begin
        step <= 3;
      end

      3: begin
        $display("[PASS] params loaded exported weights and biases through rom");
        $finish;
      end
    endcase
  end

  always @(negedge clk) begin
    case (step)
      1: begin
        if (fc1_w_data !== 8'sd4) begin
          $display("[FAIL] fc1_weight expected=4 got=%0d", fc1_w_data);
          $fatal(1);
        end

        if (fc1_b_data !== -32'sd774) begin
          $display("[FAIL] fc1_bias expected=-774 got=%0d", fc1_b_data);
          $fatal(1);
        end

        if (fc2_w_data !== -8'sd48) begin
          $display("[FAIL] fc2_weight expected=-48 got=%0d", fc2_w_data);
          $fatal(1);
        end

        if (fc2_b_data !== -32'sd197) begin
          $display("[FAIL] fc2_bias expected=-197 got=%0d", fc2_b_data);
          $fatal(1);
        end
      end

      3: begin
        if (fc1_w_data !== 8'sd5) begin
          $display("[FAIL] fc1_weight expected=5 got=%0d", fc1_w_data);
          $fatal(1);
        end

        if (fc1_b_data !== 32'sd7212) begin
          $display("[FAIL] fc1_bias expected=7212 got=%0d", fc1_b_data);
          $fatal(1);
        end

        if (fc2_w_data !== -8'sd64) begin
          $display("[FAIL] fc2_weight expected=-64 got=%0d", fc2_w_data);
          $fatal(1);
        end

        if (fc2_b_data !== 32'sd178) begin
          $display("[FAIL] fc2_bias expected=178 got=%0d", fc2_b_data);
          $fatal(1);
        end
      end
    endcase
  end
endmodule
