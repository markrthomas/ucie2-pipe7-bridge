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

# Make the shared models + vector generator importable from the test.
export PYTHONPATH := $(abspath ../common/models):$(abspath ../common/vectors):$(PYTHONPATH)

# Verilator needs SV + timing control for cocotb clock/reset stimulus.
ifeq ($(SIM),verilator)
    EXTRA_ARGS += --trace --timing -Wno-fatal
endif
# Icarus (the independent engine for the functional-coverage tier) needs SV-2012.
ifeq ($(SIM),icarus)
    COMPILE_ARGS += -g2012
endif

# ---- Line-coverage build (Phase F increment 2) ------------------------------
# INERT unless RTL_COVERAGE=1, so `make pyuvm`/`make fcov` build exactly as before.
# (NOT named COVERAGE: make exports command-line variables, and cocotb 2.x reads
# a COVERAGE env var as a request for *Python* coverage and aborts without the
# `coverage` module — caught by the CI run of this target.)
# `make coverage` at the repo root sets it. `--coverage-line` instruments line +
# branch points only (no toggle/user); tools/coverage_report.py scores the line
# points. cocotb's verilator main calls VerilatedCov::write() at end of sim,
# which drops `coverage.dat` in this directory; the root `coverage` recipe moves
# it into build/coverage/. A SEPARATE SIM_BUILD keeps the instrumented objects
# out of the gate's sim_build, so the --coverage-free builds are untouched.
ifeq ($(RTL_COVERAGE),1)
    SIM_BUILD  := $(abspath cov_build)
    EXTRA_ARGS += --coverage-line
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf sim_build cov_build build results.xml coverage.dat __pycache__
