# FPGA MLP Inference on Tang Nano 9K

Integer MLP inference in Verilog for the Sipeed Tang Nano 9K. The repo includes
the RTL accelerator, deterministic Python reference fixtures, Verilator tests, a
UART host protocol, image conversion tooling, and an open-source Gowin bitstream
flow.

Current model:

- Input: `28 x 28` raw grayscale image, `784` unsigned bytes
- Network: `784 -> 32 -> 10`
- Weights: int8, row-major
- Biases/logits: signed int32
- Host interface: UART at `115200` baud
- Hardware target: Gowin `GW1NR-LV9QN88PC6/I5`, family `GW1N-9C`

## Quick Start

Install Python dependencies into the uv-managed project environment:

```sh
uv sync
```

Run the full local gate:

```sh
make check
```

This runs the Verilator test suite, lints the main RTL tops, and builds the FPGA
bitstream.

Program the board:

```sh
make program
```

Validate real hardware against the Python reference logits:

```sh
make validate PORT=/dev/ttyUSB1 HOST_ARGS='--timeout 5'
```

On the tested setup, `/dev/ttyUSB1` is the FPGA UART. If your board enumerates
differently:

```sh
uv run python -m serial.tools.list_ports
```

## Daily Workflow

Convert an image to the raw FPGA input format:

```sh
make image IMAGE=digit.png OUTPUT=build/input.raw
```

If the source image is a dark digit on a bright background:

```sh
make image IMAGE=digit.png OUTPUT=build/input.raw HOST_ARGS='--invert'
```

Run inference over UART:

```sh
make infer PORT=/dev/ttyUSB1 IMAGE=build/input.raw
```

Generate the deterministic reference image used for hardware validation:

```sh
make reference-image
```

## Architecture

```text
PC host
  |
  | UART commands
  v
uart_rx -> controller -> mlp input memory
              |
              v
            mlp.v
              |
              +-- fc1: uint8 input x int8 weight + int32 bias
              +-- relu: ReLU + requantize to int8
              +-- fc2: int8 hidden x int8 weight + int32 bias
              +-- argmax over 10 int32 logits
              |
              v
controller -> uart_tx -> PC host
```

RTL hierarchy:

```text
board_top.v
  -> mlp_uart.v
       -> uart_rx.v / uart_tx.v
       -> controller.v
       -> mlp.v
            -> matvec.v
            -> relu.v
            -> rom.v
```

`board_top.v` is the Tang Nano 9K wrapper. `mlp_uart.v` is the reusable
accelerator top: UART, controller, and MLP core. `mlp.v` owns the inference
pipeline and stores input, hidden activations, logits, and class argmax.

## Repository Layout

```text
rtl/                  Synthesizable Verilog
tb/                   Verilator testbenches
tb/data/              Generated and checked-in test fixtures
mem/                  Exported model parameters
model/                Python model/export/reference utilities
host/                 Image conversion and UART host tools
cst/                  Gowin constraints
Makefile              Build, test, hardware, and host workflows
```

Key RTL files:

```text
rtl/board_top.v       Tang Nano 9K board wrapper
rtl/mlp_uart.v        UART-connected accelerator top
rtl/controller.v      UART protocol FSM
rtl/mlp.v             Two-layer MLP core
rtl/matvec.v          Dense matrix-vector engine
rtl/relu.v            ReLU + requantization
rtl/rom.v             Synchronous `$readmemh` ROM
rtl/protocol.vh       Command/response constants
rtl/uart_echo_top.v   UART echo diagnostic design
```

## Data Formats

### Input Image

The accelerator consumes exactly `784` bytes:

- Shape: `28 x 28`
- Layout: row-major
- Type: unsigned byte
- Range: `0..255`
- No file header, compression, or runtime normalization

`host/prepare_image.py` converts common image formats into this layout:

```sh
uv run python host/prepare_image.py digit.png build/input.raw
```

### Parameters

Model parameters are loaded from `mem/` during simulation and synthesis:

```text
mem/fc1_weight.mem   int8  two's-complement hex, row-major, 32 x 784
mem/fc1_bias.mem     int32 two's-complement hex, 32 values
mem/fc2_weight.mem   int8  two's-complement hex, row-major, 10 x 32
mem/fc2_bias.mem     int32 two's-complement hex, 10 values
mem/fc*_meta.json    scale and layout metadata
```

Weight address layout:

```text
addr = output_neuron * input_size + input_feature
```

Runtime parameter loading is intentionally out of scope for this version; the
model is fixed by the checked-in `.mem` files.

### Quantization

Layer 1 accumulates into int32, then `relu.v` applies ReLU and requantizes to
int8:

```text
hidden = clamp(round(max(fc1_acc, 0) * 26456 / 2^27), 0, 127)
```

Layer 2 accumulates directly to signed int32 logits.

### Output Frame

`READ_OUTPUT` returns `46` bytes:

```text
byte 0       RESP_OUTPUT = 0x83
byte 1       class_id, uint8
bytes 2..5   class_score, signed int32, little-endian
bytes 6..45  10 logits, signed int32, little-endian
```

## UART Protocol

Constants are defined in `rtl/protocol.vh` and mirrored in `host/protocol.py`.

```text
LOAD_INPUT
  host:  [01] [p0] [p1] ... [p783]
  fpga:  [81]

RUN
  host:  [02]
  fpga:  [82]

READ_OUTPUT
  host:  [03]
  fpga:  [83] [class]
         [score0] [score1] [score2] [score3]
         [logit0 byte0..3] ... [logit9 byte0..3]
```

Commands:

| Byte | Name | Payload |
| ---: | ---- | ------- |
| `0x01` | `CMD_LOAD_INPUT` | `784` image bytes |
| `0x02` | `CMD_RUN` | none |
| `0x03` | `CMD_READ_OUTPUT` | none |

Responses:

| Byte | Name | Meaning |
| ---: | ---- | ------- |
| `0x81` | `RESP_LOAD_DONE` | Image accepted |
| `0x82` | `RESP_RUN_DONE` | Inference finished |
| `0x83` | `RESP_OUTPUT` | Output frame follows |
| `0xe1` | `ERR_BAD_COMMAND` | Unknown command |
| `0xe2` | `ERR_RUN_NO_IMAGE` | `RUN` before image load |
| `0xe3` | `ERR_READ_NO_RESULT` | `READ_OUTPUT` before inference |

## Commands

Primary commands:

```sh
make check                       # test + lint + bitstream
make test                        # all Verilator tests
make run mlp                     # one Verilator test
make lint                        # lint main RTL tops
make bitstream                   # synthesize/place/pack board_top
make program                     # build and program board_top
make validate PORT=/dev/ttyUSB1  # hardware inference vs Python reference
make image IMAGE=... OUTPUT=...  # prepare raw input image
make infer PORT=... IMAGE=...    # UART inference
```

Diagnostics:

```sh
make echo-program                # program UART echo diagnostic
make echo PORT=/dev/ttyUSB1      # verify USB-UART path
make probe PORT=/dev/ttyUSB1     # check protocol status responses
```

Reference and inspection:

```sh
make reference                   # regenerate tb/data reference fixtures
make reference-image             # write build/reference/mlp_reference_input.raw
make list-tests                  # show module tests
make synth-cmd                   # print Yosys command
make pnr-cmd                     # print nextpnr command
make pack-cmd                    # print gowin_pack command
make program-cmd                 # print openFPGALoader command
```

Current test modules:

```text
controller
controller_uart
matvec
mlp
mlp_reference
mlp_uart
params
relu
rom
uart_rx
uart_tx
```

## Hardware Build

Default settings:

```text
DEVICE       = GW1NR-LV9QN88PC6/I5
FAMILY       = GW1N-9C
BOARD_TOP    = board_top
BOARD_CST    = cst/fpga_mlp.cst
LOADER_BOARD = tangnano9k
BAUD         = 115200
```

Measured build:

| Item | Value |
| ---- | ----- |
| Board | Sipeed Tang Nano 9K |
| FPGA | Gowin GW1NR-LV9QN88PC6/I5 |
| Family | GW1N-9C |
| UART baud | 115200 |
| Tested serial port | `/dev/ttyUSB1` |
| LUT4 | 2560 / 8640, 29% |
| BSRAM | 14 / 26, 53% |
| Fmax | 37.01 MHz |

Build outputs are written to `build/fpga/`.

`cst/fpga_mlp.cst` is the project constraint file. `cst/tangnano9k.cst` is kept
as a full board reference for future pin work.

## Verification

The same checked-in parameters drive Python reference generation, RTL tests, and
hardware validation:

1. `model/generate_mlp_reference.py` reads `mem/*.mem` and emits fixtures under
   `tb/data/`.
2. Verilator tests cover the controller, UART blocks, ROM loading, matvec, MLP,
   and the UART-connected accelerator top.
3. `tb/tb_mlp_reference.v` compares RTL logits and argmax against the Python
   integer reference.
4. `make validate` runs the bitstream over UART and compares hardware logits
   against the same reference files.

Known-good local gate:

```sh
make check
```

Known-good hardware gate:

```sh
make program
make validate PORT=/dev/ttyUSB1 HOST_ARGS='--timeout 5'
```

## Toolchain

Python dependencies are managed with `uv` through `pyproject.toml` and
`uv.lock`.

RTL/FPGA tools used:

- Verilator
- Yosys with Gowin support
- nextpnr-himbaechel
- Apicula `gowin_pack`
- openFPGALoader

Versions used for the current build:

```text
Verilator 4.222 2022-05-02
Yosys 0.47
openFPGALoader v1.1.1
nextpnr v0.10
Apicula v0.32
uv 0.11.1
Python 3.14.4
```

## Scope

This version optimizes for clarity and verified end-to-end behavior. The UART
protocol is compact and deterministic, the model is fixed at build time, and the
compute core is intentionally straightforward rather than aggressively
pipelined.

Natural next improvements:

- Add checksum/CRC to the UART protocol.
- Add runtime parameter loading if model swapping becomes important.
- Add inference cycle counters for measured latency.
- Pipeline or parallelize `matvec.v` for higher throughput.
