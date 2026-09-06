#!/usr/bin/env bash
# Entrypoint for the ucie2-pipe7-bridge UVM-on-Verilator image.
#
# Bundles UVM-capable Verilator (built from source) + the Accellera UVM library.
# Appends the toolchain overrides to every `make` call so the bundled tools are
# always used, and runs a memory preflight before the RAM-heavy --binary build.
#
#   (no args)        -> make uvm   <overrides>   (full SV UVM gate, from repo root:
#                       gen-vectors + lint + --binary build+run, seeded-random ==
#                       CI; NOT `-C dv/uvm/vlt`, which skips the shared vector)
#   make <targets>   -> make <targets> <overrides>  (repo-root targets, e.g.
#                       `make uvm`, `make lint-uvm`, `make trace-compare`)
#   shell            -> interactive shell now (local `docker run -it ... shell`),
#                       or, with no TTY, hold the container open for `railway ssh`
#   <anything else>  -> exec verbatim (verilator --version, bash, ...)
#
# Debug / attach env switches (for opening a terminal into a RUNNING container —
# see docker/shell.sh):
#   DEBUG_SHELL=1  -> skip the gate; open a shell (TTY) or hold open (no TTY)
#   KEEP_ALIVE=1   -> run the gate as usual, THEN hold the container open so
#                     `railway ssh` / `docker exec` can attach to inspect artifacts
set -euo pipefail

# A stale VERILATOR_ROOT hard-errors the launcher; the flow doesn't need it.
unset VERILATOR_ROOT || true

MAKE_ARGS=(
  "VERILATOR=${VERILATOR:-/opt/verilator/bin/verilator}"
  "UVM_HOME=${UVM_HOME:-/opt/verilator/uvm}"
  "BUILD_JOBS=${BUILD_JOBS:-1}"
)

# --- memory preflight: fail fast before the multi-GB --binary compile ---------
container_mem_mb() {
  local lim=""
  if [ -r /sys/fs/cgroup/memory.max ]; then
    lim="$(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
  elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    lim="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null)"
  fi
  if [ -z "${lim}" ] || [ "${lim}" = "max" ] || { [ "${lim}" -gt 1000000000000 ] 2>/dev/null; }; then
    awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null
  else
    echo "$(( lim / 1024 / 1024 ))"
  fi
}

preflight_resources() {
  [ -n "${UVM_SKIP_RESCHECK:-}" ] && return 0
  local min_mb="${UVM_MIN_MEM_MB:-6144}"
  local mem_mb cpus
  mem_mb="$(container_mem_mb)"
  cpus="$(nproc 2>/dev/null || echo '?')"
  echo "[preflight] container memory: ${mem_mb:-?} MB (floor ${min_mb} MB) | vCPUs: ${cpus} | BUILD_JOBS=${BUILD_JOBS:-1}"
  if [ -n "${mem_mb}" ] && [ "${mem_mb}" -lt "${min_mb}" ] 2>/dev/null; then
    echo "[preflight] ERROR: ${mem_mb} MB is below the ${min_mb} MB floor for the UVM --binary build." >&2
    echo "[preflight]   Fix: raise instance memory (Railway: Settings -> Resource Limits, ~8 GB)," >&2
    echo "[preflight]   or export UVM_SKIP_RESCHECK=1 to bypass this guard." >&2
    exit 1
  fi
}

# Open (TTY) or hold open (no TTY) an interactive shell so a terminal can attach.
# TTY  -> `docker run -it ... shell` drops you straight into bash.
# No TTY (Railway/CI) -> sleep so `railway ssh`/`docker exec` can connect later.
open_shell() {
  echo "[entrypoint] debug shell. toolchain: ${MAKE_ARGS[0]}  ${MAKE_ARGS[1]}"
  if [ -t 0 ]; then
    exec bash -l
  else
    echo "[entrypoint] no TTY -> holding the container open. Attach with:"
    echo "[entrypoint]   railway ssh      (Railway)   |   docker exec -it <c> bash   (Docker)"
    echo "[entrypoint]   then: cd /work && make lint-uvm ${MAKE_ARGS[*]}  (or: make uvm)"
    exec sleep infinity
  fi
}

# Run the gate WITHOUT exec (so KEEP_ALIVE can hold the container open afterward).
# The gate is the repo-root `make uvm` (gen-vectors + lint + --binary build+run),
# so the container verifies the SAME seeded-random stimulus as CI -- running the
# sub-Makefile `ci` directly would skip gen-vectors and silently fall back to the
# compiled-in directed ramp. UVM_HOME/VERILATOR/BUILD_JOBS ride in via MAKE_ARGS.
run_gate() {
  if [ "$#" -eq 0 ]; then
    preflight_resources
    make uvm "${MAKE_ARGS[@]}"
  elif [ "$1" = "make" ]; then
    shift
    case " $* " in *" uvm "*|*" uvm-b2b "*|*" run "*|*" ci "*|*" all "*) preflight_resources ;; esac
    make "$@" "${MAKE_ARGS[@]}"
  else
    exec "$@"   # verbatim (verilator --version, bash, ...); replaces this process
  fi
}

# DEBUG_SHELL / `shell` arg -> skip the gate entirely and open/hold a shell.
if [ "${DEBUG_SHELL:-}" = "1" ] || [ "${1:-}" = "shell" ]; then
  open_shell
fi

# KEEP_ALIVE -> run the gate, then hold open for attach (inspect artifacts, re-run).
if [ "${KEEP_ALIVE:-}" = "1" ]; then
  set +e; run_gate "$@"; rc=$?; set -e
  echo "[entrypoint] gate finished (rc=${rc}); KEEP_ALIVE=1 -> holding open. Attach with:"
  echo "[entrypoint]   railway ssh   |   docker exec -it <c> bash"
  exec sleep infinity
fi

run_gate "$@"
