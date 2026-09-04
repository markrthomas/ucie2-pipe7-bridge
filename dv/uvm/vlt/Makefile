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

# Compile order: RTL package first, then all RTL (FDI front-end + datapath + top),
# then the bound SVA checker, the UVM interface, UVM env package, tb top.
RTL_SRCS := $(RTL)/ucie2_pipe7_pkg.sv \
            $(filter-out $(RTL)/ucie2_pipe7_pkg.sv,$(wildcard $(RTL)/*.sv))
SRCS := $(RTL_SRCS) \
        $(SV)/ucie2_pipe7_sva.sv \
        $(SV)/ucie2_pipe7_if.sv \
        $(SV)/ucie2_pipe7_uvm_pkg.sv \
        $(SV)/tb_ucie2_pipe7.sv

# --assert makes the bound SVA checker (ucie2_pipe7_sva.sv, Phase F increment 1)
# a real runtime check in the --binary run, and elaborates it under lint. The
# checker deliberately lives here and NOT under rtl/, so the root Makefile's
# rtl/*.sv wildcard — and therefore `make lint`/`pyuvm`/`fcov` — is untouched.
LINTFLAGS ?= --lint-only --timing --assert -Wno-fatal -Wno-TIMESCALEMOD
VFLAGS    ?= --binary --timing --vpi --assert -j $(BUILD_JOBS) --build-jobs $(BUILD_JOBS) \
             -Wno-fatal -Wno-TIMESCALEMOD --CFLAGS "$(CFLAGS_MODEL)"
UVM_PLUSARGS ?= +UVM_NO_RELNOTES

# Default-test stimulus, passed through from the root Makefile. When empty (e.g. a
# bare `make -C dv/uvm/vlt run`, or the EDA Playground bundle) the SV sequence
# falls back to its compiled-in directed ramp and the N_FLITS/RUN_PCLK localparams.
VEC      ?=
N_FLITS  ?=
RUN_PCLK ?=
STIM_PLUSARGS := $(if $(VEC),+VEC=$(VEC)) $(if $(N_FLITS),+N_FLITS=$(N_FLITS)) \
                 $(if $(RUN_PCLK),+RUN_PCLK=$(RUN_PCLK))

.PHONY: lint run ci clean

# Elaborate-only: the RAM-safe gate that runs on the local host.
lint:
	$(VERILATOR) $(LINTFLAGS) --top-module $(TOP) $(INCS) $(UVM_HDR) $(SRCS)
	@echo "[lint-uvm] SV UVM env elaborates OK"

# Full build + run — CI / Railway only. Fails on any UVM_ERROR/UVM_FATAL, and on
# any `[SVA]` failure from the bound checker (ucie2_pipe7_sva.sv).
run:
	rm -rf $(OBJ)
	mkdir -p $(OBJ)
	$(VERILATOR) $(VFLAGS) --top-module $(TOP) --Mdir $(OBJ) $(INCS) \
	  $(UVM_HDR) $(UVM_DPI) $(SRCS)
	$(OBJ)/V$(TOP) $(UVM_PLUSARGS) $(STIM_PLUSARGS) +TRACE=$(OBJ)/bridge.trace 2>&1 | tee $(OBJ)/run.log
	@echo "----- UVM report counts -----"
	@grep -E "UVM_(INFO|WARNING|ERROR|FATAL) :" $(OBJ)/run.log || true
	@if grep -qE "UVM_(ERROR|FATAL) :[[:space:]]*[1-9]" $(OBJ)/run.log; then \
	  echo "FAIL: reported UVM_ERROR/UVM_FATAL"; exit 1; \
	elif grep -qF "[SVA]" $(OBJ)/run.log; then \
	  echo "FAIL: bound SVA assertion failure (see [SVA] lines above)"; exit 1; \
	elif ! grep -qE "UVM_INFO :" $(OBJ)/run.log; then \
	  echo "FAIL: no UVM report (crash before report_phase?)"; exit 1; \
	else echo "PASS: clean UVM report (0 errors, 0 fatals)"; fi

ci: lint run

clean:
	rm -rf $(OBJ)
