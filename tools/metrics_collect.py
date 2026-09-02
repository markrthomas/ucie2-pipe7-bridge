#!/usr/bin/env python3
"""Collect one DV-metrics row into ``metrics/metrics.db`` (Phase F increment 4).

ADDITIVE and OUTSIDE the sacred gate. This script never edits RTL, never touches
the trace emitters (``dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv``,
``dv/pyuvm/test_roundtrip.py``) and never changes the fixed clock/reset/stimulus
schedule; it only *runs existing make targets unmodified* and/or *reads logs the
gate already produced*, then parses their ``[BANNER]`` lines.

Usage
-----
    python3 tools/metrics_collect.py                    # default tier set
    python3 tools/metrics_collect.py --run lint,pyuvm   # only these
    python3 tools/metrics_collect.py --run none --log lint=lint.log
    python3 tools/metrics_collect.py --carry-forward    # fill gaps as ESTIMATED

Honesty rules (mirrored in metrics/schema.sql)
---------------------------------------------
* A tier only gets ``source='measured'`` when this invocation saw its own
  banner — either by running it here, or by reading a log the gate produced in
  this same checkout (recorded in ``notes``).
* A tier that could not run (tool absent, too heavy for this host, skipped) is
  recorded ``status='not-run'``, ``source='none'`` — **never** ``fail``, and no
  number is invented for it.
* ``--carry-forward`` may copy the newest previously-*measured* value into an
  otherwise not-run tier; such values are tagged ``source='estimated'`` and the
  row roll-up becomes ``mixed``/``estimated``. Off by default.

Stdlib only (``sqlite3`` module — the ``sqlite3`` CLI is not required).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "metrics" / "metrics.db"
DEFAULT_SCHEMA = ROOT / "metrics" / "schema.sql"

# Tier key -> make target. Keys match the schema's `<key>_status` columns.
TIERS = {
    "lint": "lint",
    "pyuvm": "pyuvm",
    "fcov": "fcov",
    "uvm": "uvm",
    "trace_compare": "trace-compare",
    "coverage": "coverage",
    "formal": "formal",
}
# Accept the make-target spelling on the command line too ("trace-compare").
ALIASES = {t: k for k, t in TIERS.items()}

# Tiers `make metrics` runs by default: everything an ~8 GB host can do without
# the from-source UVM Verilator. `uvm` is deliberately absent — it is picked up
# from the gate's own log (see LOG_FALLBACKS) instead of being rebuilt.
DEFAULT_RUN = "lint,pyuvm,fcov,coverage,formal,trace-compare"

# Logs the gate leaves behind, used when a tier was not run by us.
LOG_FALLBACKS = {
    "uvm": ROOT / "dv" / "uvm" / "vlt" / "obj" / "run.log",
}

# Phrases that mean "the tool isn't here", i.e. absent rather than broken. Only
# consulted when there is no positive pass/fail banner.
ABSENT_MARKERS = (
    "command not found",
    "not found",
    "no such file or directory",
    "unable to locate",          # cocotb: "Unable to locate command >iverilog<"
    "is not installed",
    "no simulator",
    "skip:",
    "modulenotfounderror",
    "importerror",
)


# --------------------------------------------------------------------------
# banner parsers: (text, rc) -> (status, extra_columns_dict)
# --------------------------------------------------------------------------
def _cocotb_result(text: str):
    """Shared cocotb verdict: (status or None) from the results summary."""
    m = re.search(r"TESTS=(\d+)\s+PASS=(\d+)\s+FAIL=(\d+)\s+SKIP=(\d+)", text)
    if m:
        npass, nfail = int(m.group(2)), int(m.group(3))
        if nfail:
            return "fail"
        return "pass" if npass else "not-run"
    if re.search(r"^\s*\*\*\s+\S+\s+FAIL\b", text, re.M):
        return "fail"
    if re.search(r"^\s*\*\*\s+\S+\s+PASS\b", text, re.M):
        return "pass"
    return None


def parse_lint(text: str, rc: int):
    if "[lint] RTL OK" in text:
        return "pass", {}
    return None, {}


def parse_pyuvm(text: str, rc: int):
    return _cocotb_result(text), {}


def parse_fcov(text: str, rc: int):
    extra = {}
    m = re.search(r"\[FCOV\]\s+bins=(\d+)/(\d+)\s*=\s*([\d.]+)%", text)
    if m:
        extra = {
            "fcov_bins_hit": int(m.group(1)),
            "fcov_bins_total": int(m.group(2)),
            "fcov_pct": float(m.group(3)),
        }
    status = _cocotb_result(text)
    if status is None and extra:
        status = "pass" if rc == 0 else "fail"
    if status != "pass":
        # Never publish a bins number attached to a non-passing run.
        extra = {}
    return status, extra


def parse_uvm(text: str, rc: int):
    if "PASS: clean UVM report" in text:
        return "pass", {}
    if re.search(r"^FAIL: ", text, re.M) or "[SVA]" in text:
        return "fail", {}
    return None, {}


def parse_trace_compare(text: str, rc: int):
    m = re.search(r"trace_compare: OK\s*[—-]\s*(\d+) cycles identical", text)
    if m:
        return "pass", {"trace_cycles": int(m.group(1))}
    if "DIVERGENCE" in text or "HEADER MISMATCH" in text:
        return "fail", {}
    return None, {}


def parse_coverage(text: str, rc: int):
    m = re.search(r"\[COV\]\s+line=([\d.]+)%", text)
    if "[COV] ERROR" in text:
        return "fail", {}
    if m:
        pct = float(m.group(1))
        if "[COV] FAIL" in text:
            return "fail", {"coverage_line_pct": pct}
        return "pass", {"coverage_line_pct": pct}
    return None, {}


def parse_formal(text: str, rc: int):
    passed = len(re.findall(r"^\[FORMAL\]\s+\S+:\s+BMC depth \S+ PASSED", text, re.M))
    failed = len(re.findall(r"^\[FORMAL\]\s+\S+:\s+BMC depth \S+ FAILED", text, re.M))
    total = passed + failed
    if "[FORMAL] SKIP:" in text and total == 0:
        return "not-run", {}
    if total == 0:
        return None, {}
    extra = {"formal_jobs_passed": passed, "formal_jobs_total": total}
    return ("fail" if failed else "pass"), extra


PARSERS = {
    "lint": parse_lint,
    "pyuvm": parse_pyuvm,
    "fcov": parse_fcov,
    "uvm": parse_uvm,
    "trace_compare": parse_trace_compare,
    "coverage": parse_coverage,
    "formal": parse_formal,
}

# Columns a tier is allowed to write (so a carried-forward value copies the
# right numbers with it).
TIER_METRICS = {
    "fcov": ("fcov_bins_hit", "fcov_bins_total", "fcov_pct"),
    "trace_compare": ("trace_cycles",),
    "coverage": ("coverage_line_pct",),
    "formal": ("formal_jobs_passed", "formal_jobs_total"),
}


def classify(tier: str, text: str, rc: int):
    """Map (output, exit code) onto a status. Absence never becomes a failure."""
    status, extra = PARSERS[tier](text, rc)
    if status is not None:
        return status, extra
    low = text.lower()
    if any(marker in low for marker in ABSENT_MARKERS):
        return "not-run", {}
    if rc != 0:
        return "fail", {}
    return "not-run", {}


# --------------------------------------------------------------------------
# git / db helpers
# --------------------------------------------------------------------------
def _git(*args: str, default: str = "unknown") -> str:
    try:
        out = subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.SubprocessError):
        return default
    return out.stdout.strip() or default if out.returncode == 0 else default


def open_db(db_path: Path, schema_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.executescript(schema_path.read_text())   # CREATE ... IF NOT EXISTS
    conn.commit()
    return conn


def last_measured(conn: sqlite3.Connection, tier: str):
    """Newest row where `tier` was actually measured, or None."""
    cur = conn.execute(
        f"SELECT * FROM runs WHERE {tier}_source = 'measured' "
        f"AND {tier}_status != 'not-run' ORDER BY id DESC LIMIT 1"
    )
    return cur.fetchone()


# --------------------------------------------------------------------------
def run_tier(tier: str, make: str, log_dir: Path, extra_make_args):
    """Run one make target, tee its output to build/metrics/<tier>.log."""
    target = TIERS[tier]
    cmd = [make, "-C", str(ROOT), target, *extra_make_args]
    t0 = time.monotonic()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        text = (proc.stdout or "") + (proc.stderr or "")
        rc = proc.returncode
    except OSError as exc:                       # e.g. no `make` on PATH at all
        text, rc = f"{make}: command not found ({exc})\n", 127
    secs = time.monotonic() - t0
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"{tier}.log").write_text(text)
    return text, rc, secs


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    ap.add_argument(
        "--run",
        default=DEFAULT_RUN,
        help=f"comma-separated tiers to run (default: {DEFAULT_RUN}); "
             "'none' runs nothing and only reads logs",
    )
    ap.add_argument(
        "--log",
        action="append",
        default=[],
        metavar="TIER=PATH",
        help="parse an existing log for TIER instead of running it (repeatable)",
    )
    ap.add_argument("--env", default=os.environ.get("METRICS_ENV") or
                    ("ci" if os.environ.get("CI") else "local"),
                    help="where this ran: local | ci | railway")
    ap.add_argument("--carry-forward", action="store_true",
                    help="fill not-run tiers from the newest measured row and "
                         "tag them source='estimated' (off by default)")
    ap.add_argument("--note", default=None, help="free-text note for this row")
    ap.add_argument("--make", default=os.environ.get("MAKE") or "make")
    ap.add_argument("--make-arg", action="append", default=[],
                    help="extra argument passed to every make invocation")
    ap.add_argument("--dry-run", action="store_true",
                    help="collect and print, but do not write the database")
    args = ap.parse_args(argv)

    def norm(name: str) -> str:
        key = ALIASES.get(name.strip(), name.strip().replace("-", "_"))
        if key not in TIERS:
            ap.error(f"unknown tier '{name}'; known: {', '.join(TIERS)}")
        return key

    wanted = [] if args.run.strip().lower() in ("", "none") else [
        norm(t) for t in args.run.split(",") if t.strip()
    ]
    logs = {}
    for spec in args.log:
        if "=" not in spec:
            ap.error(f"--log expects TIER=PATH, got '{spec}'")
        name, path = spec.split("=", 1)
        logs[norm(name)] = Path(path)

    row = {
        "ts_utc": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_sha": _git("rev-parse", "--short", "HEAD"),
        "git_branch": _git("rev-parse", "--abbrev-ref", "HEAD"),
        "git_dirty": 1 if _git("status", "--porcelain", default="") else 0,
        "env": args.env,
    }
    for tier in TIERS:
        row[f"{tier}_status"] = "not-run"
        row[f"{tier}_secs"] = None
        row[f"{tier}_source"] = "none"

    notes = []
    log_dir = ROOT / "build" / "metrics"
    t_start = time.monotonic()

    for tier in TIERS:
        # 1) an explicitly supplied log wins;
        # 2) then a tier we were asked to run;
        # 3) then a log the gate already left behind.
        if tier in logs:
            path = logs[tier]
            if not path.exists():
                notes.append(f"{tier}: log {path} missing -> not-run")
                continue
            status, extra = classify(tier, path.read_text(errors="replace"), 0)
            secs = None
            notes.append(f"{tier}: from log {path}")
        elif tier in wanted:
            # trace-compare needs both TB traces; without them the tier is
            # absent on this host, not failing.
            if tier == "trace_compare" and not (
                (ROOT / "dv/pyuvm/build/bridge.trace").exists()
                and (ROOT / "dv/uvm/vlt/obj/bridge.trace").exists()
            ):
                notes.append("trace_compare: no TB trace pair on disk -> not-run")
                continue
            print(f"[METRICS] running: make {TIERS[tier]}", flush=True)
            text, rc, secs = run_tier(tier, args.make, log_dir, args.make_arg)
            status, extra = classify(tier, text, rc)
            if status == "not-run":
                notes.append(f"{tier}: ran but tool/tier absent -> not-run")
        elif tier in LOG_FALLBACKS and LOG_FALLBACKS[tier].exists():
            path = LOG_FALLBACKS[tier]
            status, extra = classify(tier, path.read_text(errors="replace"), 0)
            secs = None
            notes.append(f"{tier}: from gate log {path.relative_to(ROOT)}")
        else:
            continue

        row[f"{tier}_status"] = status
        row[f"{tier}_secs"] = round(secs, 2) if secs is not None else None
        row[f"{tier}_source"] = "none" if status == "not-run" else "measured"
        for col, val in extra.items():
            row[col] = val

    if args.carry_forward:
        conn_peek = open_db(args.db, args.schema)
        for tier in TIERS:
            if row[f"{tier}_source"] != "none":
                continue
            prev = last_measured(conn_peek, tier)
            if prev is None:
                continue
            row[f"{tier}_status"] = prev[f"{tier}_status"]
            row[f"{tier}_secs"] = prev[f"{tier}_secs"]
            row[f"{tier}_source"] = "estimated"
            for col in TIER_METRICS.get(tier, ()):
                row[col] = prev[col]
            notes.append(f"{tier}: ESTIMATED, carried from run #{prev['id']}")
        conn_peek.close()

    sources = {row[f"{t}_source"] for t in TIERS}
    if "measured" in sources and "estimated" in sources:
        row["source"] = "mixed"
    elif "measured" in sources:
        row["source"] = "measured"
    else:
        row["source"] = "estimated"
    row["total_secs"] = round(time.monotonic() - t_start, 2)
    if args.note:
        notes.insert(0, args.note)
    row["notes"] = "; ".join(notes) if notes else None

    summary = "  ".join(
        f"{TIERS[t]}={row[f'{t}_status']}"
        + ("*" if row[f"{t}_source"] == "estimated" else "")
        for t in TIERS
    )
    if args.dry_run:
        print(f"[METRICS] dry-run (nothing written): {summary}")
        return 0

    conn = open_db(args.db, args.schema)
    cols = ", ".join(row)
    marks = ", ".join("?" for _ in row)
    cur = conn.execute(f"INSERT INTO runs ({cols}) VALUES ({marks})",
                       list(row.values()))
    conn.commit()
    rowid, nrows = cur.lastrowid, conn.execute(
        "SELECT COUNT(*) FROM runs").fetchone()[0]
    conn.close()

    try:
        shown_db = args.db.relative_to(ROOT)
    except ValueError:
        shown_db = args.db
    print(f"[METRICS] {summary}")
    if any(row[f"{t}_source"] == "estimated" for t in TIERS):
        print("[METRICS] '*' = ESTIMATED (carried forward, not measured here)")
    print(f"[METRICS] row #{rowid} appended to {shown_db} "
          f"({nrows} row(s), source={row['source']}, "
          f"sha={row['git_sha']}, {row['ts_utc']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
