#!/usr/bin/env bash
# =============================================================================
# check_tools.sh — verify (and optionally install) the ucie2-pipe7-bridge
# toolchain. Driven by the root Makefile:
#
#   make tools          check every tier, then install what is MISSING
#   make tools-check    check only, install nothing (CI / dry-run friendly)
#   make tools TOOLS_HEAVY=1   also build the from-source UVM Verilator (slow)
#
# Tiers mirror the reproducible envs (Dockerfile / Dockerfile.dev / CI):
#   core     required for `make lint`/`pyuvm`/`fcov`  -> apt + pip
#   formal   `make formal` (post-gate)               -> apt yosys/z3 + sby (pip+src)
#   waves    `make wave*`  (off-gate)                 -> apt gtkwave
#   heavy    `make uvm` --binary (CI/Railway only)    -> Verilator >=5.050 from src
#
# This project does NOT use OSS CAD Suite; the light tiers install from apt + pip
# exactly as the containers do. The heavy from-source Verilator build is a
# multi-minute, several-hundred-MB operation, so it is OPT-IN (TOOLS_HEAVY=1);
# otherwise it is reported with the exact build commands. Missing OPTIONAL tools
# never fail --check; only missing CORE tools do (so CI can gate on it).
# =============================================================================
set -uo pipefail

CHECK_ONLY=0
DO_HEAVY=0
for a in "$@"; do
  case "$a" in
    --check) CHECK_ONLY=1 ;;
    --heavy) DO_HEAVY=1 ;;
    -h|--help) grep -E '^#( |=|$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "check_tools.sh: unknown arg '$a'" >&2; exit 2 ;;
  esac
done

# ---- environment probes ------------------------------------------------------
have_cmd() { command -v "$1" >/dev/null 2>&1; }
have_py()  { python3 -c "import $1" >/dev/null 2>&1; }

if have_cmd apt-get; then HAVE_APT=1; else HAVE_APT=0; fi
if [ "$(id -u)" -eq 0 ]; then SUDO=""; elif have_cmd sudo; then SUDO="sudo"; else SUDO=""; fi

# Accumulators (installs are batched into one apt / one pip invocation).
declare -a MISS_APT=()        # apt package names to install
declare -a MISS_PIP=()        # pip package names to install
declare -a REPORT=()          # pretty status lines
CORE_MISSING=0                # -> non-zero exit in --check mode
NEED_SBY=0                    # SymbiYosys needs a pip+source install (special)
NEED_HEAVY=0                  # from-source UVM Verilator missing

# check <tier> <label> <present?0/1> <apt-pkg|-> <pip-pkg|->
# Records a status line; queues the install source when missing.
check() {
  local tier="$1" label="$2" ok="$3" apt="$4" pip="$5"
  if [ "$ok" -eq 1 ]; then
    REPORT+=("$(printf '  [ ok ]  %-7s %-16s' "$tier" "$label")")
    return
  fi
  REPORT+=("$(printf '  [MISS]  %-7s %-16s -> %s' "$tier" "$label" \
             "${apt:+apt:$apt }${pip:+pip:$pip}")")
  [ "$tier" = "core" ] && CORE_MISSING=1
  [ "$apt" != "-" ] && MISS_APT+=("$apt")
  [ "$pip" != "-" ] && MISS_PIP+=("$pip")
}

echo "== ucie2-pipe7-bridge toolchain =="
echo "   apt-get: $([ $HAVE_APT -eq 1 ] && echo yes || echo 'no (install manually)')   sudo: ${SUDO:-none}   mode: $([ $CHECK_ONLY -eq 1 ] && echo check-only || echo install)"

# ---- core (required) ---------------------------------------------------------
check core git       "$(have_cmd git      && echo 1 || echo 0)" git             -
check core make      "$(have_cmd make     && echo 1 || echo 0)" make            -
check core g++       "$(have_cmd g++      && echo 1 || echo 0)" g++             -
check core python3   "$(have_cmd python3  && echo 1 || echo 0)" python3         -
check core pip3      "$(have_cmd pip3 || python3 -m pip --version >/dev/null 2>&1 && echo 1 || echo 0)" python3-pip -
check core verilator "$(have_cmd verilator && echo 1 || echo 0)" verilator      -
check core iverilog  "$(have_cmd iverilog && echo 1 || echo 0)" iverilog        -
check core cocotb    "$(have_py cocotb    && echo 1 || echo 0)" -               cocotb
check core pyuvm     "$(have_py pyuvm     && echo 1 || echo 0)" -               pyuvm

# ---- formal (optional, post-gate) -------------------------------------------
check formal yosys   "$(have_cmd yosys    && echo 1 || echo 0)" yosys           -
check formal z3      "$(have_cmd z3       && echo 1 || echo 0)" z3              -
if have_cmd sby; then
  REPORT+=("$(printf '  [ ok ]  %-7s %-16s' formal sby)")
else
  REPORT+=("$(printf '  [MISS]  %-7s %-16s -> %s' formal sby 'pip:click + src:YosysHQ/sby')")
  NEED_SBY=1
fi

# ---- waves (optional, off-gate) ---------------------------------------------
check waves gtkwave  "$(have_cmd gtkwave  && echo 1 || echo 0)" gtkwave         -

# ---- heavy (CI/Railway): from-source UVM-capable Verilator >= 5.050 ----------
# Present if the local from-source install exists, or UVM_HOME points at the
# bundled Accellera library. The apt Verilator above CANNOT elaborate UVM.
UVM_VL="${VERILATOR:-$HOME/verilator/bin/verilator}"
UVM_H="${UVM_HOME:-$HOME/verilator/test_regress/t/uvm}"
if [ -x "$UVM_VL" ] && [ -f "$UVM_H/uvm_pkg_all_v2020_3_1_dpi.svh" ]; then
  REPORT+=("$(printf '  [ ok ]  %-7s %-16s (%s)' heavy 'uvm-verilator' "$UVM_VL")")
else
  REPORT+=("$(printf '  [MISS]  %-7s %-16s -> %s' heavy 'uvm-verilator' \
             'build from source (TOOLS_HEAVY=1)')")
  NEED_HEAVY=1
fi

printf '%s\n' "${REPORT[@]}"

# ---- install phase -----------------------------------------------------------
if [ "$CHECK_ONLY" -eq 1 ]; then
  if [ "$CORE_MISSING" -eq 1 ]; then
    echo "[tools] FAIL: core tool(s) missing (run 'make tools' to install)"; exit 1
  fi
  echo "[tools] check OK (core present; optional gaps are non-fatal)"; exit 0
fi

rc=0

# apt batch (light tiers). De-dup while preserving order.
if [ "${#MISS_APT[@]}" -gt 0 ]; then
  mapfile -t APT_UNIQ < <(printf '%s\n' "${MISS_APT[@]}" | awk '!seen[$0]++')
  echo "[tools] apt install: ${APT_UNIQ[*]}"
  if [ "$HAVE_APT" -eq 1 ]; then
    $SUDO apt-get update && \
    $SUDO apt-get install -y --no-install-recommends "${APT_UNIQ[@]}" || rc=1
  else
    echo "[tools] no apt-get on PATH — install these manually: ${APT_UNIQ[*]}"; rc=1
  fi
fi

# pip batch (matches CI: --break-system-packages on Debian/Ubuntu PEP-668).
if [ "${#MISS_PIP[@]}" -gt 0 ]; then
  mapfile -t PIP_UNIQ < <(printf '%s\n' "${MISS_PIP[@]}" | awk '!seen[$0]++')
  echo "[tools] pip install: ${PIP_UNIQ[*]}"
  python3 -m pip install --break-system-packages "${PIP_UNIQ[@]}" || \
    python3 -m pip install "${PIP_UNIQ[@]}" || rc=1
fi

# SymbiYosys: pip 'click' + a shallow source install (pure Python, no compile).
if [ "$NEED_SBY" -eq 1 ]; then
  echo "[tools] SymbiYosys (sby): pip click + install from YosysHQ/sby source"
  python3 -m pip install --break-system-packages click >/dev/null 2>&1 || \
    python3 -m pip install click >/dev/null 2>&1 || true
  tmp="$(mktemp -d)"
  if git clone --depth 1 https://github.com/YosysHQ/sby "$tmp/sby" 2>/dev/null; then
    $SUDO make -C "$tmp/sby" install || echo "[tools] sby install failed (optional; skipping)"
  else
    echo "[tools] could not clone YosysHQ/sby (optional; skipping)"
  fi
  rm -rf "$tmp"
fi

# Heavy from-source UVM Verilator — OPT-IN only (slow, big).
if [ "$NEED_HEAVY" -eq 1 ]; then
  if [ "$DO_HEAVY" -eq 1 ]; then
    echo "[tools] building UVM-capable Verilator v5.050 from source into ~/verilator ..."
    if [ "$HAVE_APT" -eq 1 ]; then
      $SUDO apt-get update && $SUDO apt-get install -y --no-install-recommends \
        git help2man perl python3 make autoconf g++ flex bison ccache \
        libgoogle-perftools-dev numactl perl-doc libfl2 libfl-dev \
        zlib1g zlib1g-dev ca-certificates || rc=1
    fi
    src="$HOME/verilator"
    if [ ! -d "$src/.git" ]; then
      git clone --branch v5.050 https://github.com/verilator/verilator "$src" || rc=1
    fi
    ( cd "$src" && autoconf && ./configure && make -j"$(nproc)" ) || rc=1
    echo "[tools] built $src/bin/verilator; UVM_HOME=$src/test_regress/t/uvm"
  else
    cat <<'EOF'
[tools] SKIP heavy: the from-source UVM-capable Verilator (>=5.050) is a
        multi-minute, ~hundreds-of-MB build and is only needed for the CI/Railway
        `make uvm` --binary gate (this box lint/elaborates UVM instead). Build it
        with:  make tools TOOLS_HEAVY=1
        (or let CI/the Dockerfile provide it — see Dockerfile stage 1).
EOF
  fi
fi

if [ "$rc" -ne 0 ]; then
  echo "[tools] FINISHED with errors (see above)"; exit 1
fi
echo "[tools] all requested tools present/installed"
