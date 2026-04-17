module tb_mlp (
    input wire clk
);
  localparam integer INPUT_SIZE = 4;
  localparam integer HIDDEN_SIZE = 3;
  localparam integer OUTPUT_SIZE = 2;

  reg reset;
  reg start;
  wire busy;
  wire done;

  reg input_we;
  reg [1:0] input_addr;
  reg [7:0] input_data;

  reg [0:0] logit_addr;
  wire signed [31:0] logit_data;

  wire [0:0] class_id;
  wire signed [31:0] class_score;

  integer step;
  reg saw_done;

  mlp #(
      .INPUT_SIZE(INPUT_SIZE),
      .HIDDEN_SIZE(HIDDEN_SIZE),
      .OUTPUT_SIZE(OUTPUT_SIZE),
      .INPUT_ADDR_W(2),
      .HIDDEN_ADDR_W(2),
      .OUTPUT_ADDR_W(1),
      .FC1_WEIGHT_FILE("tb/data/mlp_fc1_weight.mem"),
      .FC1_BIAS_FILE("tb/data/mlp_fc1_bias.mem"),
      .FC2_WEIGHT_FILE("tb/data/mlp_fc2_weight.mem"),
      .FC2_BIAS_FILE("tb/data/mlp_fc2_bias.mem"),
      .FC1_REQUANT_MULT(1),
      .FC1_REQUANT_SHIFT(1)
  ) dut (
      .clk(clk),
      .reset(reset),
      .start(start),
      .busy(busy),
      .done(done),
      .input_we(input_we),
      .input_addr(input_addr),
      .input_data(input_data),
      .logit_addr(logit_addr),
      .logit_data(logit_data),
      .class_id(class_id),
      .class_score(class_score)
  );

  initial begin
    reset = 1'b1;
    start = 1'b0;
    input_we = 1'b0;
    input_addr = 2'd0;
    input_data = 8'sd0;
    logit_addr = 1'd0;
    step = 0;
    saw_done = 1'b0;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        reset <= 1'b0;
        step <= 1;
      end

      1: begin
        input_we <= 1'b1;
        input_addr <= 2'd0;
        input_data <= 8'sd3;
        step <= 2;
      end

      2: begin
        input_addr <= 2'd1;
        input_data <= 8'd2;
        step <= 3;
      end

      3: begin
        input_addr <= 2'd2;
        input_data <= 8'sd1;
        step <= 4;
      end

      4: begin
        input_addr <= 2'd3;
        input_data <= 8'sd4;
        step <= 5;
      end

      5: begin
        input_we <= 1'b0;
        start <= 1'b1;
        step <= 6;
      end

      6: begin
        start <= 1'b0;
        step <= 7;
      end

      7: begin
        if (done) begin
          saw_done <= 1'b1;

          if (busy !== 1'b0) begin
            $display("[FAIL] mlp expected busy low with done");
            $fatal(1);
          end

          if (class_id !== 1'd0 || class_score !== 32'sd33) begin
            $display("[FAIL] mlp class expected id=0 score=33 got id=%0d score=%0d",
                     class_id, class_score);
            $fatal(1);
          end

          logit_addr <= 1'd0;
          step <= 8;
        end
      end

      8: begin
        step <= 9;
      end

      9: begin
        if (logit_data !== 32'sd33) begin
          $display("[FAIL] mlp logit0 expected=33 got=%0d", logit_data);
          $fatal(1);
        end

        logit_addr <= 1'd1;
        step <= 10;
      end

      10: begin
        step <= 11;
      end

      11: begin
        if (logit_data !== 32'sd17) begin
          $display("[FAIL] mlp logit1 expected=17 got=%0d", logit_data);
          $fatal(1);
        end

        if (!saw_done) begin
          $display("[FAIL] mlp never observed done");
          $fatal(1);
        end

        $display("[PASS] mlp produced expected logits and argmax");
        $finish;
      end
    endcase
  end
endmodule
