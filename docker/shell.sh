#!/usr/bin/env bash
# =============================================================================
# shell.sh — open an interactive terminal into a RUNNING ucie2-pipe7-bridge
# container, wherever it runs: a local Docker container, the GitHub Codespace /
# devcontainer, or a Railway deployment. Additive dev convenience; nothing in the
# green gate uses it.
#
#   docker/shell.sh                 auto-detect (railway -> docker -> local)
#   docker/shell.sh docker [NAME]   docker exec -it into a running container
#                                   (default: newest container of our image)
#   docker/shell.sh railway [SVC]   railway ssh into the deployment (SVC optional)
#   docker/shell.sh local           exec a login shell in THIS environment
#                                   (you are already inside the container/Codespace)
#   make shell [SHELL_ARGS="docker mybox"]     same, via the Makefile
#
# Railway note: the gate is a run-to-completion batch job, so there is normally no
# running container to attach to. Deploy it with KEEP_ALIVE=1 (or DEBUG_SHELL=1) —
# see docker/entrypoint.sh — so the container stays up and `railway ssh` (this
# script's railway mode) can connect. NOT OSS CAD Suite; no new deps.
# =============================================================================
set -euo pipefail

IMAGE="${SWARM_IMAGE:-ghcr.io/markrthomas/ucie2-pipe7-uvm}"
# Strip any :tag so `docker ps --filter ancestor=` matches regardless of tag.
IMAGE_BASE="${IMAGE%%:*}"
SHELL_BIN="${CONTAINER_SHELL:-bash}"

have() { command -v "$1" >/dev/null 2>&1; }

# Is this process itself running inside our container / a Codespace / a Railway box?
in_container() {
  [ -f /.dockerenv ] || [ -n "${CODESPACES:-}" ] || [ -n "${RAILWAY_ENVIRONMENT:-}" ] \
    || grep -qaE '(docker|kubepods|containerd)' /proc/1/cgroup 2>/dev/null
}

open_local() {
  echo "[shell] opening a login shell in the current environment ($(hostname))."
  exec "$SHELL_BIN" -l
}

open_docker() {
  local name="${1:-}"
  if ! have docker; then
    echo "[shell] docker not found on PATH." >&2; return 2
  fi
  if [ -z "$name" ]; then
    # Newest running container of our image (any tag).
    name="$(docker ps --filter "ancestor=$IMAGE_BASE" --format '{{.ID}}' | head -1)"
    [ -z "$name" ] && name="$(docker ps --filter "ancestor=$IMAGE" --format '{{.ID}}' | head -1)"
  fi
  if [ -z "$name" ]; then
    echo "[shell] no running container of '$IMAGE_BASE' found. Running ones:" >&2
    docker ps --format '  {{.ID}}  {{.Image}}  {{.Names}}' >&2 || true
    echo "[shell] start one first (e.g. 'make uvm-shell'), or pass a name:" >&2
    echo "[shell]   docker/shell.sh docker <name|id>" >&2
    return 3
  fi
  echo "[shell] docker exec -it $name $SHELL_BIN"
  # Fall back to sh if the image has no bash.
  exec docker exec -it "$name" sh -lc "exec $SHELL_BIN -l 2>/dev/null || exec sh -l"
}

open_railway() {
  local svc="${1:-}"
  if ! have railway; then
    echo "[shell] railway CLI not found. Install it: npm install -g @railway/cli" >&2
    echo "[shell]   then: railway link   (select the project/service), and re-run." >&2
    return 2
  fi
  echo "[shell] railway ssh${svc:+ --service $svc}   (needs a running deployment;"
  echo "[shell]   deploy with KEEP_ALIVE=1 so the batch container stays up)"
  if [ -n "$svc" ]; then
    exec railway ssh --service "$svc"
  else
    exec railway ssh
  fi
}

mode="${1:-auto}"
[ "$#" -gt 0 ] && shift || true

case "$mode" in
  local)   open_local ;;
  docker)  open_docker "${1:-}" ;;
  railway) open_railway "${1:-}" ;;
  auto)
    # Inside the container already? Just give a shell.
    if in_container; then open_local; fi
    # A Railway context (CLI + linked project) wins over local Docker.
    if have railway && { [ -n "${RAILWAY_PROJECT_ID:-}" ] || [ -f ".railway.json" ] \
         || railway status >/dev/null 2>&1; }; then
      open_railway "" || true
    fi
    if have docker; then open_docker "" || true; fi
    echo "[shell] nothing to attach to (no in-container context, no linked Railway"
    echo "[shell]   project, no running Docker container). Options:"
    echo "[shell]     make uvm-shell            # run the image locally, drop into a shell"
    echo "[shell]     docker/shell.sh railway   # attach to a KEEP_ALIVE Railway deploy"
    echo "[shell]     docker/shell.sh local     # shell in the current environment"
    exit 1
    ;;
  -h|--help)
    grep -E '^#( |=|$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)
    echo "[shell] unknown mode '$mode' (use: auto | docker | railway | local)" >&2
    exit 2 ;;
esac
