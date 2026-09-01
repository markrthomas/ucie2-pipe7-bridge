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
# Package first (declares types used by the rest), then every other rtl source.
RTL_SRCS  := $(RTL_PKG) $(filter-out $(RTL_PKG),$(wildcard $(RTL_DIR)/*.sv))
RTL_TOP   := ucie2_pipe7_bridge

.PHONY: default help lint pyuvm fcov lint-uvm uvm trace-compare \
        railway-prebuild railway-template railway-swarm-probe railway-swarm \
        railway-swarm-agents clean

# Functional-coverage tier engine: Icarus in CI (independent from Verilator);
# override locally with `make fcov FCOV_SIM=verilator`.
FCOV_SIM ?= icarus

default: help

help:
	@echo "ucie2-pipe7-bridge targets:"
	@echo "  make lint          RTL strict lint (Verilator -Wall)          [local]"
	@echo "  make pyuvm         PyUVM-on-cocotb tier                        [local]"
	@echo "  make fcov          functional coverage (cocotb_coverage/Icarus) [CI; local: FCOV_SIM=verilator]"
	@echo "  make lint-uvm      elaborate-only lint of the SV UVM env       [local]"
	@echo "  make uvm           full SV UVM --binary build+run              [CI/Railway]"
	@echo "  make trace-compare cycle-accurate PyUVM==UVM trace diff        [CI/Railway]"
	@echo "  make railway-prebuild  build the prebuilt verilator-uvm image  [Docker]"
	@echo "  make railway-template  build the 4GB sandbox toolchain template [Railway]"
	@echo "  make railway-swarm-probe   one cheap sandbox: RAM/os report    [dry-run; SWARM_APPLY=1]"
	@echo "  make railway-swarm     N sandboxes: light elaborate smoke       [dry-run; SWARM_APPLY=1]"
	@echo "  make railway-swarm-agents  AI-dev slice swarm (ca --claude)     [dry-run; SWARM_APPLY=1]"
	@echo "                             (heavy --binary + trace_compare stay in CI)"
	@echo "  make clean         remove build artifacts"

# ---- RTL lint (the primary local gate) --------------------------------------
lint:
	$(VERILATOR) --lint-only -Wall -sv --top-module $(RTL_TOP) $(RTL_SRCS)
	@echo "[lint] RTL OK"

# ---- PyUVM-on-cocotb tier (runs locally) ------------------------------------
# Delegates to the cocotb Makefile. SIM/simulator selection lives there.
pyuvm:
	$(MAKE) -C dv/pyuvm

# ---- Functional coverage tier (cocotb_coverage; Icarus in CI) ---------------
fcov:
	$(MAKE) -C dv/pyuvm MODULE=test_fcov SIM=$(FCOV_SIM)

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

# ---- Railway cloud swarm (CI/Railway have the RAM the local box lacks) -------
# Prebuild the verilator-uvm toolchain image so swarm workers boot hot instead
# of building Verilator from source. `docker` here is podman-shim-friendly.
DOCKER      ?= docker
SWARM_IMAGE ?= ghcr.io/markrthomas/ucie2-pipe7-uvm:latest

railway-prebuild:
	$(DOCKER) build -t $(SWARM_IMAGE) -f Dockerfile .
	@echo "[railway-prebuild] built $(SWARM_IMAGE) — push with: $(DOCKER) push $(SWARM_IMAGE)"
	@echo "[railway-prebuild] (CI publishes it via .github/workflows/prebuild-image.yml)"

# Build the light-tier sandbox template so 4 GB sandboxes boot with the toolchain
# for `make lint` + `make fcov` (apt verilator/iverilog + cocotb/pyuvm/cov). Fast
# to build (apt+pip, no source compile). The heavy from-source UVM Verilator is
# NOT here — that lives in CI / the GHCR image. Content-addressed + cached server
# side, so a re-run with identical steps is an instant hit. Provisions build
# compute (costs money): run it yourself with `!` or approve the prompt.
SWARM_TEMPLATE ?= uvm
railway-template:
	$(RAILWAY_CLI) sandbox template build --name $(SWARM_TEMPLATE) --wait \
	  -c 'apt-get update && apt-get install -y --no-install-recommends git make g++ ca-certificates verilator iverilog python3 python3-dev python3-pip python3-venv' \
	  -c 'pip install --break-system-packages "cocotb==1.9.2" "cocotb_coverage==1.2.0" "pyuvm==4.0.1"'
	@echo "[railway-template] built template '$(SWARM_TEMPLATE)'. Use: railway sandbox create --template $(SWARM_TEMPLATE)"

# Fire the cloud swarm. DRY-RUN by default (prints the railway commands, touches
# nothing); set SWARM_APPLY=1 to actually provision. Tune with N=, SEEDS=, REF=.
# The positional mode arg to the script is authoritative (don't set MODE= here).
railway-swarm-probe:
	RAILWAY="$(RAILWAY_CLI)" $(SWARM_ENV) tools/railway_swarm.sh probe

railway-swarm:
	RAILWAY="$(RAILWAY_CLI)" $(SWARM_ENV) tools/railway_swarm.sh gate

railway-swarm-agents:
	RAILWAY="$(RAILWAY_CLI)" $(SWARM_ENV) tools/railway_swarm.sh agents

# Point at whatever railway binary is on PATH (falls back to `railway`).
RAILWAY_CLI ?= $(shell command -v railway 2>/dev/null || echo railway)
SWARM_ENV   ?=

clean:
	-$(MAKE) -C dv/pyuvm clean
	-$(MAKE) -C dv/uvm/vlt clean
	rm -rf obj_dir report
