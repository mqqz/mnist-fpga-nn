# Quantised MNIST Neural Network on FPGA (Tang Nano 9K)

I'm using a piss-cheap Sipeed Tang Nano9k board bought from China.

## Prerequisites

### Open-source Toolchain

- Synthesis: [`yosys`](https://github.com/YosysHQ/yosys)
- Place-and-route: [`nextpnr(-himbachael)`](https://github.com/YosysHQ/nextpnr)
- Bitstream: [`Apocula`](https://github.com/YosysHQ/apicula) (or whatever's needed for your board)
- Programming: [`openfpgaloader`](https://trabucayre.github.io/openFPGALoader/index.html)

## Development

### Verilator

[Verilator](https://github.com/verilator/verilator) is used for simulation and linting
e.g. commands like `make build` and `make lint`.

### Python

Python is used for creating and training (pytorch) the original model and quanitsing it (torchao)
as well as communicating with the board (pyserial).

- `uv` is used to manage the virtual environment
- run `uv sync` to install needed python deps.
- `model/` contains necessary code to train model and generate weights.
- `host/` contains code to interface with the board.

You might not need to bother with training you can find the pretrained weights in `mem/`, but the
model code is there for your reference.

## Programming the Board

`make fpga-build` does the necessary synthesis and bitstream generation then `make fpga-program`
programs the board.

You can grab the bitstream .fs for tangnano9k or alternatively build from source for your board
provided it is supported by the toolchain, you might have to fiddle a bit with the code and build
commands to get it working.

## Inference Example

1. Plug-in and program the fpga `make fpga-program`.
2. Generate a reference image `make host-reference-image`.
3. Do inference `make host-infer PORT=/dev/ttyUSB1 IMAGE=build/reference/mlp_reference_input.raw`.

## Future Enhancements

- [ ] Pipeline MAC
- [ ] Handle BRAM latency properly
- [ ] Reduce stalls
- [ ] Check DSP usage
- [ ] Check LUT usage
- [ ] Optimize bit widths

