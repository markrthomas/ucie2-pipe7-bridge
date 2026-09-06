#!/usr/bin/env bash
# =============================================================================
# codespace.sh — run the SV UVM gate (`make uvm`) in a GitHub Codespace from your
# laptop, then stream it and attach a terminal ON DEMAND. The Codespaces sibling
# of docker/remote.sh (Railway); same verbs, driven by RUNNER=codespace.
#
# A Codespace boots from Dockerfile.dev, which has only apt Verilator 5.020 (NOT
# UVM-capable). So the first run BOOTSTRAPS the from-source UVM Verilator via
# `make tools TOOLS_HEAVY=1` (self-installs its build deps; ~10 min, cached after),
# then runs `make uvm` inside a detached `tmux` session so it survives disconnects.
#
#   docker/codespace.sh up        create/reuse a codespace, bootstrap + run, stream
#   docker/codespace.sh logs      (re)stream the run's log (tail -f)
#   docker/codespace.sh attach    open a terminal in the run (tmux attach)
#   docker/codespace.sh status    codespace + run-session status
#   docker/codespace.sh down      delete the codespace (STOPS billing)
#
#   make uvm-remote RUNNER=codespace   (and uvm-remote-logs / uvm-attach /
#   uvm-remote-status / uvm-remote-down with the same RUNNER=codespace) are the
#   Makefile front-doors.
#
# NOTE (vs Railway): `railway up` deploys your LOCAL working tree; a Codespace is a
# cloud clone of a git branch, so this runs CS_BRANCH (default main) — commit +
# push first. On reuse it `git pull`s the branch before building.
#
# SAFETY: `up` (create) and `down` (delete) change paid cloud state, so they are
# DRY-RUN by default (print the exact gh commands, touch nothing). Set APPLY=1 to
# execute. logs/attach/status run directly.
#
#   APPLY=1 docker/codespace.sh up
#   CS_BRANCH=my-feature CS_MACHINE=standardLinux32gb APPLY=1 docker/codespace.sh up
#   CS_NAME=<name> docker/codespace.sh attach     # target a specific codespace
# =============================================================================
set -euo pipefail

GH="${GH:-gh}"
CS_REPO="${CS_REPO:-markrthomas/ucie2-pipe7-bridge}"
CS_BRANCH="${CS_BRANCH:-main}"
CS_MACHINE="${CS_MACHINE:-standardLinux32gb}"   # 4 cores / 16 GB — fits the --binary build
CS_NAME="${CS_NAME:-}"
APPLY="${APPLY:-}"

CS_WORKDIR="/workspaces/${CS_REPO##*/}"
CS_LOG="/tmp/uvm.log"
CS_SESSION="uvm"

have() { command -v "$1" >/dev/null 2>&1; }
need_gh() {
  if ! have "$GH"; then
    echo "[cs] GitHub CLI not found. Install: https://cli.github.com  then: gh auth login" >&2
    exit 2
  fi
}

run_or_echo() {
  if [ -n "$APPLY" ]; then echo "[cs] + $*"; "$@"; else echo "[cs] (dry-run) would run: $*"; fi
}

# Resolve the codespace name for this repo (CS_NAME wins; else newest on CS_REPO).
cs_name() {
  [ -n "$CS_NAME" ] && { echo "$CS_NAME"; return 0; }
  "$GH" codespace list --json name,repository -q \
    ".[] | select(.repository==\"$CS_REPO\") | .name" 2>/dev/null | head -1
}

# The bootstrap+run script executed INSIDE the codespace (non-interactive). Starts
# `make uvm` in a detached tmux session, logging to $CS_LOG, so it survives ssh
# disconnects. Idempotent: a second `up` while it runs just reports it's running.
boot_script() {
  cat <<EOF
set -e
cd "$CS_WORKDIR"
command -v tmux >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y -qq tmux; }
if tmux has-session -t $CS_SESSION 2>/dev/null; then
  echo "[cs] tmux session '$CS_SESSION' already running — attach with: make uvm-attach RUNNER=codespace"
  exit 0
fi
git pull --ff-only origin "$CS_BRANCH" || true
tmux new-session -d -s $CS_SESSION "cd '$CS_WORKDIR' && { \
  echo '[cs] bootstrapping UVM Verilator (first run ~10 min) ...'; \
  make tools TOOLS_HEAVY=1 && \
  PATH=\\\$HOME/verilator/bin:\\\$PATH UVM_HOME=\\\$HOME/verilator/test_regress/t/uvm make uvm; \
  echo \"[cs] === make uvm exited (rc=\\\$?) ===\"; \
} 2>&1 | tee '$CS_LOG'"
echo "[cs] started 'make uvm' in tmux session '$CS_SESSION'"
EOF
}

cs_up() {
  need_gh
  local name; name="$(cs_name || true)"
  if [ -z "$name" ]; then
    if [ -z "$APPLY" ]; then
      echo "[cs] DRY-RUN (set APPLY=1 to actually create a codespace + run — bills core-hours):"
      echo "[cs] (dry-run) would run: $GH codespace create -R $CS_REPO -b $CS_BRANCH -m $CS_MACHINE"
      echo "[cs] then, inside it: make tools TOOLS_HEAVY=1 && make uvm  (in tmux '$CS_SESSION'), then tail $CS_LOG"
      echo "[cs] To fire for real:  APPLY=1 make uvm-remote RUNNER=codespace"
      return 0
    fi
    echo "[cs] creating codespace ($CS_MACHINE) for $CS_REPO@$CS_BRANCH ..."
    name="$("$GH" codespace create -R "$CS_REPO" -b "$CS_BRANCH" -m "$CS_MACHINE")"
    echo "[cs] created: $name"
  else
    echo "[cs] reusing codespace: $name"
    if [ -z "$APPLY" ]; then
      echo "[cs] (dry-run) would bootstrap the UVM toolchain + run 'make uvm' in it (tmux '$CS_SESSION')."
      echo "[cs] To fire for real:  APPLY=1 make uvm-remote RUNNER=codespace"
      return 0
    fi
  fi
  echo "[cs] starting the run (detached tmux; survives disconnect) ..."
  "$GH" codespace ssh -c "$name" -- "$(boot_script)"
  echo "[cs] attach a terminal any time:  make uvm-attach RUNNER=codespace"
  echo "[cs] streaming $CS_LOG (Ctrl-C stops VIEWING only; the job keeps running)..."
  exec "$GH" codespace ssh -c "$name" -- -t "tail -n +1 -f '$CS_LOG'"
}

cs_logs() {
  need_gh
  local name; name="$(cs_name || true)"
  [ -z "$name" ] && { echo "[cs] no codespace found for $CS_REPO (create one: APPLY=1 make uvm-remote RUNNER=codespace)" >&2; exit 1; }
  echo "[cs] streaming $CS_LOG on $name (Ctrl-C to stop viewing)..."
  exec "$GH" codespace ssh -c "$name" -- -t "tail -n +1 -f '$CS_LOG'"
}

cs_attach() {
  need_gh
  local name; name="$(cs_name || true)"
  [ -z "$name" ] && { echo "[cs] no codespace found for $CS_REPO" >&2; exit 1; }
  echo "[cs] attaching to tmux '$CS_SESSION' on $name (detach: Ctrl-b d)..."
  exec "$GH" codespace ssh -c "$name" -- -t "cd '$CS_WORKDIR'; tmux attach -t $CS_SESSION || { echo '[cs] no run session; opening a shell'; exec bash -l; }"
}

cs_status() {
  need_gh
  "$GH" codespace list --json name,repository,state,gitStatus -q \
    ".[] | select(.repository==\"$CS_REPO\") | \"\(.name)  \(.state)  ref=\(.gitStatus.ref)\"" 2>/dev/null \
    || "$GH" codespace list
  local name; name="$(cs_name || true)"
  if [ -n "$name" ]; then
    echo "----- run session on $name -----"
    "$GH" codespace ssh -c "$name" -- "tmux has-session -t $CS_SESSION 2>/dev/null && echo 'session $CS_SESSION: RUNNING' || echo 'session $CS_SESSION: none'; tail -n 20 '$CS_LOG' 2>/dev/null || true" || true
  fi
}

cs_down() {
  need_gh
  local name; name="$(cs_name || true)"
  [ -z "$name" ] && { echo "[cs] no codespace found for $CS_REPO — nothing to delete." >&2; return 0; }
  if [ -z "$APPLY" ]; then
    echo "[cs] DRY-RUN teardown (set APPLY=1 to actually delete the codespace):"
  fi
  run_or_echo "$GH" codespace delete -c "$name"
  if [ -n "$APPLY" ]; then echo "[cs] codespace $name deleted; billing for it stops."; fi
}

mode="${1:-up}"
case "$mode" in
  up)      cs_up ;;
  logs)    cs_logs ;;
  attach)  cs_attach ;;
  status)  cs_status ;;
  down)    cs_down ;;
  -h|--help) grep -E '^#( |=|$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "[cs] unknown mode '$mode' (use: up | logs | attach | status | down)" >&2; exit 2 ;;
esac
