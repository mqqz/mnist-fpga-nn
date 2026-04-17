// Byte-protocol controller for the MLP accelerator.
//
// UART-facing protocol:
//   0x01 LOAD_INPUT   followed by IMAGE_SIZE input bytes
//   0x02 RUN          starts inference after a full input image is loaded
//   0x03 READ_OUTPUT  sends RESP_OUTPUT, class, score, and all logits.
`include "rtl/protocol.vh"

module controller #(
    parameter IMAGE_SIZE = 784,
    parameter OUTPUT_SIZE = 10,
    parameter INPUT_ADDR_W = 10,
    parameter OUTPUT_ADDR_W = 4
) (
    input wire clk,
    input wire reset,

    input  wire [7:0] rx_data,
    input  wire       rx_data_valid,
    output reg        rx_data_ready,

    output reg [7:0] tx_data,
    output reg       tx_data_valid,
    input  wire      tx_data_ready,

    output reg                    input_we,
    output reg [INPUT_ADDR_W-1:0] input_addr,
    output reg [             7:0] input_data,

    output reg mlp_start,
    input  wire mlp_busy,
    input  wire mlp_done,

    input wire [OUTPUT_ADDR_W-1:0] class_id,
    input wire signed [31:0] class_score,
    output wire [OUTPUT_ADDR_W-1:0] logit_addr,
    input wire signed [31:0] logit_data,

    output reg image_loaded,
    output reg result_valid,
    output reg [2:0] state_debug
);
  localparam [2:0] IDLE = 3'd0;
  localparam [2:0] LOAD_INPUT = 3'd1;
  localparam [2:0] RUN_LAYER1 = 3'd2;
  localparam [2:0] RUN_LAYER2 = 3'd3;
  localparam [2:0] SEND_OUTPUT = 3'd4;
  localparam [2:0] SEND_STATUS = 3'd5;

  localparam integer LAST_INPUT = IMAGE_SIZE - 1;
  localparam integer OUTPUT_FRAME_BYTES = 2 + 4 + (OUTPUT_SIZE * 4);
  localparam integer LAST_OUTPUT_BYTE = OUTPUT_FRAME_BYTES - 1;

  reg [2:0] state;
  reg [INPUT_ADDR_W-1:0] input_count;
  integer send_index;
  reg [7:0] status_byte;

  assign logit_addr = (state == SEND_OUTPUT && send_index >= 6) ?
                      logit_index_from_send(send_index) : {OUTPUT_ADDR_W{1'b0}};

  function [OUTPUT_ADDR_W-1:0] logit_index_from_send;
    input integer index;
    begin
      logit_index_from_send = OUTPUT_ADDR_W'((index - 6) / 4);
    end
  endfunction

  function [7:0] output_byte;
    input integer index;
    begin
      case (index)
        0: output_byte = `RESP_OUTPUT;
        1: output_byte = {{(8 - OUTPUT_ADDR_W) {1'b0}}, class_id};
        2: output_byte = class_score[7:0];
        3: output_byte = class_score[15:8];
        4: output_byte = class_score[23:16];
        5: output_byte = class_score[31:24];
        default: begin
          case ((index - 6) & 3)
            0: output_byte = logit_data[7:0];
            1: output_byte = logit_data[15:8];
            2: output_byte = logit_data[23:16];
            default: output_byte = logit_data[31:24];
          endcase
        end
      endcase
    end
  endfunction

  always @(*) begin
    state_debug = state;

    case (state)
      IDLE, LOAD_INPUT: rx_data_ready = 1'b1;
      default: rx_data_ready = 1'b0;
    endcase
  end

  always @(posedge clk) begin
    if (reset) begin
      state <= IDLE;
      tx_data <= 8'd0;
      tx_data_valid <= 1'b0;
      input_we <= 1'b0;
      input_addr <= 0;
      input_data <= 0;
      mlp_start <= 1'b0;
      image_loaded <= 1'b0;
      result_valid <= 1'b0;
      input_count <= 0;
      send_index <= 0;
      status_byte <= 8'd0;
    end else begin
      tx_data_valid <= 1'b0;
      input_we <= 1'b0;
      mlp_start <= 1'b0;

      case (state)
        IDLE: begin
          if (rx_data_valid) begin
            case (rx_data)
              `CMD_LOAD_INPUT: begin
                state <= LOAD_INPUT;
                input_count <= 0;
                image_loaded <= 1'b0;
                result_valid <= 1'b0;
              end

              `CMD_RUN: begin
                if (image_loaded && !mlp_busy) begin
                  state <= RUN_LAYER1;
                  mlp_start <= 1'b1;
                  result_valid <= 1'b0;
                end else begin
                  state <= SEND_STATUS;
                  status_byte <= `ERR_RUN_NO_IMAGE;
                end
              end

              `CMD_READ_OUTPUT: begin
                if (result_valid) begin
                  state <= SEND_OUTPUT;
                  send_index <= 0;
                end else begin
                  state <= SEND_STATUS;
                  status_byte <= `ERR_READ_NO_RESULT;
                end
              end

              default: begin
                state <= SEND_STATUS;
                status_byte <= `ERR_BAD_COMMAND;
              end
            endcase
          end
        end

        LOAD_INPUT: begin
          if (rx_data_valid) begin
            input_we <= 1'b1;
            input_addr <= input_count;
            input_data <= rx_data;

            if (input_count == LAST_INPUT[INPUT_ADDR_W-1:0]) begin
              image_loaded <= 1'b1;
              state <= SEND_STATUS;
              status_byte <= `RESP_LOAD_DONE;
            end else begin
              input_count <= input_count + 1'b1;
            end
          end
        end

        RUN_LAYER1: begin
          if (mlp_busy) begin
            state <= RUN_LAYER2;
          end else if (mlp_done) begin
            result_valid <= 1'b1;
            state <= SEND_STATUS;
            status_byte <= `RESP_RUN_DONE;
          end
        end

        RUN_LAYER2: begin
          if (mlp_done) begin
            result_valid <= 1'b1;
            state <= SEND_STATUS;
            status_byte <= `RESP_RUN_DONE;
          end
        end

        SEND_OUTPUT: begin
          if (tx_data_ready) begin
            tx_data <= output_byte(send_index);
            tx_data_valid <= 1'b1;

            if (send_index == LAST_OUTPUT_BYTE) begin
              state <= IDLE;
            end else begin
              send_index <= send_index + 1'b1;
            end
          end
        end

        SEND_STATUS: begin
          if (tx_data_ready) begin
            tx_data <= status_byte;
            tx_data_valid <= 1'b1;
            state <= IDLE;
          end
        end

        default: begin
          state <= IDLE;
        end
      endcase
    end
  end
endmodule
