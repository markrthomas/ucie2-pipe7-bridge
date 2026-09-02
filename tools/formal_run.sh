#!/usr/bin/env bash
# =============================================================================
# formal_run.sh -- Phase F increment 3: the SymbiYosys (BMC) formal tier.
#
# ADDITIVE and OUTSIDE the gate. This is never invoked by lint / pyuvm / fcov /
# uvm / trace-compare / coverage; it reads no testbench and writes only under
# build/formal/. It proves boundary properties of two tractable blocks with a
# BOUNDED model check -- the banner says "BMC depth N", not "proven".
#
# Toolchain: apt `yosys` + SymbiYosys (github.com/YosysHQ/sby) + `z3`.
# NOT OSS CAD Suite (see CLAUDE.md / PLAN.md).
#
# Degrades gracefully: a host without sby/yosys prints a skip line and exits 0,
# so `make formal` never reds a box that simply lacks the formal tools. CI and
# the Railway image DO have them, so there it really runs and must PASS.
#
# Usage: tools/formal_run.sh [job ...]      (default: every formal/*.sby)
# =============================================================================
set -u -o pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
SBY_DIR=formal
SRC_DIR=build/formal/src
WORK_DIR=build/formal/work
PYTHON=${PYTHON:-python3}

if ! command -v sby >/dev/null 2>&1 || ! command -v yosys >/dev/null 2>&1; then
    echo "[FORMAL] SKIP: no SymbiYosys/yosys on PATH."
    echo "[FORMAL] SKIP: install with 'apt-get install -y yosys z3' plus"
    echo "[FORMAL] SKIP:   git clone --depth 1 https://github.com/YosysHQ/sby && make -C sby install"
    echo "[FORMAL] SKIP: (do NOT use OSS CAD Suite). The formal tier runs in CI/Railway."
    exit 0
fi

JOBS=("$@")
if [ ${#JOBS[@]} -eq 0 ]; then
    JOBS=()
    for f in "$SBY_DIR"/*.sby; do
        JOBS+=("$(basename "$f" .sby)")
    done
fi

# The yosys 0.33 Verilog frontend cannot parse `import ucie2_pipe7_pkg::*;` (nor
# `return` in a function, nor an `int'()` cast), so the proof reads a mechanically
# transformed COPY of the RTL. rtl/ itself is never touched -- see tools/formal_prep.py.
rm -rf "$SRC_DIR"
"$PYTHON" tools/formal_prep.py --pkg rtl/ucie2_pipe7_pkg.sv --outdir "$SRC_DIR" \
    rtl/ucie2_fdi_link_fsm.sv \
    rtl/pipe7_mac_ctrl_fsm.sv \
    rtl/pipe7_tx_framer_gb.sv \
    rtl/pipe7_rx_deframer_gb.sv || exit 1

rc=0
for job in "${JOBS[@]}"; do
    sby_file="$SBY_DIR/$job.sby"
    if [ ! -f "$sby_file" ]; then
        echo "[FORMAL] $job: ERROR no such job ($sby_file)"
        rc=1
        continue
    fi
    depth=$(sed -n 's/^depth[[:space:]]\+\([0-9]\+\).*/\1/p' "$sby_file" | head -1)
    log="$WORK_DIR/$job.log"
    mkdir -p "$WORK_DIR"
    if sby -f -d "$WORK_DIR/$job" "$sby_file" >"$log" 2>&1; then
        echo "[FORMAL] $job: BMC depth ${depth:-?} PASSED"
    else
        echo "[FORMAL] $job: BMC depth ${depth:-?} FAILED -- see $ROOT/$log"
        sed -n 's/^.*summary: */    /p' "$log" | tail -8
        rc=1
    fi
done

if [ $rc -eq 0 ]; then
    echo "[FORMAL] ${#JOBS[@]} job(s) PASSED (bounded model check -- not an unbounded proof)"
fi
exit $rc
