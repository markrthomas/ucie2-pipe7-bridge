# PyUVM-on-cocotb tier (PLAN Phase C). Runs locally under whatever cocotb
# simulator is on PATH; CI uses apt verilator (NOT OSS CAD Suite).
#
#   make            # default: smoke test (Item 11 grows this into the full env)
#   make SIM=icarus # pick a simulator (default: verilator)
#
# The DUT is currently the Phase-A shell, so the smoke drives clocks/reset and
# emits the canonical per-cycle trace (build/bridge.trace) that trace_compare.py
# checks against the SV UVM trace.

TOPLEVEL_LANG ?= verilog
SIM           ?= verilator

RTL := $(abspath ../../rtl)
# Package first, then every other rtl source (FDI front-end + datapath + top).
VERILOG_SOURCES := $(RTL)/ucie2_pipe7_pkg.sv \
                   $(filter-out $(RTL)/ucie2_pipe7_pkg.sv,$(wildcard $(RTL)/*.sv))
TOPLEVEL := ucie2_pipe7_bridge
# Default test: the directed Gen5 FDI round-trip (proves data flows + emits the
# cycle-accurate trace). test_smoke.py remains for a quick idle bring-up check.
MODULE   ?= test_roundtrip

# Make the shared models importable from the test.
export PYTHONPATH := $(abspath ../common/models):$(PYTHONPATH)

# Verilator needs SV + timing control for cocotb clock/reset stimulus.
ifeq ($(SIM),verilator)
    EXTRA_ARGS += --trace --timing -Wno-fatal
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf sim_build build results.xml __pycache__
