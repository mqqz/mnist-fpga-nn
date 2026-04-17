`ifndef FPGA_MLP_PROTOCOL_VH
`define FPGA_MLP_PROTOCOL_VH

`define CMD_LOAD_INPUT     8'h01
`define CMD_RUN            8'h02
`define CMD_READ_OUTPUT    8'h03

`define RESP_LOAD_DONE     8'h81
`define RESP_RUN_DONE      8'h82
`define RESP_OUTPUT        8'h83

`define ERR_BAD_COMMAND    8'he1
`define ERR_RUN_NO_IMAGE   8'he2
`define ERR_READ_NO_RESULT 8'he3

`endif
