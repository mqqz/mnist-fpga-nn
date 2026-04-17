module tb_matvec (
    input wire clk
);
  localparam integer IN_SIZE = 4;
  localparam integer OUT_SIZE = 2;
  localparam integer X_ADDR_W = 2;
  localparam integer Y_ADDR_W = 1;
  localparam integer W_ADDR_W = 3;

  reg reset;
  reg start;

  wire [X_ADDR_W-1:0] x_addr;
  reg signed [7:0] x_data;

  wire [W_ADDR_W-1:0] w_addr;
  reg signed [7:0] w_data;

  wire [Y_ADDR_W-1:0] bias_addr;
  reg signed [31:0] bias_data;

  wire y_we;
  wire [Y_ADDR_W-1:0] y_addr;
  wire signed [31:0] y_data;
  wire done;

  reg signed [7:0] x_mem[0:IN_SIZE-1];
  reg signed [7:0] w_mem[0:(IN_SIZE*OUT_SIZE)-1];
  reg signed [31:0] expected[0:OUT_SIZE-1];
  reg signed [31:0] observed[0:OUT_SIZE-1];
  integer write_count;
  integer step;
  reg saw_done;

  matvec #(
      .IN_SIZE(IN_SIZE),
      .OUT_SIZE(OUT_SIZE),
      .X_ADDR_W(X_ADDR_W),
      .Y_ADDR_W(Y_ADDR_W),
      .W_ADDR_W(W_ADDR_W)
  ) dut (
      .clk(clk),
      .reset(reset),
      .start(start),
      .x_addr(x_addr),
      .x_data(x_data),
      .w_addr(w_addr),
      .w_data(w_data),
      .bias_addr(bias_addr),
      .bias_data(bias_data),
      .y_we(y_we),
      .y_addr(y_addr),
      .y_data(y_data),
      .done(done)
  );

  always @(*) begin
    x_data = x_mem[x_addr];
  end

  always @(posedge clk) begin
    w_data <= w_mem[w_addr];
    bias_data <= 32'sd0;
  end

  always @(posedge clk) begin
    if (y_we) begin
      observed[y_addr] <= y_data;
      write_count <= write_count + 1;
    end
  end

  initial begin
    x_mem[0] = 8'sd1;
    x_mem[1] = 8'sd2;
    x_mem[2] = -8'sd1;
    x_mem[3] = 8'sd3;

    w_mem[0] = 8'sd2;
    w_mem[1] = 8'sd1;
    w_mem[2] = -8'sd1;
    w_mem[3] = 8'sd0;
    w_mem[4] = -8'sd3;
    w_mem[5] = 8'sd1;
    w_mem[6] = 8'sd2;
    w_mem[7] = 8'sd4;

    expected[0] = 32'sd5;
    expected[1] = 32'sd9;
    observed[0] = 32'sd0;
    observed[1] = 32'sd0;
    write_count = 0;
    step = 0;
    saw_done = 1'b0;

    reset = 1'b1;
    start = 1'b0;
  end

  always @(posedge clk) begin
    case (step)
      0: begin
        step <= 1;
      end
      1: begin
        reset <= 1'b0;
        step <= 2;
      end
      2: begin
        start <= 1'b1;
        step <= 3;
      end
      3: begin
        start <= 1'b0;
        step <= 4;
      end
      default: begin
        if (done) begin
          saw_done <= 1'b1;
        end

        if (saw_done) begin
          if (write_count !== OUT_SIZE) begin
            $display("[FAIL] matvec expected %0d writes got %0d", OUT_SIZE, write_count);
            $fatal(1);
          end

          if (observed[0] !== expected[0] || observed[1] !== expected[1]) begin
            $display("[FAIL] matvec expected [%0d, %0d] got [%0d, %0d]",
                     expected[0], expected[1], observed[0], observed[1]);
            $fatal(1);
          end

          $display("[PASS] matvec produced expected output vector");
          $finish;
        end
      end
    endcase
  end
endmodule
