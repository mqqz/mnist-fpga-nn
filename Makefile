VERILATOR ?= verilator
UV        ?= uv
PYTHON    ?= $(UV) run python
CXXFLAGS  ?= -std=c++17

export CCACHE_DISABLE := 1

MODULES := \
	controller \
	controller_uart \
	input_buffer \
	matvec \
	mlp \
	mlp_reference \
	param_rom \
	relu \
	top \
	uart_rx \
	uart_tx \
	weight_rom

RTL_FILES := $(sort $(abspath $(wildcard rtl/*.v)))
SIM_MAIN  := $(abspath sim_main.cpp)

DEVICE       ?= GW1NR-LV9QN88PC6/I5
FAMILY       ?= GW1N-9C
BOARD_TOP    ?= board_top
BOARD_CST    ?= cst/fpga_mlp.cst
FPGA_DIR     ?= build/fpga
FPGA_JSON    ?= $(FPGA_DIR)/$(BOARD_TOP).json
FPGA_PNR_JSON ?= $(FPGA_DIR)/$(BOARD_TOP)_pnr.json
FPGA_BITSTREAM ?= $(FPGA_DIR)/$(BOARD_TOP).fs
LOADER_CABLE ?= ft2232
BAUD         ?= 115200
REFERENCE_IMAGE ?= build/reference/mlp_reference_input.raw

REFERENCE_FILES := \
	tb/data/mlp_reference_input.mem \
	tb/data/mlp_reference_hidden.mem \
	tb/data/mlp_reference_logits.mem \
	tb/data/mlp_reference_class.mem

REFERENCE_DEPS := \
	model/generate_mlp_reference.py \
	mem/fc1_weight.mem \
	mem/fc1_bias.mem \
	mem/fc2_weight.mem \
	mem/fc2_bias.mem

VERILATOR_WARN_FLAGS := \
	-Wall \
	-Wno-DECLFILENAME \
	-Wno-fatal

TOP_MODULE ?= top
LINT_TOPS  ?= top controller mlp matvec

REQUESTED_MODULES := $(filter $(MODULES),$(MAKECMDGOALS))

ifeq ($(words $(REQUESTED_MODULES)),0)
TEST_MODULES := $(MODULES)
else ifeq ($(words $(REQUESTED_MODULES)),1)
TEST_MODULES := $(REQUESTED_MODULES)
else
$(error Specify at most one module: $(REQUESTED_MODULES))
endif

MODULE    := $(firstword $(TEST_MODULES))
TB_TOP    := tb_$(MODULE)
TB_FILE   := $(abspath tb/$(TB_TOP).v)
BUILD_DIR := build/$(MODULE)
SIM_BIN   := $(BUILD_DIR)/V$(TB_TOP)
BUILD_LOG := $(BUILD_DIR)/build.log
TEST_LOG  := $(BUILD_DIR)/test.log
REF_LOG   := $(BUILD_DIR)/reference.log

VERILATOR_BUILD_FLAGS := \
	$(VERILATOR_WARN_FLAGS) \
	--cc \
	$(RTL_FILES) \
	$(TB_FILE) \
	--exe $(SIM_MAIN) \
	--build \
	--Mdir $(BUILD_DIR) \
	--top-module $(TB_TOP) \
	-CFLAGS "$(CXXFLAGS) -DTOP_HEADER=\\\"V$(TB_TOP).h\\\" -DTOP_CLASS=V$(TB_TOP)"

VERILATOR_LINT_FLAGS := \
	$(VERILATOR_WARN_FLAGS) \
	--lint-only \
	$(RTL_FILES)

.PHONY: \
	all help list-tests \
	build run test \
	lint lint-top lint-module \
	verilator-cmd verilator-lint-cmd \
	host-help host-infer \
	host-reference-image hw-validate \
	fpga-synth fpga-pnr fpga-pack fpga-build fpga-program \
	reference clean \
	$(MODULES)

all: test

help:
	@echo "Targets:"
	@echo "  make test                         Run the full test suite"
	@echo "  make test <module>                Run one module test, e.g. make test mlp"
	@echo "  make build <module>               Build one module simulation"
	@echo "  make run <module>                 Build and run one module simulation"
	@echo "  make lint                         Lint common RTL tops: $(LINT_TOPS)"
	@echo "  make lint-top TOP_MODULE=<top>    Lint a specific RTL top"
	@echo "  make lint-module <module>         Lint RTL plus one testbench top"
	@echo "  make reference                    Regenerate Python/RTL reference fixtures"
	@echo "  make host-help                    Show UART host tool help through uv"
	@echo "  make host-infer PORT=... IMAGE=... Run UART inference through uv"
	@echo "  make host-reference-image         Write reference raw image for hardware validation"
	@echo "  make hw-validate PORT=...         Run host inference and compare reference logits"
	@echo "  make fpga-build                   Build FPGA bitstream"
	@echo "  make fpga-program                 Program FPGA with openFPGALoader"
	@echo "  make verilator-cmd <module>       Print the Verilator build command"
	@echo "  make verilator-lint-cmd           Print the Verilator lint command"
	@echo "  make list-tests                   List available module tests"
	@echo "  make clean                        Remove generated build output"
	@echo ""
	@echo "Variables:"
	@echo "  MODULE=<module>                   Alternative to the module alias"
	@echo "  TOP_MODULE=<top>                  RTL top for lint-top, default: top"
	@echo "  LINT_TOPS='top mlp ...'           Tops used by make lint"
	@echo "  PYTHON='uv run python'            Python runner for project scripts"
	@echo "  PORT=/dev/ttyUSB0 IMAGE=img.raw   Inputs for make host-infer"
	@echo "  DEVICE='$(DEVICE)' FAMILY='$(FAMILY)' BOARD_TOP='$(BOARD_TOP)'"
	@echo "  SIM_MAX_TICKS=<ticks>             Runtime timeout consumed by sim_main.cpp"

list-tests:
	@printf '%s\n' $(MODULES)

reference: $(REFERENCE_FILES)
	@mkdir -p build/reference
	@printf '[REF  ] mlp_reference\n'
	@$(PYTHON) model/generate_mlp_reference.py > build/reference/reference.log
	@cat build/reference/reference.log

$(REFERENCE_FILES) &: $(REFERENCE_DEPS)
	@printf '[GEN  ] mlp_reference fixtures\n'
	@$(PYTHON) model/generate_mlp_reference.py

build:
	@test -n "$(MODULE)" || (echo "No module selected. See 'make list-tests'."; exit 1)
	@test -f "$(TB_FILE)" || (echo "Unknown MODULE '$(MODULE)'. See 'make list-tests'."; exit 1)
	@mkdir -p "$(BUILD_DIR)"
	@if [ "$(MODULE)" = "mlp_reference" ]; then \
		$(MAKE) --no-print-directory $(REFERENCE_FILES) >"$(REF_LOG)"; \
	fi
	@printf '[BUILD] %s\n' "$(MODULE)"
	@$(VERILATOR) $(VERILATOR_BUILD_FLAGS) >"$(BUILD_LOG)" 2>&1 || { \
		printf '[FAIL ] %s build\n' "$(MODULE)"; \
		cat "$(BUILD_LOG)"; \
		exit 1; \
	}
	@printf '[ OK  ] %s build\n' "$(MODULE)"

run: build
	@printf '[RUN  ] %s\n' "$(MODULE)"
	@$(SIM_BIN) >"$(TEST_LOG)" 2>&1 || { \
		printf '[FAIL ] %s test\n' "$(MODULE)"; \
		grep -v 'Verilog $$finish' "$(TEST_LOG)" || true; \
		exit 1; \
	}
	@grep -v 'Verilog $$finish' "$(TEST_LOG)" || true
	@printf '[ OK  ] %s test\n' "$(MODULE)"

test:
	@set -e; \
	for module in $(TEST_MODULES); do \
		$(MAKE) --no-print-directory run $$module; \
	done

lint:
	@set -e; \
	for top in $(LINT_TOPS); do \
		$(MAKE) --no-print-directory lint-top TOP_MODULE=$$top; \
	done

lint-top:
	@printf '[LINT ] %s\n' "$(TOP_MODULE)"
	@$(VERILATOR) $(VERILATOR_LINT_FLAGS) --top-module "$(TOP_MODULE)"
	@printf '[ OK  ] %s lint\n' "$(TOP_MODULE)"

lint-module:
	@test -n "$(MODULE)" || (echo "No module selected. See 'make list-tests'."; exit 1)
	@test -f "$(TB_FILE)" || (echo "Unknown MODULE '$(MODULE)'. See 'make list-tests'."; exit 1)
	@printf '[LINT ] %s\n' "$(TB_TOP)"
	@$(VERILATOR) $(VERILATOR_WARN_FLAGS) --lint-only $(RTL_FILES) "$(TB_FILE)" --top-module "$(TB_TOP)"
	@printf '[ OK  ] %s lint\n' "$(MODULE)"

verilator-cmd:
	@test -n "$(MODULE)" || (echo "No module selected. See 'make list-tests'."; exit 1)
	@test -f "$(TB_FILE)" || (echo "Unknown MODULE '$(MODULE)'. See 'make list-tests'."; exit 1)
	@printf '%s %s\n' "$(VERILATOR)" '$(VERILATOR_BUILD_FLAGS)'

verilator-lint-cmd:
	@printf '%s %s --top-module %s\n' "$(VERILATOR)" '$(VERILATOR_LINT_FLAGS)' "$(TOP_MODULE)"

host-help:
	@$(PYTHON) host/infer_uart.py --help

host-infer:
	@test -n "$(PORT)" || (echo "Set PORT=/dev/ttyUSB0"; exit 1)
	@test -n "$(IMAGE)" || (echo "Set IMAGE=path/to/image.raw"; exit 1)
	@$(PYTHON) host/infer_uart.py "$(PORT)" "$(IMAGE)" $(HOST_ARGS)

host-reference-image: reference
	@$(PYTHON) host/write_reference_image.py

hw-validate: host-reference-image
	@test -n "$(PORT)" || (echo "Set PORT=/dev/ttyUSB0"; exit 1)
	@$(PYTHON) host/infer_uart.py "$(PORT)" "$(REFERENCE_IMAGE)" --baud "$(BAUD)" --compare-reference tb/data $(HOST_ARGS)

fpga-synth:
	@mkdir -p "$(FPGA_DIR)"
	@printf '[SYNTH] %s\n' "$(BOARD_TOP)"
	yosys -p "read_verilog -sv $(RTL_FILES); synth_gowin -top $(BOARD_TOP) -json $(FPGA_JSON)"

fpga-pnr: fpga-synth
	@printf '[PNR  ] %s\n' "$(BOARD_TOP)"
	nextpnr-himbaechel \
		--json "$(FPGA_JSON)" \
		--write "$(FPGA_PNR_JSON)" \
		--device "$(DEVICE)" \
		--vopt family="$(FAMILY)" \
		--vopt cst="$(BOARD_CST)"

fpga-pack: fpga-pnr
	@printf '[PACK ] %s\n' "$(FPGA_BITSTREAM)"
	gowin_pack -d "$(FAMILY)" -o "$(FPGA_BITSTREAM)" "$(FPGA_PNR_JSON)"

fpga-build: fpga-pack
	@printf '[ OK  ] %s\n' "$(FPGA_BITSTREAM)"

fpga-program: fpga-build
	@printf '[PROG ] %s\n' "$(FPGA_BITSTREAM)"
	openFPGALoader -c "$(LOADER_CABLE)" "$(FPGA_BITSTREAM)"

$(MODULES):
	@:

clean:
	rm -rf build obj_dir *.vcd
