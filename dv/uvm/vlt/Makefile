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
VEC       ?=
VEC_WORDS ?=
N_FLITS   ?=
RUN_PCLK  ?=
STIM_PLUSARGS := $(if $(VEC),+VEC=$(VEC)) $(if $(VEC_WORDS),+VEC_WORDS=$(VEC_WORDS)) \
                 $(if $(N_FLITS),+N_FLITS=$(N_FLITS)) $(if $(RUN_PCLK),+RUN_PCLK=$(RUN_PCLK))

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

# ---- Back-to-back (B2B) two-bridge configs (Phase H, SV UVM tier) -----------
# Additive: each config has its OWN top / package / interface, so the sacred
# single-bridge `lint`/`run` (and its byte-identical trace) are untouched. The
# bound SVA checker (ucie2_pipe7_sva.sv) is deliberately NOT compiled here -- it
# binds by module name to every ucie2_pipe7_bridge, so with two idle-ended
# bridges its directed-round-trip properties could false-fire; the B2B tier is
# scoreboard-gated instead. Stimulus flows via the same +VEC/+N_FLITS/+RUN_PCLK
# plusargs as `run` (config-pcie adds +VEC via a pre-framed PIPE word vector).
.PHONY: lint-b2b lint-b2b-ucie lint-b2b-pcie run-b2b run-b2b-ucie run-b2b-pcie

HARNESS_DIR := $(abspath $(VLT_DIR)/../../harness)
B2B         := $(abspath $(SV)/b2b)

B2B_UCIE_SRCS := $(RTL_SRCS) $(B2B)/b2b_ucie_if.sv $(B2B)/b2b_ucie_uvm_pkg.sv \
                 $(HARNESS_DIR)/b2b_ucie_pcie_ucie.sv $(B2B)/tb_b2b_ucie.sv
B2B_PCIE_SRCS := $(RTL_SRCS) $(B2B)/b2b_pcie_if.sv $(B2B)/b2b_pcie_uvm_pkg.sv \
                 $(HARNESS_DIR)/b2b_pcie_ucie_pcie.sv $(B2B)/tb_b2b_pcie.sv

lint-b2b: lint-b2b-ucie lint-b2b-pcie
run-b2b:  run-b2b-ucie run-b2b-pcie

lint-b2b-ucie:
	$(VERILATOR) $(LINTFLAGS) --top-module tb_b2b_ucie $(INCS) $(UVM_HDR) $(B2B_UCIE_SRCS)
	@echo "[lint-uvm] B2B UCIe env elaborates OK"

lint-b2b-pcie:
	$(VERILATOR) $(LINTFLAGS) --top-module tb_b2b_pcie $(INCS) $(UVM_HDR) $(B2B_PCIE_SRCS)
	@echo "[lint-uvm] B2B PCIe env elaborates OK"

# The `run` pass/fail check without the [SVA] branch (no bound checker here).
define B2B_RUN_CHECK
	@echo "----- UVM report counts -----"
	@grep -E "UVM_(INFO|WARNING|ERROR|FATAL) :" $(1)/run.log || true
	@if grep -qE "UVM_(ERROR|FATAL) :[[:space:]]*[1-9]" $(1)/run.log; then \
	  echo "FAIL: reported UVM_ERROR/UVM_FATAL"; exit 1; \
	elif ! grep -qE "UVM_INFO :" $(1)/run.log; then \
	  echo "FAIL: no UVM report (crash before report_phase?)"; exit 1; \
	else echo "PASS: clean UVM report (0 errors, 0 fatals)"; fi
endef

run-b2b-ucie:
	rm -rf $(OBJ)/b2b_ucie && mkdir -p $(OBJ)/b2b_ucie
	$(VERILATOR) $(VFLAGS) --top-module tb_b2b_ucie --Mdir $(OBJ)/b2b_ucie $(INCS) \
	  $(UVM_HDR) $(UVM_DPI) $(B2B_UCIE_SRCS)
	$(OBJ)/b2b_ucie/Vtb_b2b_ucie $(UVM_PLUSARGS) $(STIM_PLUSARGS) 2>&1 | tee $(OBJ)/b2b_ucie/run.log
	$(call B2B_RUN_CHECK,$(OBJ)/b2b_ucie)

run-b2b-pcie:
	rm -rf $(OBJ)/b2b_pcie && mkdir -p $(OBJ)/b2b_pcie
	$(VERILATOR) $(VFLAGS) --top-module tb_b2b_pcie --Mdir $(OBJ)/b2b_pcie $(INCS) \
	  $(UVM_HDR) $(UVM_DPI) $(B2B_PCIE_SRCS)
	$(OBJ)/b2b_pcie/Vtb_b2b_pcie $(UVM_PLUSARGS) $(STIM_PLUSARGS) 2>&1 | tee $(OBJ)/b2b_pcie/run.log
	$(call B2B_RUN_CHECK,$(OBJ)/b2b_pcie)

clean:
	rm -rf $(OBJ)
