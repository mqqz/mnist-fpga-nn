module uart_tx #(
    parameter CLK_FRE   = 50,
    parameter BAUD_RATE = 115200
) (
    input            clk,
    input            rst_n,
    input      [7:0] tx_data,
    input            tx_data_valid,
    output           tx_data_ready,
    output           tx_pin
);
  localparam CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
  localparam [15:0] CYCLE_COUNT = CYCLE[15:0];

  localparam S_IDLE = 3'd1;
  localparam S_START = 3'd2;
  localparam S_SEND_BYTE = 3'd3;
  localparam S_STOP = 3'd4;

  reg [ 2:0] state;
  reg [ 2:0] next_state;
  reg [15:0] cycle_cnt;
  reg [ 2:0] bit_cnt;
  reg [ 7:0] tx_data_latch;
  reg        tx_reg;

  assign tx_pin = tx_reg;
  assign tx_data_ready = (state == S_IDLE) && !tx_data_valid;

  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) state <= S_IDLE;
    else state <= next_state;
  end

  always @(*) begin
    case (state)
      S_IDLE: begin
        if (tx_data_valid) next_state = S_START;
        else next_state = S_IDLE;
      end
      S_START: begin
        if (cycle_cnt == CYCLE_COUNT - 1'b1) next_state = S_SEND_BYTE;
        else next_state = S_START;
      end
      S_SEND_BYTE: begin
        if (cycle_cnt == CYCLE_COUNT - 1'b1 && bit_cnt == 3'd7) next_state = S_STOP;
        else next_state = S_SEND_BYTE;
      end
      S_STOP: begin
        if (cycle_cnt == CYCLE_COUNT - 1'b1) next_state = S_IDLE;
        else next_state = S_STOP;
      end
      default: next_state = S_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
      tx_data_latch <= 8'd0;
    end else if (state == S_IDLE && tx_data_valid == 1'b1) begin
      tx_data_latch <= tx_data;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
      bit_cnt <= 3'd0;
    end else if (state == S_SEND_BYTE) begin
      if (cycle_cnt == CYCLE_COUNT - 1'b1) bit_cnt <= bit_cnt + 3'd1;
      else bit_cnt <= bit_cnt;
    end else begin
      bit_cnt <= 3'd0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) cycle_cnt <= 16'd0;
    else if ((state == S_SEND_BYTE && cycle_cnt == CYCLE_COUNT - 1'b1) || next_state != state)
      cycle_cnt <= 16'd0;
    else cycle_cnt <= cycle_cnt + 16'd1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) tx_reg <= 1'b1;
    else
      case (state)
        S_IDLE, S_STOP: tx_reg <= 1'b1;
        S_START: tx_reg <= 1'b0;
        S_SEND_BYTE: tx_reg <= tx_data_latch[bit_cnt];
        default: tx_reg <= 1'b1;
      endcase
  end
endmodule
