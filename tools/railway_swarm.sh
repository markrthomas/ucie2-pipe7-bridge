#!/usr/bin/env bash
# =============================================================================
# railway_swarm.sh — fire a cloud swarm of verilator-uvm workers on Railway.
#
# Two modes (MODE=), both fanned out N-wide onto Railway cloud infra that has the
# RAM the local ~5.7 GB WSL box lacks (the `--binary` UVM build OOMs locally):
#
#   MODE=gate    (default) — N ephemeral `railway sandbox`es (~4 GB), each boots
#                the prebuilt toolchain snapshot (SWARM_TEMPLATE), clones REF, and
#                runs the LIGHT elaborate smoke (`dv/uvm/vlt lint`). The heavy
#                `--binary` + trace_compare gate does NOT fit 4 GB and stays in CI
#                (.github/workflows/uvm-verilator.yml) — the authoritative gate.
#
#   MODE=agents  — N `railway ca start --claude` cloud-agent VMs (Claude Code),
#                each handed one item-13 env slice to BUILD: author it, check
#                elaboration in-VM with `lint-uvm` (fits 4 GB), then push a branch
#                so CI runs the authoritative `--binary` + trace_compare. AI-dev swarm.
#
# SAFETY: prints the exact railway commands and does NOTHING by default. Set
# SWARM_APPLY=1 to actually fire (spends money + provisions cloud resources).
#
# PREREQS to fire: `railway login` (done: markt) AND a linked project
# (`railway link`) OR RAILWAY_TOKEN in the env (CI). For MODE=agents, a headless
# Claude credential (CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY).
#
#   MODE=probe   — ONE real sandbox: report nproc/mem/os, then self-destroy.
#                The cheapest first live fire; confirms cloud RAM + the JSON id
#                field that gate mode captures. `SWARM_APPLY=1 MODE=probe`.
#
#   Usage:  tools/railway_swarm.sh [MODE]   (MODE = probe|gate|agents)
#   Env:    N=8  REF=<git sha/branch>  SWARM_TEMPLATE=uvm
#           SWARM_APPLY=1  SEEDS="1 2 3 4"  TESTS="roundtrip"  IDLE_MIN=30
# =============================================================================
set -euo pipefail

RW="${RAILWAY:-railway}"
MODE="${1:-${MODE:-gate}}"
N="${N:-8}"
REF="${REF:-$(git rev-parse HEAD 2>/dev/null || echo main)}"
REPO_URL="${REPO_URL:-https://github.com/markrthomas/ucie2-pipe7-bridge.git}"
SWARM_TEMPLATE="${SWARM_TEMPLATE:-uvm}"          # railway sandbox template name
IDLE_MIN="${IDLE_MIN:-30}"                        # auto-destroy idle sandboxes
SEEDS="${SEEDS:-1 2 3 4 5 6 7 8}"
TESTS="${TESTS:-roundtrip}"
APPLY="${SWARM_APPLY:-0}"

# Project/environment selection: prefer explicit flags, else the linked project.
PROJ_FLAGS=()
[ -n "${RAILWAY_PROJECT:-}" ]     && PROJ_FLAGS+=(--project "$RAILWAY_PROJECT")
[ -n "${RAILWAY_ENVIRONMENT:-}" ] && PROJ_FLAGS+=(--environment "$RAILWAY_ENVIRONMENT")

say()  { printf '\033[1;36m[swarm]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[swarm]\033[0m %s\n' "$*" >&2; }

# Run a railway command, or just echo it in dry-run.
run() {
  if [ "$APPLY" = "1" ]; then
    say "+ $RW $*"
    "$RW" "$@"
  else
    printf '  (dry-run) %s %s\n' "$RW" "$*"
  fi
}

preflight() {
  say "MODE=$MODE  N=$N  REF=${REF:0:12}  template=$SWARM_TEMPLATE  APPLY=$APPLY"
  if ! "$RW" whoami >/dev/null 2>&1 && [ -z "${RAILWAY_TOKEN:-}" ]; then
    warn "not logged in and no RAILWAY_TOKEN — run 'railway login' or set RAILWAY_TOKEN"
    [ "$APPLY" = "1" ] && exit 1
  fi
  if ! "$RW" status >/dev/null 2>&1 && [ ${#PROJ_FLAGS[@]} -eq 0 ] && [ -z "${RAILWAY_TOKEN:-}" ]; then
    warn "no linked project — run 'railway link' or pass RAILWAY_PROJECT/RAILWAY_ENVIRONMENT"
    [ "$APPLY" = "1" ] && exit 1
  fi
  if [ "$APPLY" = "1" ]; then
    # The sandbox clones REF from GitHub over HTTPS. We can't reliably verify an
    # arbitrary commit is pushed from here (local `origin` is SSH and may lag), so
    # just note it — the clone fails loudly if REF isn't on the remote.
    say "sandboxes clone REF ${REF:0:12} from $REPO_URL — ensure it is pushed."
  fi
}

# The command each GATE sandbox runs. NB: Railway sandboxes are ~4 GB (measured)
# and the plan ceiling is 8 GB, so the heavy `--binary` UVM build (needs >=6 GB)
# does NOT run here — it is CI's job (.github/workflows/uvm-verilator.yml), which
# is the authoritative heavy + trace_compare gate. On the 4 GB sandbox we run the
# LIGHT elaborate smoke (`dv/uvm/vlt lint`, ~330 MB) as a fast cloud sanity check.
# The prebuilt template carries verilator-uvm at /opt/verilator (UVM_HOME).
gate_cmd() {
  local test="$1" seed="$2"
  cat <<EOF
set -euo pipefail
git clone --depth 50 "$REPO_URL" work && cd work && git checkout "$REF"
# Light tiers that fit a 4 GB sandbox on the apt-toolchain template ('$SWARM_TEMPLATE'):
# RTL strict lint (apt verilator) + independent functional coverage (iverilog).
# Heavy --binary UVM + trace_compare stay in CI (uvm-verilator.yml).
make lint
make fcov FCOV_SIM=icarus
EOF
}

launch_gate() {
  say "LIGHT elaborate smoke on 4 GB sandboxes — heavy --binary + trace_compare run in CI"
  local i=0
  for test in $TESTS; do
    for seed in $SEEDS; do
      i=$((i+1)); [ "$i" -gt "$N" ] && { say "reached N=$N shards; stopping fan-out"; return 0; }
      say "shard $i/$N: test=$test seed=$seed"
      if [ "$APPLY" != "1" ]; then
        run sandbox create "${PROJ_FLAGS[@]}" --template "$SWARM_TEMPLATE" \
            --idle-timeout-minutes "$IDLE_MIN" --json --variable "SWARM_TEST=$test,SWARM_SEED=$seed"
        run sandbox exec "${PROJ_FLAGS[@]}" --id '<id-from-create>' -- "$(gate_cmd "$test" "$seed")"
        continue
      fi
      local out id
      out="$("$RW" sandbox create "${PROJ_FLAGS[@]}" --template "$SWARM_TEMPLATE" \
             --idle-timeout-minutes "$IDLE_MIN" --json --variable "SWARM_TEST=$test,SWARM_SEED=$seed")"
      id="$(printf '%s' "$out" | extract_id)"
      [ -z "$id" ] && { warn "no sandbox id from create; raw JSON: $out"; continue; }
      "$RW" sandbox exec "${PROJ_FLAGS[@]}" --id "$id" --timeout 900 -- "$(gate_cmd "$test" "$seed")" \
        || warn "shard $i exec failed (see output above)"
      "$RW" sandbox destroy "${PROJ_FLAGS[@]}" --id "$id" || true
    done
  done
}

# Each AGENT VM builds one item-13 slice. Slice tasks are intentionally terse
# pointers to the tracked spec so the agent reads the authoritative version.
declare -a SLICES=(
  "fdi-agent|Build dv/uvm/sv/agents/fdi_agent.svh (fdi_sequencer/driver/rx_monitor + stall_ack) mirroring dv/pyuvm/agents/fdi_agent.py. Keep trace byte-identical."
  "pipe-agent|Build dv/uvm/sv/agents/pipe_agent.svh (pipe_tx_monitor + phy_loopback shadow-register) mirroring the PyUVM PipeTxMonitor/loopback. Keep trace byte-identical."
  "scoreboard-env|Build dv/uvm/sv/{env,seq_lib}/* (fdi_flit_seq, bridge_scoreboard, bridge_env) mirroring dv/pyuvm/env.py. Keep trace byte-identical."
)

# One real sandbox: create -> report resources -> destroy. The cheapest possible
# first live fire — confirms the cloud box has the RAM the local box lacks AND
# nails down the `sandbox create --json` id field so gate mode can capture it.
extract_id() {
  # Read the create --json from stdin and print the sandbox id (field: "id").
  # Use `python3 -c` (NOT a heredoc) so stdin stays the piped JSON.
  python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(d, dict):
    if d.get("id"):
        print(d["id"])
    elif isinstance(d.get("sandbox"), dict) and d["sandbox"].get("id"):
        print(d["sandbox"]["id"])
' 2>/dev/null || true
}

launch_probe() {
  if [ "$APPLY" != "1" ]; then
    say "probe (dry-run): would create 1 sandbox, run 'nproc; free -m; uname -a', destroy it"
    run sandbox create "${PROJ_FLAGS[@]}" --idle-timeout-minutes 10 --json
    return 0
  fi
  say "creating one probe sandbox (real)..."
  local out id
  out="$("$RW" sandbox create "${PROJ_FLAGS[@]}" --idle-timeout-minutes 10 --json)"
  printf '%s\n' "$out"                       # show raw JSON so we learn the shape
  id="$(printf '%s' "$out" | extract_id)"
  if [ -z "$id" ]; then
    warn "could not auto-extract a sandbox id from the JSON above."
    warn "note the id field name, then destroy manually: railway sandbox destroy --id <id>"
    return 1
  fi
  say "sandbox id = $id — running resource report..."
  "$RW" sandbox exec "${PROJ_FLAGS[@]}" --id "$id" --timeout 120 -- \
    'echo "== nproc =="; nproc;
     echo "== MemTotal (MB) =="; awk "/MemTotal/{printf \"%d\n\", \$2/1024}" /proc/meminfo;
     echo "== cgroup memory.max =="; cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo unknown;
     echo "== os =="; uname -a;
     echo "== verilator =="; (command -v verilator && verilator --version) || echo "no verilator (expected until template is prebuilt)"'
  say "destroying probe sandbox $id..."
  "$RW" sandbox destroy "${PROJ_FLAGS[@]}" --id "$id"
  say "probe done. If mem >= 6 GB and destroy succeeded, gate mode is good to go."
}

launch_agents() {
  local i=0
  for entry in "${SLICES[@]}"; do
    i=$((i+1)); [ "$i" -gt "$N" ] && break
    local slice="${entry%%|*}" task="${entry#*|}"
    local name="uvm-slice-${slice}"
    say "agent $i -> $name"
    # --claude uses CLAUDE_CODE_OAUTH_TOKEN/ANTHROPIC_API_KEY if set (headless),
    # else mints a token interactively. AGENT_ARGS after `--` go to Claude Code.
    run ca start "${PROJ_FLAGS[@]}" --claude --new --name "$name" \
        --variable "SWARM_SLICE=$slice,SWARM_REF=$REF" \
        -- -p "$task Reference: docs/phase_d_swarm.md and dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv. Check elaboration in-VM with 'make -C dv/uvm/vlt lint' (fits 4 GB), then push a branch — CI runs the authoritative --binary + trace_compare (heavy build does not fit the 4 GB VM)."
  done
}

preflight
case "$MODE" in
  probe)  launch_probe ;;
  gate)   launch_gate ;;
  agents) launch_agents ;;
  *) warn "unknown MODE=$MODE (want probe|gate|agents)"; exit 2 ;;
esac

if [ "$APPLY" != "1" ]; then
  say "DRY-RUN complete — no cloud resources touched. Re-run with SWARM_APPLY=1 to fire."
fi
