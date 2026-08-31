# =============================================================================
# SV UVM-on-Verilator flow for the UCIe2->PIPE7 bridge (PLAN Phase D).
#
# Requires a UVM-capable Verilator (>= 5.050) and the bundled Accellera UVM
# 2020.3.1 library — the apt/OSS-CAD-Suite Verilator is NOT UVM-capable. Set
# UVM_HOME to the dir holding uvm_pkg_all_v2020_3_1_dpi.svh (e.g. a from-source
# Verilator's test_regress/t/uvm). This project does NOT use OSS CAD Suite.
#
#   make lint    elaborate-only (~330 MB, seconds)   -> runs locally + CI
#   make run     full --binary build + run           -> CI / Railway only
#   make ci      lint then run
#
# NOTE: `run` OOMs an ~8 GB box during the UVM precompiled-header compile — do it
# in CI/Railway, not on the local host (per CLAUDE.md).
# =============================================================================

VERILATOR ?= verilator
UVM_HOME  ?= $(error Set UVM_HOME to the bundled Verilator UVM dir, e.g. \
  ~/verilator/test_regress/t/uvm)

UVM_HDR := $(UVM_HOME)/uvm_pkg_all_v2020_3_1_dpi.svh
UVM_DPI := $(UVM_HOME)/v2020_3_1/dpi/uvm_dpi.cc

BUILD_JOBS   ?= 1
CFLAGS_MODEL ?= -O0

VLT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SV      := $(abspath $(VLT_DIR)/../sv)
RTL     := $(abspath $(VLT_DIR)/../../../rtl)
OBJ     := $(VLT_DIR)/obj
TOP     := tb_ucie2_pipe7

INCS := +incdir+$(SV) +incdir+$(UVM_HOME) +incdir+$(VLT_DIR)

# Compile order: RTL package, RTL DUT, UVM interface, UVM env package, tb top.
SRCS := $(RTL)/ucie2_pipe7_pkg.sv \
        $(RTL)/ucie2_pipe7_bridge.sv \
        $(SV)/ucie2_pipe7_if.sv \
        $(SV)/ucie2_pipe7_uvm_pkg.sv \
        $(SV)/tb_ucie2_pipe7.sv

LINTFLAGS ?= --lint-only --timing -Wno-fatal -Wno-TIMESCALEMOD
VFLAGS    ?= --binary --timing --vpi -j $(BUILD_JOBS) --build-jobs $(BUILD_JOBS) \
             -Wno-fatal -Wno-TIMESCALEMOD --CFLAGS "$(CFLAGS_MODEL)"
UVM_PLUSARGS ?= +UVM_NO_RELNOTES

.PHONY: lint run ci clean

# Elaborate-only: the RAM-safe gate that runs on the local host.
lint:
	$(VERILATOR) $(LINTFLAGS) --top-module $(TOP) $(INCS) $(UVM_HDR) $(SRCS)
	@echo "[lint-uvm] SV UVM env elaborates OK"

# Full build + run — CI / Railway only. Fails on any UVM_ERROR/UVM_FATAL.
run:
	rm -rf $(OBJ)
	mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --top-module $(TOP) --Mdir $(OBJ) $(INCS) \
	  $(UVM_HDR) $(UVM_DPI) $(SRCS)
	$(OBJ)/V$(TOP) $(UVM_PLUSARGS) +TRACE=$(OBJ)/bridge.trace 2>&1 | tee $(OBJ)/run.log
	@echo "----- UVM report counts -----"
	@grep -E "UVM_(INFO|WARNING|ERROR|FATAL) :" $(OBJ)/run.log || true
	@if grep -qE "UVM_(ERROR|FATAL) :[[:space:]]*[1-9]" $(OBJ)/run.log; then \
	  echo "FAIL: reported UVM_ERROR/UVM_FATAL"; exit 1; \
	elif ! grep -qE "UVM_INFO :" $(OBJ)/run.log; then \
	  echo "FAIL: no UVM report (crash before report_phase?)"; exit 1; \
	else echo "PASS: clean UVM report (0 errors, 0 fatals)"; fi

ci: lint run

clean:
	rm -rf $(OBJ)
