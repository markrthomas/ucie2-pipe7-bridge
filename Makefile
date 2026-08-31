# =============================================================================
# ucie2-pipe7-bridge — single entry point for every flow.
#
# Local host runs the gates that fit an ~8 GB box:
#   make lint       RTL strict lint (Verilator -Wall)
#   make pyuvm      PyUVM-on-cocotb tier (needs a cocotb simulator on PATH)
#   make lint-uvm   ELABORATE-ONLY lint of the SV UVM env (never --binary here)
#
# CI / Railway container additionally run the heavy gates:
#   make uvm        full SV UVM --binary build + run (from-source Verilator >=5.050)
#   make trace-compare   cycle-accurate PyUVM-trace == UVM-trace diff
#
# Toolchain is overridable so this works with whatever is on PATH; the
# reproducible envs (.devcontainer, Dockerfile*, CI) install apt verilator/
# iverilog + a from-source UVM Verilator and do NOT use OSS CAD Suite.
# =============================================================================

VERILATOR ?= verilator
IVERILOG  ?= iverilog
PYTHON    ?= python3

RTL_DIR   := rtl
RTL_PKG   := $(RTL_DIR)/ucie2_pipe7_pkg.sv
RTL_SRCS  := $(RTL_PKG) $(RTL_DIR)/ucie2_pipe7_bridge.sv
RTL_TOP   := ucie2_pipe7_bridge

.PHONY: default help lint pyuvm lint-uvm uvm trace-compare clean

default: help

help:
	@echo "ucie2-pipe7-bridge targets:"
	@echo "  make lint          RTL strict lint (Verilator -Wall)          [local]"
	@echo "  make pyuvm         PyUVM-on-cocotb tier                        [local]"
	@echo "  make lint-uvm      elaborate-only lint of the SV UVM env       [local]"
	@echo "  make uvm           full SV UVM --binary build+run              [CI/Railway]"
	@echo "  make trace-compare cycle-accurate PyUVM==UVM trace diff        [CI/Railway]"
	@echo "  make clean         remove build artifacts"

# ---- RTL lint (the primary local gate) --------------------------------------
lint:
	$(VERILATOR) --lint-only -Wall -sv $(RTL_SRCS)
	@echo "[lint] RTL OK"

# ---- PyUVM-on-cocotb tier (runs locally) ------------------------------------
# Delegates to the cocotb Makefile. SIM/simulator selection lives there.
pyuvm:
	$(MAKE) -C dv/pyuvm

# ---- SV UVM env: lint only here (full build is CI/Railway) ------------------
lint-uvm:
	$(MAKE) -C dv/uvm/vlt lint

# ---- SV UVM env: full --binary build + run (CI/Railway only) ----------------
uvm:
	$(MAKE) -C dv/uvm/vlt run

# ---- Cycle-accurate cross-check: PyUVM trace vs UVM trace -------------------
trace-compare:
	$(PYTHON) tools/trace_compare.py \
	  --pyuvm dv/pyuvm/build/bridge.trace \
	  --uvm   dv/uvm/vlt/obj/bridge.trace

clean:
	-$(MAKE) -C dv/pyuvm clean
	-$(MAKE) -C dv/uvm/vlt clean
	rm -rf obj_dir report
