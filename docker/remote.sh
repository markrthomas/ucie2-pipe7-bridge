#!/usr/bin/env bash
# =============================================================================
# remote.sh — run the SV UVM gate (`make uvm`) on Railway from your laptop, then
# stream logs and attach a terminal ON DEMAND.
#
# The local box OOMs the --binary UVM build (~5.7 GB WSL, CLAUDE.md); Railway's
# prod image (root Dockerfile) already carries the from-source UVM-capable
# Verilator and its ENTRYPOINT runs `make uvm`. This script is the laptop-side
# launcher: it deploys the CURRENT working tree (uncommitted edits included),
# sets KEEP_ALIVE=1 so the container holds open after the gate for attach, and
# streams the run. NOT OSS CAD Suite; no new deps beyond the Railway CLI.
#
#   docker/remote.sh up        deploy current tree + run `make uvm`, then stream
#   docker/remote.sh logs      (re)stream the running deployment's logs
#   docker/remote.sh attach    open a terminal in the running container (railway ssh)
#   docker/remote.sh status    show project/service/deployment status
#   docker/remote.sh down      tear the deployment down (STOPS billing)
#
#   make uvm-remote / uvm-remote-logs / uvm-attach / uvm-remote-status /
#   uvm-remote-down are the Makefile front-doors.
#
# SAFETY: `up` and `down` change paid cloud state, so they are DRY-RUN by default
# (print the exact railway commands, touch nothing). Set APPLY=1 to execute. The
# read-only modes (logs/attach/status) run directly.
#
#   APPLY=1 docker/remote.sh up          # actually deploy + run
#   RAILWAY_SVC=ucie2-pipe7-uvm ...       # override the service name
#
# Cost note: KEEP_ALIVE=1 keeps the container up AFTER `make uvm` finishes (that
# is what makes attach-on-demand work), so it bills until `docker/remote.sh down`.
# The prod image preflights a ~6 GB floor — size the Railway instance at ~8 GB
# (Settings -> Resource Limits) or the run fails fast before the build.
# =============================================================================
set -euo pipefail

RAILWAY="${RAILWAY:-$(command -v railway 2>/dev/null || echo railway)}"
SVC="${RAILWAY_SVC:-ucie2-pipe7-uvm}"
APPLY="${APPLY:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

have() { command -v "$1" >/dev/null 2>&1; }

need_railway() {
  if ! have "${RAILWAY%% *}" && [ ! -x "$RAILWAY" ]; then
    echo "[remote] Railway CLI not found. Install: npm install -g @railway/cli" >&2
    echo "[remote]   then: railway login && railway link   (pick project + service)" >&2
    exit 2
  fi
}

# Print a command; run it only when APPLY=1, else explain it's a dry run.
run_or_echo() {
  if [ -n "$APPLY" ]; then
    echo "[remote] + $*"
    "$@"
  else
    echo "[remote] (dry-run) would run: $*"
  fi
}

remote_up() {
  need_railway
  echo "[remote] target: project '$($RAILWAY status 2>/dev/null | awk -F': *' '/^Project:/{print $2; exit}')' service '$SVC'"
  if [ -z "$APPLY" ]; then
    echo "[remote] DRY-RUN (set APPLY=1 to actually deploy + run — provisions paid compute):"
  fi
  # 1) Hold the container open after the gate so a terminal can attach on demand.
  #    --skip-deploys: don't trigger a separate deploy; the `up` below carries it.
  run_or_echo "$RAILWAY" variables set KEEP_ALIVE=1 --service "$SVC" --skip-deploys
  # 2) Deploy the current working tree; the ENTRYPOINT runs `make uvm`. This
  #    streams BUILD logs inline until the deployment is live.
  run_or_echo "$RAILWAY" up --service "$SVC"
  if [ -z "$APPLY" ]; then
    echo "[remote] (dry-run) then it would stream the run:  $RAILWAY logs -d"
    echo "[remote] To fire for real:  APPLY=1 make uvm-remote"
    return 0
  fi
  echo "[remote] deployment live. Attach a terminal any time with:  make uvm-attach"
  echo "[remote]   (the job keeps running if you close this / your laptop)"
  echo "[remote] streaming the run (Ctrl-C stops VIEWING only; the job keeps going)..."
  # 3) Stream the container's stdout — the `make uvm` gate output.
  exec "$RAILWAY" logs -d
}

remote_logs()   { need_railway; echo "[remote] streaming deploy logs (Ctrl-C to stop viewing)..."; exec "$RAILWAY" logs -d; }
remote_attach() { need_railway; exec bash "$SCRIPT_DIR/shell.sh" railway "$SVC"; }
remote_status() {
  need_railway
  "$RAILWAY" status || true
  echo "----- recent deploy logs -----"
  "$RAILWAY" logs -d --lines 20 2>/dev/null || echo "[remote] no deployment logs yet."
}
remote_down() {
  need_railway
  if [ -z "$APPLY" ]; then
    echo "[remote] DRY-RUN teardown (set APPLY=1 to actually remove the deployment):"
  fi
  run_or_echo "$RAILWAY" down --service "$SVC" ${APPLY:+--yes}
  if [ -n "$APPLY" ]; then echo "[remote] deployment removed; billing for it stops."; fi
}

mode="${1:-up}"
case "$mode" in
  up)      remote_up ;;
  logs)    remote_logs ;;
  attach)  remote_attach ;;
  status)  remote_status ;;
  down)    remote_down ;;
  -h|--help) grep -E '^#( |=|$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "[remote] unknown mode '$mode' (use: up | logs | attach | status | down)" >&2; exit 2 ;;
esac
