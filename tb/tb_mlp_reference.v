module tb_mlp_reference (
    input wire clk
);
  localparam integer INPUT_SIZE = 784;
  localparam integer OUTPUT_SIZE = 10;

  reg reset;
  reg start;
  wire busy;
  wire done;

  reg input_we;
  reg [9:0] input_addr;
  reg [7:0] input_data;

  reg [3:0] logit_addr;
  wire signed [31:0] logit_data;

  wire [3:0] class_id;
  wire signed [31:0] class_score;

  reg [7:0] ref_input[0:INPUT_SIZE-1];
  reg signed [31:0] ref_logits[0:OUTPUT_SIZE-1];
  reg signed [31:0] ref_class[0:1];

  integer step;
  integer load_index;
  integer check_index;

  mlp dut (
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
    $readmemh("tb/data/mlp_reference_input.mem", ref_input);
    $readmemh("tb/data/mlp_reference_logits.mem", ref_logits);
    $readmemh("tb/data/mlp_reference_class.mem", ref_class);

    reset = 1'b1;
    start = 1'b0;
    input_we = 1'b0;
    input_addr = 10'd0;
    input_data = 8'sd0;
    logit_addr = 4'd0;
    step = 0;
    load_index = 0;
    check_index = 0;
  end

  always @(posedge clk) begin
    case (step)
      0, 1: begin
        step <= step + 1;
      end

      2: begin
        reset <= 1'b0;
        input_we <= 1'b1;
        input_addr <= 10'd0;
        input_data <= ref_input[0];
        load_index <= 1;
        step <= 3;
      end

      3: begin
        if (load_index == INPUT_SIZE) begin
          input_we <= 1'b0;
          start <= 1'b1;
          step <= 4;
        end else begin
          input_addr <= load_index[9:0];
          input_data <= ref_input[load_index];
          load_index <= load_index + 1;
        end
      end

      4: begin
        start <= 1'b0;
        step <= 5;
      end

      5: begin
        if (done) begin
          if (class_id !== ref_class[0][3:0] || class_score !== ref_class[1]) begin
            $display("[FAIL] mlp_reference class expected id=%0d score=%0d got id=%0d score=%0d",
                     ref_class[0], ref_class[1], class_id, class_score);
            $fatal(1);
          end

          logit_addr <= 4'd0;
          check_index <= 0;
          step <= 6;
        end
      end

      6: begin
        step <= 7;
      end

      7: begin
        if (logit_data !== ref_logits[check_index]) begin
          $display("[FAIL] mlp_reference logit[%0d] expected=%0d got=%0d",
                   check_index, ref_logits[check_index], logit_data);
          $fatal(1);
        end

        if (check_index == OUTPUT_SIZE - 1) begin
          step <= 8;
        end else begin
          check_index <= check_index + 1;
          logit_addr <= (check_index + 1);
          step <= 6;
        end
      end

      8: begin
        $display("[PASS] mlp matches Python integer reference logits and class");
        $finish;
      end
    endcase
  end
endmodule
