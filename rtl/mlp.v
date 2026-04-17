// Two-layer MLP inference core for the exported MNIST-style model.
//
// Flow:
//   1. Load INPUT_SIZE unsigned pixel features through input_we/input_addr.
//   2. Pulse start for one cycle.
//   3. Run FC1 + bias, ReLU+requantize, then FC2 + bias.
//   4. done pulses high for one cycle and class_id/class_score hold the argmax.
module mlp #(
    parameter INPUT_SIZE = 784,
    parameter HIDDEN_SIZE = 32,
    parameter OUTPUT_SIZE = 10,

    parameter INPUT_ADDR_W = 10,
    parameter HIDDEN_ADDR_W = 5,
    parameter OUTPUT_ADDR_W = 4,

    parameter FC1_WEIGHT_FILE = "mem/fc1_weight.mem",
    parameter FC1_BIAS_FILE = "mem/fc1_bias.mem",
    parameter FC2_WEIGHT_FILE = "mem/fc2_weight.mem",
    parameter FC2_BIAS_FILE = "mem/fc2_bias.mem",

    // fc1_acc_scale / fc2_input_scale for the checked-in mem files:
    // 2.6977018053303057e-05 / 0.13686184620294045 ~= 26456 / 2^27.
    parameter FC1_REQUANT_MULT  = 26456,
    parameter FC1_REQUANT_SHIFT = 27
) (
    input wire clk,
    input wire reset,

    input wire start,
    output reg busy,
    output reg done,

    input wire                    input_we,
    input wire [INPUT_ADDR_W-1:0] input_addr,
    input wire [             7:0] input_data,

    input  wire [OUTPUT_ADDR_W-1:0] logit_addr,
    output reg signed [      31:0] logit_data,

    output reg [OUTPUT_ADDR_W-1:0] class_id,
    output reg signed [31:0] class_score
);
  localparam [2:0] S_IDLE = 3'd0;
  localparam [2:0] S_FC1 = 3'd1;
  localparam [2:0] S_FC1_STORE = 3'd2;
  localparam [2:0] S_FC2 = 3'd3;
  localparam [2:0] S_DONE = 3'd4;

  localparam integer FC1_W_ADDR_W = $clog2(INPUT_SIZE * HIDDEN_SIZE);
  localparam integer FC2_W_ADDR_W = $clog2(HIDDEN_SIZE * OUTPUT_SIZE);
  localparam integer LAST_HIDDEN = HIDDEN_SIZE - 1;

  reg [2:0] state;
  reg fc1_start;
  reg fc2_start;

  wire [ INPUT_ADDR_W-1:0] fc1_x_addr;
  wire [ FC1_W_ADDR_W-1:0] fc1_w_addr;
  wire [HIDDEN_ADDR_W-1:0] fc1_bias_addr;
  wire fc1_y_we;
  wire [HIDDEN_ADDR_W-1:0] fc1_y_addr;
  wire signed [31:0] fc1_y_data;
  wire fc1_done_unused;

  wire [HIDDEN_ADDR_W-1:0] fc2_x_addr;
  wire [ FC2_W_ADDR_W-1:0] fc2_w_addr;
  wire [OUTPUT_ADDR_W-1:0] fc2_bias_addr;
  wire fc2_y_we;
  wire [OUTPUT_ADDR_W-1:0] fc2_y_addr;
  wire signed [31:0] fc2_y_data;
  wire fc2_done;

  wire signed [31:0] relu_out_data_unused;
  wire signed [7:0] relu_out_q8;

  reg [7:0] input_mem[0:INPUT_SIZE-1];
  reg signed [7:0] hidden_mem[0:HIDDEN_SIZE-1];
  reg signed [31:0] logit_mem[0:OUTPUT_SIZE-1];

  wire signed [7:0] fc1_weight_data;
  wire signed [31:0] fc1_bias_data;
  wire signed [7:0] fc2_weight_data;
  wire signed [31:0] fc2_bias_data;

  weight_rom #(
      .WIDTH(8),
      .DEPTH(INPUT_SIZE * HIDDEN_SIZE),
      .ADDR_WIDTH(FC1_W_ADDR_W),
      .INIT_FILE(FC1_WEIGHT_FILE)
  ) fc1_weight_rom (
      .clk(clk),
      .addr(fc1_w_addr),
      .data(fc1_weight_data)
  );

  small_rom #(
      .WIDTH(32),
      .DEPTH(HIDDEN_SIZE),
      .ADDR_WIDTH(HIDDEN_ADDR_W),
      .INIT_FILE(FC1_BIAS_FILE)
  ) fc1_bias_rom (
      .clk(clk),
      .addr(fc1_bias_addr),
      .data(fc1_bias_data)
  );

  weight_rom #(
      .WIDTH(8),
      .DEPTH(HIDDEN_SIZE * OUTPUT_SIZE),
      .ADDR_WIDTH(FC2_W_ADDR_W),
      .INIT_FILE(FC2_WEIGHT_FILE)
  ) fc2_weight_rom (
      .clk(clk),
      .addr(fc2_w_addr),
      .data(fc2_weight_data)
  );

  small_rom #(
      .WIDTH(32),
      .DEPTH(OUTPUT_SIZE),
      .ADDR_WIDTH(OUTPUT_ADDR_W),
      .INIT_FILE(FC2_BIAS_FILE)
  ) fc2_bias_rom (
      .clk(clk),
      .addr(fc2_bias_addr),
      .data(fc2_bias_data)
  );

  matvec #(
      .IN_SIZE(INPUT_SIZE),
      .OUT_SIZE(HIDDEN_SIZE),
      .X_ADDR_W(INPUT_ADDR_W),
      .Y_ADDR_W(HIDDEN_ADDR_W),
      .W_ADDR_W(FC1_W_ADDR_W),
      .X_UNSIGNED(1)
  ) fc1 (
      .clk(clk),
      .reset(reset),
      .start(fc1_start),
      .x_addr(fc1_x_addr),
      .x_data(input_mem[fc1_x_addr]),
      .w_addr(fc1_w_addr),
      .w_data(fc1_weight_data),
      .bias_addr(fc1_bias_addr),
      .bias_data(fc1_bias_data),
      .y_we(fc1_y_we),
      .y_addr(fc1_y_addr),
      .y_data(fc1_y_data),
      .done(fc1_done_unused)
  );

  relu #(
      .REQUANT_MULT(FC1_REQUANT_MULT),
      .REQUANT_SHIFT(FC1_REQUANT_SHIFT)
  ) fc1_relu (
      .clk(clk),
      .valid_in(fc1_y_we),
      .in_data(fc1_y_data),
      .out_data(relu_out_data_unused),
      .out_q8(relu_out_q8)
  );

  matvec #(
      .IN_SIZE(HIDDEN_SIZE),
      .OUT_SIZE(OUTPUT_SIZE),
      .X_ADDR_W(HIDDEN_ADDR_W),
      .Y_ADDR_W(OUTPUT_ADDR_W),
      .W_ADDR_W(FC2_W_ADDR_W),
      .X_UNSIGNED(0)
  ) fc2 (
      .clk(clk),
      .reset(reset),
      .start(fc2_start),
      .x_addr(fc2_x_addr),
      .x_data(hidden_mem[fc2_x_addr]),
      .w_addr(fc2_w_addr),
      .w_data(fc2_weight_data),
      .bias_addr(fc2_bias_addr),
      .bias_data(fc2_bias_data),
      .y_we(fc2_y_we),
      .y_addr(fc2_y_addr),
      .y_data(fc2_y_data),
      .done(fc2_done)
  );

  always @(posedge clk) begin
    if (input_we) input_mem[input_addr] <= input_data;
  end

  always @(*) begin
    logit_data = logit_mem[logit_addr];
  end

  always @(posedge clk) begin
    if (reset) begin
      state <= S_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      fc1_start <= 1'b0;
      fc2_start <= 1'b0;
      class_id <= 0;
      class_score <= 0;
    end else begin
      done <= 1'b0;
      fc1_start <= 1'b0;
      fc2_start <= 1'b0;

      case (state)
        S_IDLE: begin
          busy <= 1'b0;

          if (start) begin
            busy <= 1'b1;
            fc1_start <= 1'b1;
            class_id <= 0;
            class_score <= 32'sh8000_0000;
            state <= S_FC1;
          end
        end

        S_FC1: begin
          if (fc1_y_we) begin
            state <= S_FC1_STORE;
          end
        end

        S_FC1_STORE: begin
          hidden_mem[fc1_y_addr] <= relu_out_q8;

          if (fc1_y_addr == LAST_HIDDEN[HIDDEN_ADDR_W-1:0]) begin
            fc2_start <= 1'b1;
            state <= S_FC2;
          end else begin
            state <= S_FC1;
          end
        end

        S_FC2: begin
          if (fc2_y_we) begin
            logit_mem[fc2_y_addr] <= fc2_y_data;

            if (fc2_y_addr == 0 || fc2_y_data > class_score) begin
              class_id <= fc2_y_addr;
              class_score <= fc2_y_data;
            end
          end

          if (fc2_done) begin
            state <= S_DONE;
          end
        end

        S_DONE: begin
          busy <= 1'b0;
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: begin
          state <= S_IDLE;
          busy <= 1'b0;
        end
      endcase
    end
  end
endmodule
