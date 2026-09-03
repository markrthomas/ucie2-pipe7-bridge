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

.PHONY: default help lint pyuvm fcov lint-uvm uvm trace-compare coverage formal \
        metrics dashboard eda-playground eda-check waves wave wave-check wave-web \
        railway-prebuild railway-template railway-swarm-probe railway-swarm \
        railway-swarm-agents swarm clean

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
	@echo "  make coverage      RTL line coverage of the directed round-trip [local; post-gate]"
	@echo "                     (Verilator --coverage-line; prints [COV] line=NN.N%"
	@echo "                      plus an informational [COV] branch=NN.N%;"
	@echo "                      advisory floor — set a gate with COV_MIN=NN)"
	@echo "  make formal        SymbiYosys BMC of the FDI link FSM, the PIPE MAC  [local; post-gate]"
	@echo "                     ctrl FSM and the Gen5 gearbox (apt yosys+sby+z3;"
	@echo "                      prints [FORMAL] <job>: BMC depth N PASSED; skips"
	@echo "                      cleanly with exit 0 if sby is not installed)"
	@echo "  make metrics       append one DV-metrics row to metrics/metrics.db [local/CI; post-gate]"
	@echo "                     (runs METRICS_TIERS, parses the existing tier"
	@echo "                      banners; absent tiers = not-run, never fail;"
	@echo "                      migrates an older store to schema user_version=2"
	@echo "                      in place, preserving every row; also records"
	@echo "                      coverage branch%, per-job formal BMC depth,"
	@echo "                      round-trip sim cycles and collect peak RSS;"
	@echo "                      prints [METRICS] signals: …, [METRICS] regressions: N"
	@echo "                      (ADVISORY — never fails this or any other target)"
	@echo "                      and [METRICS] row #N appended to …;"
	@echo "                      METRICS_ARGS=--once-per-sha makes it idempotent —"
	@echo "                      a clean tree whose sha+env already has a row runs"
	@echo "                      nothing and appends nothing, so a push-triggered"
	@echo "                      CI job may commit the result back safely)"
	@echo "  make dashboard     regenerate metrics/dashboard.html from the DB [local/CI; post-gate]"
	@echo "                     (single self-contained file: inlined CSS + JS +"
	@echo "                      hand-drawn SVG, NO CDN and no external fetch;"
	@echo "                      per-branch trend charts over MEASURED points only,"
	@echo "                      a regression badge, a filterable/sortable run"
	@echo "                      history, one drill-down panel per tier and"
	@echo "                      git_sha → commit links (plain <a href>);"
	@echo "                      prints [DASH] wrote …, [DASH] trends: …,"
	@echo "                      [DASH] ux: …)"
	@echo "  make eda-playground regenerate the EDA Playground bundle          [local; off-gate]"
	@echo "                     (dv/uvm/eda_playground/: design.sv + testbench.sv"
	@echo "                      + all-in-one; flattens the UVM pkg includes)"
	@echo "  make eda-check     fail if the committed EDA bundle is stale       [local/CI; off-gate]"
	@echo "  make waves         dump an FST of the PyUVM round-trip             [local; OFF-GATE]"
	@echo "                     (TEST=roundtrip|smoke|fcov; WAVES=1 build in"
	@echo "                      dv/pyuvm/wave_build -> build/waves/test_<T>.fst;"
	@echo "                      prints [WAVES] wrote …)"
	@echo "  make wave          make waves, then open it in GTKWave             [local; OFF-GATE]"
	@echo "                     (layout dv/waves/<TEST>.gtkw, else default.gtkw;"
	@echo "                      needs a display — apt gtkwave, not OSS CAD Suite)"
	@echo "  make wave-check    drift-guard: every net path in every committed  [local; OFF-GATE]"
	@echo "                     dv/waves/*.gtkw must resolve in that target's"
	@echo "                     real dump hierarchy (via gtkwave's fst2vcd);"
	@echo "                     skips with exit 0 if fst2vcd is absent"
	@echo "  make wave-web      bundle that SAME dump + the vendored viewer     [local; OFF-GATE]"
	@echo "                     into ONE openable build/waves/test_<T>.html"
	@echo "                     (TEST=roundtrip|smoke|fcov; no desktop app, no"
	@echo "                      X11 — for the Codespace/browser workflow;"
	@echo "                      strictly self-contained: inlined CSS+JS + the"
	@echo "                      VCD as base64, NO CDN and no external fetch,"
	@echo "                      re-verified on the generated file; the default"
	@echo "                      view comes from the same dv/waves/*.gtkw layout;"
	@echo "                      prints [WAVES] wrote … N external ref(s))"
	@echo "  make railway-prebuild  build the prebuilt verilator-uvm image  [Docker]"
	@echo "  make railway-template  build the 4GB sandbox toolchain template [Railway]"
	@echo "  make railway-swarm-probe   one cheap sandbox: RAM/os report    [dry-run; SWARM_APPLY=1]"
	@echo "  make railway-swarm     N sandboxes: light elaborate smoke       [dry-run; SWARM_APPLY=1]"
	@echo "  make swarm             DV swarm: manager+subagents, opens a PR   [needs claude + creds]"
	@echo "  make railway-swarm-agents  Railway ca --claude swarm (alt path) [dry-run; SWARM_APPLY=1]"
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

# ---- RTL line coverage (Phase F increment 2) --------------------------------
# ADDITIVE and OUTSIDE the gate: never run inside/alongside lint/pyuvm/fcov/uvm/
# trace-compare, and never inside a timed DV run. It re-runs the SAME directed
# FDI round-trip (dv/pyuvm test_roundtrip) in a SEPARATE, --coverage-line
# instrumented build dir (dv/pyuvm/cov_build), so the gate's own build and the
# byte-identical per-cycle trace are untouched. Verilator-only (needs
# verilator_coverage); ~15 s.
#
# The floor is ADVISORY for now (report only). Once the baseline is agreed,
# enforce it with `make coverage COV_MIN=NN` (and add COV_MIN to the CI step).
COV_DIR            ?= build/coverage
COV_MIN            ?=
VERILATOR_COVERAGE ?= verilator_coverage

coverage:
	rm -f dv/pyuvm/coverage.dat dv/pyuvm/cov_build/coverage.dat
	$(MAKE) -C dv/pyuvm RTL_COVERAGE=1 SIM=verilator
	mkdir -p $(COV_DIR)
	@if   [ -f dv/pyuvm/coverage.dat ];           then mv -f dv/pyuvm/coverage.dat           $(COV_DIR)/coverage.dat; \
	 elif [ -f dv/pyuvm/cov_build/coverage.dat ]; then mv -f dv/pyuvm/cov_build/coverage.dat $(COV_DIR)/coverage.dat; \
	 else echo "[COV] ERROR: the instrumented run produced no coverage.dat"; exit 1; fi
	-$(VERILATOR_COVERAGE) --annotate $(COV_DIR)/annotated --annotate-min 1 \
	  $(COV_DIR)/coverage.dat
	$(PYTHON) tools/coverage_report.py $(COV_DIR)/coverage.dat \
	  --rtl-dir $(RTL_DIR) --report $(COV_DIR)/coverage.txt \
	  $(if $(COV_MIN),--min $(COV_MIN))

# ---- Formal / SymbiYosys BMC (Phase F increment 3) --------------------------
# ADDITIVE and OUTSIDE the gate: never run inside/alongside lint/pyuvm/fcov/uvm/
# trace-compare/coverage, reads no testbench, and writes only under build/formal/.
# It BMCs three tractable blocks against boundary properties (see formal/*.sv):
#   ucie2_fdi_link_fsm  -- no illegal FDI link state (the FLAGGED fdi_state_e
#                          encodings), stall-handshake well-formedness;
#   pipe7_mac_ctrl_fsm  -- PIPE 7.1 s8.4.1 rate/width legality, request/completion
#                          handshake well-formedness;
#   pipe7_gearbox       -- Gen5 128b/130b framer+deframer sync legality (no
#                          accumulator overflow/underflow, no illegally-framed
#                          block ever passed upstream).
# Toolchain: apt yosys + SymbiYosys (YosysHQ/sby) + z3 -- NOT OSS CAD Suite.
# Degrades gracefully: no sby on PATH => a skip message and exit 0.
# Bounded, not unbounded: the banner reports "BMC depth N".
formal:
	bash tools/formal_run.sh $(FORMAL_JOBS)

# ---- DV metrics + dashboard (Phase F inc 4; Phase G inc 1-2) ----------------
# ADDITIVE and OUTSIDE the gate. `metrics` runs the EXISTING tier targets
# unmodified (or reads the log the gate already wrote, e.g. dv/uvm/vlt/obj/
# run.log for `uvm`) and appends ONE row to the committed SQLite store; it
# never edits rtl/dv, never touches the trace emitters, and never changes the
# fixed clock/reset/stimulus schedule. `dashboard` only reads that store and
# rewrites one self-contained HTML file (inlined CSS + hand-drawn SVG, NO CDN).
# Neither is part of lint/pyuvm/fcov/uvm/trace-compare/coverage/formal, and
# neither may be run inside a timed DV run.
#
# A tier that cannot run here (missing tool, too heavy) is recorded as 'not-run'
# with source='none' — never as a failure, and never with a made-up number.
# `make metrics METRICS_ARGS=--carry-forward` fills such gaps from the newest
# measured row and tags them source='estimated' (off by default).
#
# Phase G increment 1: the store is at schema user_version = 2 and `metrics`
# migrates an older DB in place (ALTER TABLE ADD COLUMN; every row preserved).
# It additionally records coverage branch%, per-job formal BMC depth, the
# round-trip sim cycle count and the collect run's peak RSS -- each with its own
# *_source -- and prints `[METRICS] regressions: N` from a comparison against
# the newest prior MEASURED row on the same branch. That count is ADVISORY: it
# never changes the exit status of this target and no gate reads it.
#
# Phase G increment 2: `metrics METRICS_ARGS=--once-per-sha` is IDEMPOTENT — on a
# clean tree whose (git_sha, env) already has a row it runs nothing, appends
# nothing and exits 0 ("[METRICS] up to date: …"), so a push-to-main CI job can
# run this and commit the appended row + regenerated dashboard back without ever
# duplicating a row (that workflow is authored in
# docs/phase_g_env_enhancements.md for the maintainer to apply — it is its own
# job, on `main` only, and never runs on a PR branch). `dashboard` additionally
# emits a filterable/sortable run history, a per-tier drill-down and git_sha →
# commit links; still ONE self-contained file with inlined CSS/JS/SVG, no CDN
# and no external fetch (the generator re-checks that and prints the count).
#
# Stdlib Python only (sqlite3 module; the sqlite3 CLI is NOT required).
METRICS_DB    ?= metrics/metrics.db
METRICS_HTML  ?= metrics/dashboard.html
METRICS_TIERS ?= lint,pyuvm,fcov,coverage,formal,trace-compare
METRICS_ARGS  ?=

metrics:
	$(PYTHON) tools/metrics_collect.py --db $(METRICS_DB) --run "$(METRICS_TIERS)" \
	  $(METRICS_ARGS)

dashboard:
	$(PYTHON) tools/metrics_dashboard.py --db $(METRICS_DB) --out $(METRICS_HTML)

# ---- EDA Playground bundle (Phase G increment 5) ----------------------------
# ADDITIVE and OUTSIDE the gate. Concatenates the canonical rtl/ + dv/uvm/sv/
# sources (in the vlt compile order) into paste-ready EDA Playground files under
# dv/uvm/eda_playground/, flattening the UVM package's project `include lines so
# the bundle needs no include search path. It reads the sources only — it never
# edits rtl/dv, never touches the trace emitters, and is NOT the sacred gate
# (EDA Playground cannot run tools/trace_compare.py). `eda-check` is a dev-only
# drift-guard: it regenerates in memory and fails if the committed files are
# stale. Stdlib Python only.
eda-playground:
	$(PYTHON) tools/gen_eda_playground.py

eda-check:
	$(PYTHON) tools/gen_eda_playground.py --check

# ---- Waveforms: FST dump + GTKWave (Phase G increment 3) --------------------
# ADDITIVE, OFF-GATE and STRICTLY OPT-IN. Nothing below is reachable from
# lint/pyuvm/fcov/uvm/trace-compare/coverage/formal/metrics: FST dumping is
# compiled in only under the dedicated `-DWAVES` define (plus Verilator's
# `--trace-fst`), which ONLY these targets set, and it builds into its own
# dv/pyuvm/wave_build/ so the gate's sim_build objects are never instrumented.
# The gate therefore stays wave-free, GTKWave-independent and byte-identical.
#
#   make waves [TEST=roundtrip]      dump build/waves/test_<TEST>.fst
#   make wave  [TEST=roundtrip]      dump, then open it in GTKWave with the
#                                    curated dv/waves/<TEST>.gtkw layout
#                                    (falling back to dv/waves/default.gtkw)
#   make wave-check                  resolve every net path in every committed
#                                    layout against the real dump hierarchy
#   make wave-web [TEST=roundtrip]   bundle THAT SAME dump + the vendored
#                                    viewer into ONE openable, offline,
#                                    no-CDN build/waves/test_<TEST>.html
#                                    (Phase G increment 4)
#
# Dumps are build artifacts and git-ignored; only the curated dv/waves/*.gtkw
# layouts and the vendored dv/waves/viewer/ template are committed. Toolchain:
# Verilator's own FST writer + apt gtkwave (its fst2vcd for the drift-guard, and
# for the one-shot FST -> VCD conversion `wave-web` does at bundle time)
# -- NOT OSS CAD Suite.
#
# NOT extended to the SV UVM env (`waves-uvm`) in this increment: that flow needs
# the from-source UVM Verilator, which neither this host nor the light CI job has,
# so a `$dumpfile` hook there could not be run or proven here. See
# docs/phase_g_env_enhancements.md (increment 3, "Deferred").
TEST            ?= roundtrip
WAVE_DIR        ?= build/waves
WAVE_LAYOUT_DIR ?= dv/waves
GTKWAVE         ?= gtkwave

WAVE_MODULE := test_$(TEST)
WAVE_FST    := $(WAVE_DIR)/$(WAVE_MODULE).fst
# Per-target layout if one is curated, else the shared default.
WAVE_LAYOUT := $(if $(wildcard $(WAVE_LAYOUT_DIR)/$(TEST).gtkw),\
                 $(WAVE_LAYOUT_DIR)/$(TEST).gtkw,$(WAVE_LAYOUT_DIR)/default.gtkw)

waves:
	@mkdir -p $(WAVE_DIR)
	$(MAKE) -C dv/pyuvm WAVES=1 SIM=verilator MODULE=$(WAVE_MODULE) \
	  WAVE_DIR=$(abspath $(WAVE_DIR))
	@if [ ! -s $(WAVE_FST) ]; then \
	  echo "[WAVES] ERROR: the WAVES=1 run produced no FST at $(WAVE_FST)"; exit 1; fi
	@echo "[WAVES] wrote $(WAVE_FST) ($$(wc -c < $(WAVE_FST)) bytes) \
from dv/pyuvm MODULE=$(WAVE_MODULE) (Verilator FST, -DWAVES build)"
	@echo "[WAVES] open with: make wave TEST=$(TEST)   layout: $(WAVE_LAYOUT)"

wave: waves
	@if ! command -v $(GTKWAVE) >/dev/null 2>&1; then \
	  echo "[WAVES] gtkwave not found on PATH — install it (apt-get install -y gtkwave)"; \
	  echo "[WAVES] the dump is ready at $(WAVE_FST); open it wherever you like"; \
	  exit 1; fi
	@echo "[WAVES] opening $(WAVE_FST) in GTKWave with layout $(WAVE_LAYOUT)"
	@exec $(GTKWAVE) --save=$(WAVE_LAYOUT) $(WAVE_FST)

wave-check:
	$(PYTHON) tools/wave_check.py --layout-dir $(WAVE_LAYOUT_DIR) \
	  --wave-dir $(WAVE_DIR) $(WAVE_CHECK_ARGS)

# Phase G increment 4 — the browser viewer. Consumes the increment-3 dump above
# (it will run `make waves` itself if it is missing); adds NO second dump path
# and touches nothing the gate compiles. Output is one git-ignored HTML file.
WAVE_VIEWER ?= $(WAVE_LAYOUT_DIR)/viewer/wave_viewer.html

wave-web:
	$(PYTHON) tools/wave_web.py --test $(TEST) --wave-dir $(WAVE_DIR) \
	  --layout-dir $(WAVE_LAYOUT_DIR) --viewer $(WAVE_VIEWER) $(WAVE_WEB_ARGS)

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

# The DV swarm: Docker + .claude/agents manager-subagent model (adapted from the
# axi-on-ucie-to-mem sibling). Runs Claude Code NON-bare; the swarm-manager
# dispatches per-tier dv-env-testers + the infra-agent, fixes reds, and opens a
# PR (a human merges; CI validates --binary UVM + trace_compare on the PR).
# Needs `claude` on PATH + a credential (ANTHROPIC_API_KEY or
# CLAUDE_CODE_OAUTH_TOKEN) and, to push/PR, GITHUB_TOKEN.
#   make swarm                       # default finalization task
#   SWARM_TASK="do X" make swarm     # custom task
swarm:
	bash docker/swarm.sh

# Point at whatever railway binary is on PATH (falls back to `railway`).
RAILWAY_CLI ?= $(shell command -v railway 2>/dev/null || echo railway)
SWARM_ENV   ?=

clean:
	-$(MAKE) -C dv/pyuvm clean
	-$(MAKE) -C dv/uvm/vlt clean
	rm -rf obj_dir report $(COV_DIR) build/formal $(WAVE_DIR)
