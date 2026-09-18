"""Functional-coverage model for the integrated ucie2_pipe7_bridge (PLAN Phase C, item 12).

INDEPENDENT-tool functional coverage: the bins here are scored by ``cocotb_coverage``
(pure Python), a tool entirely separate from Verilator's line coverage, and the CI
tier runs the stimulus on the INDEPENDENT Icarus Verilog engine (``make fcov``).
Together they are a redundant cross-check to the Verilator/UVM tiers: a different
simulator, a different testbench, a different coverage tool, and a different metric
(functional vs line/round-trip).

The bin set is derived from the frozen (Item 0) interface encoding space
(``rtl/ucie2_pipe7_pkg.sv``): control-plane PowerDown P0/P0s/P1/P2, Rate Gen5/Gen6,
Width W_10..W_160, request kind/outcome/busy; message-bus opcode/is_read/committed;
observed datapath rate/lock/data-phase/tx-valid; observed FDI flow control
(pl_valid / pl_trdy / pl_stallreq) and flit-type (pl_is_os); the recovered FDI
link-state space (``fdi_state_e``, all 8 states); and the two error-status flags
(sync_error, rx_overflow). Every bin is reachable from ``ucie2_pipe7_bridge`` driven
through its management + FDI + PIPE-RX ports -- there are deliberately no cross bins
with structurally-unreachable cells, so the target is an honest 100% of the set.
Sampling is done from Python monitors that read the DUT handles -- no RTL involvement.

Phase I I7 closed the two error-status bins (sync_error=1, rx_overflow=1) that were
previously FLAGGED as loopback-unreachable: the fcov driver now injects illegal
PIPE-RX sync headers (loss of block lock) and stalls the RX drain to overflow the
burst FIFO, and adds the is_os flit-type + full fdi_state link-state coverage. The
set is honest-100% again, error paths included.
"""
import json

from cocotb_coverage.coverage import CoverPoint, coverage_db

# ---- encodings (mirror ucie2_pipe7_pkg::*) ------------------------------------------------
RATE_GEN5, RATE_GEN6 = 4, 5
PD_BINS    = [0, 1, 2, 3]                 # P0, P0s, P1, P2
WIDTH_BINS = [0, 1, 2, 3, 4]             # W_10, W_20, W_40, W_80, W_160
KIND_BINS  = [0, 1, 2]                   # REQ_POWER, REQ_RATE, REQ_WIDTH
STATE_BINS = [0, 1, 2, 3, 4, 5, 6, 7]   # fdi_state_e RESET..DISABLED (pinned encoding)
STATE_LABELS = ["RESET", "ACTIVE", "L1", "L2", "LINKRESET", "LINKERROR",
                "RETRAIN", "DISABLED"]

# The exact CoverPoint names this model owns (so the overall % never double-counts the
# hierarchical parent nodes cocotb_coverage also stores in coverage_db).
POINTS = [
    "bridge.ctrl.kind", "bridge.ctrl.outcome", "bridge.ctrl.pd", "bridge.ctrl.rate",
    "bridge.ctrl.width", "bridge.ctrl.busy",
    "bridge.mb.op", "bridge.mb.is_read", "bridge.mb.committed",
    "bridge.dp.rate_obs", "bridge.dp.block_locked", "bridge.dp.in_data_phase",
    "bridge.dp.tx_valid",
    "bridge.fdi.pl_valid", "bridge.fdi.pl_trdy", "bridge.fdi.pl_stallreq",
    "bridge.fdi.is_os",
    "bridge.link.state",
    "bridge.err.sync_error", "bridge.err.rx_overflow",
]


# ---- control plane ------------------------------------------------------------------------
@CoverPoint("bridge.ctrl.kind", xf=lambda s: s["kind"], bins=KIND_BINS,
            bins_labels=["POWER", "RATE", "WIDTH"])
@CoverPoint("bridge.ctrl.outcome", xf=lambda s: s["outcome"], bins=["done", "reject"])
@CoverPoint("bridge.ctrl.pd", xf=lambda s: s["pd"], bins=PD_BINS,
            bins_labels=["P0", "P0s", "P1", "P2"])
@CoverPoint("bridge.ctrl.rate", xf=lambda s: s["rate"], bins=[RATE_GEN5, RATE_GEN6],
            bins_labels=["Gen5", "Gen6"])
@CoverPoint("bridge.ctrl.width", xf=lambda s: s["width"], bins=WIDTH_BINS,
            bins_labels=["W10", "W20", "W40", "W80", "W160"])
@CoverPoint("bridge.ctrl.busy", xf=lambda s: s["busy"], bins=[0, 1])
def sample_ctrl(s):
    """s = {kind, outcome('done'|'reject'), pd, rate, width, busy}."""
    pass


# ---- message bus --------------------------------------------------------------------------
@CoverPoint("bridge.mb.op", xf=lambda s: s["op"], bins=["read", "wr_unc", "wr_com"])
@CoverPoint("bridge.mb.is_read", xf=lambda s: s["is_read"], bins=[0, 1])
@CoverPoint("bridge.mb.committed", xf=lambda s: s["committed"], bins=[0, 1])
def sample_mb(s):
    """s = {op('read'|'wr_unc'|'wr_com'), is_read(0|1), committed(0|1)}."""
    pass


# ---- datapath / framing (observed) --------------------------------------------------------
@CoverPoint("bridge.dp.rate_obs", xf=lambda s: s["rate"], bins=[RATE_GEN5, RATE_GEN6],
            bins_labels=["Gen5", "Gen6"])
@CoverPoint("bridge.dp.block_locked", xf=lambda s: s["locked"], bins=[0, 1])
@CoverPoint("bridge.dp.in_data_phase", xf=lambda s: s["data_phase"], bins=[0, 1])
@CoverPoint("bridge.dp.tx_valid", xf=lambda s: s["tx_valid"], bins=[0, 1])
def sample_dp(s):
    """s = {rate, locked, data_phase, tx_valid}."""
    pass


# ---- FDI flow control (observed) ----------------------------------------------------------
@CoverPoint("bridge.fdi.pl_valid", xf=lambda s: s["pl_valid"], bins=[0, 1])
@CoverPoint("bridge.fdi.pl_trdy", xf=lambda s: s["pl_trdy"], bins=[0, 1])
@CoverPoint("bridge.fdi.pl_stallreq", xf=lambda s: s["pl_stallreq"], bins=[0, 1])
@CoverPoint("bridge.fdi.is_os", xf=lambda s: s.get("is_os", 0), bins=[0, 1],
            bins_labels=["data", "OS"])
def sample_fdi(s):
    """s = {pl_valid(0|1), pl_trdy(0|1), pl_stallreq(0|1), is_os(0|1, optional)}."""
    pass


# ---- FDI recovered link state (fdi_state_e; Phase I I1) ------------------------------------
@CoverPoint("bridge.link.state", xf=lambda s: s["state"], bins=STATE_BINS,
            bins_labels=STATE_LABELS)
def sample_link(s):
    """s = {state(0..7 = fdi_state_e)} -- the committed pl_state_sts."""
    pass


# ---- error-status flags (Phase I I5/I3; closed by I7 injection) ----------------------------
@CoverPoint("bridge.err.sync_error", xf=lambda s: s["sync_error"], bins=[0, 1])
@CoverPoint("bridge.err.rx_overflow", xf=lambda s: s["rx_overflow"], bins=[0, 1])
def sample_err(s):
    """s = {sync_error(0|1), rx_overflow(0|1)}."""
    pass


# ---- aggregation / reporting --------------------------------------------------------------
def per_point():
    """[(name, covered, size, pct), ...] over this model's own points (present in coverage_db)."""
    rows = []
    for name in POINTS:
        if name in coverage_db:
            ci = coverage_db[name]
            rows.append((name, int(ci.coverage), int(ci.size), float(ci.cover_percentage)))
    return rows


def overall():
    """(hit_bins, total_bins, pct) unioned across this model's points -- the headline number."""
    rows = per_point()
    hit = sum(r[1] for r in rows)
    total = sum(r[2] for r in rows)
    pct = (100.0 * hit / total) if total else 0.0
    return hit, total, pct


def dump(json_path=None, txt_path=None):
    """Write a machine-readable (JSON) + human (txt) functional-coverage report; return the dict."""
    rows = per_point()
    hit, total, pct = overall()
    doc = {
        "tool": "cocotb_coverage",
        "metric": "functional",
        "bins_hit": hit,
        "bins_total": total,
        "pct": round(pct, 2),
        "points": [{"name": n, "covered": c, "size": s, "pct": round(p, 2)}
                   for (n, c, s, p) in rows],
    }
    if json_path:
        with open(json_path, "w") as f:
            json.dump(doc, f, indent=2)
    if txt_path:
        with open(txt_path, "w") as f:
            f.write(f"Functional coverage (cocotb_coverage): {hit}/{total} bins = {pct:.2f}%\n\n")
            for (n, c, s, p) in rows:
                f.write(f"  {n:28s} {c:3d}/{s:<3d} {p:6.1f}%\n")
    return doc
