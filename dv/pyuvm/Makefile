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
# Extra sources appended after the rtl/ set (e.g. the dv/harness B2B wrapper tops
# for the back-to-back configs). Empty for the single-bridge default. The root
# Makefile's b2b-* targets set both this and TOPLEVEL below.
EXTRA_VERILOG ?=
VERILOG_SOURCES += $(EXTRA_VERILOG)
# TOPLEVEL is overridable so the B2B wrappers can be elaborated as the top; the
# default is the single bridge.
TOPLEVEL ?= ucie2_pipe7_bridge
# Default test: the directed Gen5 FDI round-trip (proves data flows + emits the
# cycle-accurate trace). test_smoke.py remains for a quick idle bring-up check.
MODULE   ?= test_roundtrip

# Make the shared models + vector generator importable from the test.
export PYTHONPATH := $(abspath ../common/models):$(abspath ../common/vectors):$(PYTHONPATH)

# Verilator needs SV + timing control for cocotb clock/reset stimulus.
#
# NOTE (Phase G increment 3): `--trace` is deliberately NOT here. cocotb appends
# EXTRA_ARGS to BOTH the verilate command and the simulation command, so a
# `--trace` in this variable compiled the VCD tracer in *and* switched it on at
# run time — the gate silently wrote a 170 KB dv/pyuvm/dump.vcd on every
# `make pyuvm`/`make fcov`. The gate is wave-free again; waveforms are opt-in via
# the WAVES=1 block below (see `make waves` / `make wave` at the repo root).
ifeq ($(SIM),verilator)
    EXTRA_ARGS += --timing -Wno-fatal
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

# ---- Waveform dump build (Phase G increment 3) ------------------------------
# INERT unless WAVES=1, so `make pyuvm`/`make fcov`/`make coverage` build and run
# EXACTLY as before — no tracer compiled in, no dump written, no runtime cost, and
# the byte-identical per-cycle trace (build/bridge.trace) is untouched.
#
# WAVES=1 is set ONLY by the repo-root `waves`/`wave`/`wave-check` targets. It:
#   * builds into a SEPARATE SIM_BUILD (wave_build/), so the gate's own sim_build
#     objects are never replaced by instrumented ones (same trick as cov_build);
#   * adds `-DWAVES` — the one dedicated define reserved for "dump waveforms"
#     project-wide, so the deferred SV UVM $dumpfile hook can key off the same
#     name instead of inventing a second switch;
#   * adds `--trace-fst --trace-structs` at COMPILE time only (COMPILE_ARGS, not
#     EXTRA_ARGS) so VM_TRACE_FST=1 and cocotb's verilator main writes FST; and
#   * adds `--trace --trace-file <fst>` at RUN time only (SIM_ARGS), which is what
#     actually opens the dump.
# Verilator's own FST writer + apt gtkwave. NOT OSS CAD Suite.
WAVE_DIR  ?= $(abspath ../../build/waves)
WAVE_FILE ?= $(WAVE_DIR)/$(MODULE).fst

ifeq ($(WAVES),1)
    SIM_BUILD    := $(abspath wave_build)
    COMPILE_ARGS += -DWAVES --trace-fst --trace-structs
    SIM_ARGS     += --trace --trace-file $(WAVE_FILE)
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -rf sim_build cov_build wave_build b2b_ucie_build b2b_pcie_build \
	       b2b_ucie_fd_build b2b_pcie_fd_build \
	       build results.xml coverage.dat dump.vcd dump.fst __pycache__
