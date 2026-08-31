#!/usr/bin/env bash
# Entrypoint for the ucie2-pipe7-bridge UVM-on-Verilator image.
#
# Bundles UVM-capable Verilator (built from source) + the Accellera UVM library.
# Appends the toolchain overrides to every `make` call so the bundled tools are
# always used, and runs a memory preflight before the RAM-heavy --binary build.
#
#   (no args)        -> make -C dv/uvm/vlt ci   <overrides>   (full UVM gate)
#   make <targets>   -> make -C dv/uvm/vlt <targets> <overrides>
#   <anything else>  -> exec verbatim (verilator --version, bash, ...)
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

# No args -> full CI gate. `make ...` -> forward to the vlt flow. Else exec.
if [ "$#" -eq 0 ]; then
  preflight_resources
  exec make -C dv/uvm/vlt ci "${MAKE_ARGS[@]}"
elif [ "$1" = "make" ]; then
  shift
  case " $* " in *" run "*|*" ci "*|*" all "*) preflight_resources ;; esac
  exec make -C dv/uvm/vlt "$@" "${MAKE_ARGS[@]}"
else
  exec "$@"
fi
