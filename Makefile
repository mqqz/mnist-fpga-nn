VERILATOR ?= verilator
UV        ?= uv
PYTHON    ?= $(UV) run python
CXXFLAGS  ?= -std=c++17

export CCACHE_DISABLE := 1

MODULES := \
	controller \
	controller_uart \
	matvec \
	mlp \
	mlp_reference \
	mlp_uart \
	params \
	relu \
	rom \
	uart_rx \
	uart_tx

RTL_FILES := $(sort $(abspath $(wildcard rtl/*.v)))
SIM_MAIN  := $(abspath sim_main.cpp)

DEVICE    ?= GW1NR-LV9QN88PC6/I5
FAMILY    ?= GW1N-9C
BOARD_TOP ?= board_top
BOARD_CST ?= cst/fpga_mlp.cst
FPGA_DIR  ?= build/fpga

FPGA_JSON        := $(FPGA_DIR)/$(BOARD_TOP).json
FPGA_PNR_JSON    := $(FPGA_DIR)/$(BOARD_TOP)_pnr.json
FPGA_BITSTREAM   := $(FPGA_DIR)/$(BOARD_TOP).fs
FPGA_SYNTH_LOG   := $(FPGA_DIR)/$(BOARD_TOP)_synth.log
FPGA_PNR_LOG     := $(FPGA_DIR)/$(BOARD_TOP)_pnr.log
FPGA_PACK_LOG    := $(FPGA_DIR)/$(BOARD_TOP)_pack.log
FPGA_PROGRAM_LOG := $(FPGA_DIR)/$(BOARD_TOP)_program.log

LOADER_BOARD ?= tangnano9k
LOADER_CABLE ?=
LOADER_ARGS  := $(if $(LOADER_CABLE),-c "$(LOADER_CABLE)",-b "$(LOADER_BOARD)")

BAUD            ?= 115200
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

TOP_MODULE ?= mlp_uart
LINT_TOPS  ?= mlp_uart controller mlp matvec board_top

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
	build run test check \
	lint lint-top lint-module \
	verilator-cmd verilator-lint-cmd \
	synth-cmd pnr-cmd pack-cmd program-cmd \
	image infer reference-image echo probe validate \
	synth pnr pack bitstream program \
	echo-bitstream echo-program \
	reference clean \
	$(MODULES)

all: check

help:
	@echo "Targets:"
	@echo "  make check                       Run tests, lint, and FPGA bitstream build"
	@echo "  make test                        Run the full Verilator test suite"
	@echo "  make test <module>               Run one module test, e.g. make test mlp"
	@echo "  make run <module>                Build and run one module simulation"
	@echo "  make lint                        Lint common RTL tops: $(LINT_TOPS)"
	@echo "  make bitstream                   Build the FPGA bitstream"
	@echo "  make program                     Build and program the FPGA"
	@echo "  make validate PORT=...           Run hardware inference against reference logits"
	@echo "  make image IMAGE=... OUTPUT=...  Convert PNG/JPEG/etc to raw 28x28"
	@echo "  make infer PORT=... IMAGE=...    Run UART inference"
	@echo "  make echo-program                Program the UART echo diagnostic bitstream"
	@echo "  make echo PORT=...               Validate the UART echo diagnostic"
	@echo "  make probe PORT=...              Probe MLP UART protocol status responses"
	@echo "  make reference                   Regenerate Python/RTL reference fixtures"
	@echo "  make reference-image             Write the reference raw image"
	@echo "  make list-tests                  List available module tests"
	@echo "  make clean                       Remove generated build output"
	@echo ""
	@echo "Variables:"
	@echo "  PORT=/dev/ttyUSB1                Serial port for infer/validate/echo/probe"
	@echo "  IMAGE=digit.png OUTPUT=input.raw Inputs for make image"
	@echo "  HOST_ARGS='--timeout 5'          Extra host-tool arguments"
	@echo "  DEVICE='$(DEVICE)' FAMILY='$(FAMILY)' BOARD_TOP='$(BOARD_TOP)'"
	@echo "  BOARD_CST='$(BOARD_CST)'"
	@echo "  LOADER_BOARD='$(LOADER_BOARD)' LOADER_CABLE='$(LOADER_CABLE)'"
	@echo "  TOP_MODULE=<top>                 RTL top for lint-top, default: $(TOP_MODULE)"
	@echo "  SIM_MAX_TICKS=<ticks>            Runtime timeout consumed by sim_main.cpp"

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
	@test -f "$(TB_FILE)" || (echo "Unknown module '$(MODULE)'. See 'make list-tests'."; exit 1)
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

check:
	@$(MAKE) --no-print-directory test
	@$(MAKE) --no-print-directory lint
	@$(MAKE) --no-print-directory bitstream

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
	@test -f "$(TB_FILE)" || (echo "Unknown module '$(MODULE)'. See 'make list-tests'."; exit 1)
	@printf '[LINT ] %s\n' "$(TB_TOP)"
	@$(VERILATOR) $(VERILATOR_WARN_FLAGS) --lint-only $(RTL_FILES) "$(TB_FILE)" --top-module "$(TB_TOP)"
	@printf '[ OK  ] %s lint\n' "$(MODULE)"

verilator-cmd:
	@test -n "$(MODULE)" || (echo "No module selected. See 'make list-tests'."; exit 1)
	@test -f "$(TB_FILE)" || (echo "Unknown module '$(MODULE)'. See 'make list-tests'."; exit 1)
	@printf '%s %s\n' "$(VERILATOR)" '$(VERILATOR_BUILD_FLAGS)'

verilator-lint-cmd:
	@printf '%s %s --top-module %s\n' "$(VERILATOR)" '$(VERILATOR_LINT_FLAGS)' "$(TOP_MODULE)"

image:
	@test -n "$(IMAGE)" || (echo "Set IMAGE=path/to/image.png"; exit 1)
	@test -n "$(OUTPUT)" || (echo "Set OUTPUT=path/to/image.raw"; exit 1)
	@$(PYTHON) host/prepare_image.py "$(IMAGE)" "$(OUTPUT)" $(HOST_ARGS)

infer:
	@test -n "$(PORT)" || (echo "Set PORT=/dev/ttyUSB1"; exit 1)
	@test -n "$(IMAGE)" || (echo "Set IMAGE=path/to/image.raw"; exit 1)
	@$(PYTHON) host/infer.py "$(PORT)" "$(IMAGE)" $(HOST_ARGS)

reference-image: reference
	@$(PYTHON) host/write_reference_image.py

echo:
	@test -n "$(PORT)" || (echo "Set PORT=/dev/ttyUSB1"; exit 1)
	@$(PYTHON) host/echo.py "$(PORT)" --baud "$(BAUD)" $(HOST_ARGS)

probe:
	@test -n "$(PORT)" || (echo "Set PORT=/dev/ttyUSB1"; exit 1)
	@$(PYTHON) host/probe.py "$(PORT)" --baud "$(BAUD)" $(HOST_ARGS)

validate: reference-image
	@test -n "$(PORT)" || (echo "Set PORT=/dev/ttyUSB1"; exit 1)
	@$(PYTHON) host/infer.py "$(PORT)" "$(REFERENCE_IMAGE)" --baud "$(BAUD)" --compare-reference tb/data $(HOST_ARGS)

synth:
	@mkdir -p "$(FPGA_DIR)"
	@printf '[SYNTH] %s\n' "$(BOARD_TOP)"
	@yosys -p "read_verilog -sv $(RTL_FILES); synth_gowin -top $(BOARD_TOP) -json $(FPGA_JSON)" >"$(FPGA_SYNTH_LOG)" 2>&1 || { \
		printf '[FAIL ] synth %s\n' "$(BOARD_TOP)"; \
		cat "$(FPGA_SYNTH_LOG)"; \
		exit 1; \
	}
	@printf '[ OK  ] synth log: %s\n' "$(FPGA_SYNTH_LOG)"

pnr: synth
	@printf '[PNR  ] %s\n' "$(BOARD_TOP)"
	@nextpnr-himbaechel \
		--json "$(FPGA_JSON)" \
		--write "$(FPGA_PNR_JSON)" \
		--device "$(DEVICE)" \
		--vopt family="$(FAMILY)" \
		--vopt cst="$(BOARD_CST)" >"$(FPGA_PNR_LOG)" 2>&1 || { \
		printf '[FAIL ] pnr %s\n' "$(BOARD_TOP)"; \
		cat "$(FPGA_PNR_LOG)"; \
		exit 1; \
	}
	@grep -E 'Device utilisation|LUT4:|BSRAM:|ERROR|WARN' "$(FPGA_PNR_LOG)" || true
	@grep 'Max frequency' "$(FPGA_PNR_LOG)" | tail -n 1 || true
	@printf '[ OK  ] pnr log: %s\n' "$(FPGA_PNR_LOG)"

pack: pnr
	@printf '[PACK ] %s\n' "$(FPGA_BITSTREAM)"
	@gowin_pack -d "$(FAMILY)" -o "$(FPGA_BITSTREAM)" "$(FPGA_PNR_JSON)" >"$(FPGA_PACK_LOG)" 2>&1 || { \
		printf '[FAIL ] pack %s\n' "$(BOARD_TOP)"; \
		cat "$(FPGA_PACK_LOG)"; \
		exit 1; \
	}
	@printf '[ OK  ] pack log: %s\n' "$(FPGA_PACK_LOG)"

bitstream: pack
	@printf '[ OK  ] %s\n' "$(FPGA_BITSTREAM)"

program: bitstream
	@printf '[PROG ] %s\n' "$(FPGA_BITSTREAM)"
	@openFPGALoader $(LOADER_ARGS) "$(FPGA_BITSTREAM)" >"$(FPGA_PROGRAM_LOG)" 2>&1 || { \
		printf '[FAIL ] program %s\n' "$(BOARD_TOP)"; \
		cat "$(FPGA_PROGRAM_LOG)"; \
		exit 1; \
	}
	@cat "$(FPGA_PROGRAM_LOG)"

synth-cmd:
	@printf '%s\n' 'yosys -p "read_verilog -sv $(RTL_FILES); synth_gowin -top $(BOARD_TOP) -json $(FPGA_JSON)"'

pnr-cmd:
	@printf '%s\n' 'nextpnr-himbaechel --json "$(FPGA_JSON)" --write "$(FPGA_PNR_JSON)" --device "$(DEVICE)" --vopt family="$(FAMILY)" --vopt cst="$(BOARD_CST)"'

pack-cmd:
	@printf '%s\n' 'gowin_pack -d "$(FAMILY)" -o "$(FPGA_BITSTREAM)" "$(FPGA_PNR_JSON)"'

program-cmd:
	@printf '%s\n' 'openFPGALoader $(LOADER_ARGS) "$(FPGA_BITSTREAM)"'

echo-bitstream:
	@$(MAKE) --no-print-directory bitstream BOARD_TOP=uart_echo_top

echo-program:
	@$(MAKE) --no-print-directory program BOARD_TOP=uart_echo_top

$(MODULES):
	@:

clean:
	rm -rf build obj_dir *.vcd
