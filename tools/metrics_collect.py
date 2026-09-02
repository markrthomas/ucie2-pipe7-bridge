#!/usr/bin/env python3
"""Collect one DV-metrics row into ``metrics/metrics.db``.

Phase F increment 4 (the store) + Phase G increment 1 (more signals, trends,
advisory regression flags).

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
* Every Phase-G signal carries its OWN ``*_source`` (``coverage_branch_source``,
  ``formal_depth_source``, ``roundtrip_cycles_source``, ``collect_source``), so a
  number is never implied by its tier's roll-up.

Schema migration (Phase G increment 1)
--------------------------------------
``open_db`` brings an existing ``user_version = 1`` database up to ``2`` in
place: ``ALTER TABLE runs ADD COLUMN`` for each missing v2 column, then the
``CREATE ... IF NOT EXISTS`` script. **Every existing row is preserved**; the new
columns come up NULL / ``'none'``, which is exactly "we never measured that".

Regression flags (Phase G increment 1) — ADVISORY
-------------------------------------------------
Each measured signal is compared with the most recent prior row on the same
``git_branch`` that measured *that same signal*. A flag is raised on pass->fail,
a coverage/depth/cycle-count drop, or a runtime blow-up. The count is printed as
``[METRICS] regressions: N`` and stored in ``runs.regressions`` for the
dashboard badge. It **never** changes the exit status of ``make metrics``, and
nothing on the gate reads it.

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

try:                                            # POSIX only; optional by design
    import resource as _resource
except ImportError:                             # pragma: no cover - non-POSIX
    _resource = None

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "metrics" / "metrics.db"
DEFAULT_SCHEMA = ROOT / "metrics" / "schema.sql"

# The per-cycle trace the pyuvm round-trip writes. Read-only here: counting its
# rows is how we learn the simulated cycle count without touching the emitter.
PYUVM_TRACE = ROOT / "dv" / "pyuvm" / "build" / "bridge.trace"

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
#
# Keys of `extra` are `runs` columns, except FORMAL_JOBS_KEY, which is a
# side-channel for the `formal_jobs` side table and is popped before the INSERT.
# --------------------------------------------------------------------------
FORMAL_JOBS_KEY = "_formal_jobs"



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
        extra = {"coverage_line_pct": float(m.group(1))}
        # Branch % is optional: older datafiles carry no branch points and
        # coverage_report.py then omits the banner entirely. Absent => stays
        # NULL with source 'none'; we never render a missing signal as 0%.
        mb = re.search(r"\[COV\]\s+branch=([\d.]+)%", text)
        if mb:
            extra["coverage_branch_pct"] = float(mb.group(1))
        return ("fail" if "[COV] FAIL" in text else "pass"), extra
    return None, {}


# `[FORMAL] <job>: BMC depth <N|?> PASSED|FAILED`
_FORMAL_JOB_RE = re.compile(
    r"^\[FORMAL\]\s+(\S+):\s+BMC depth (\S+) (PASSED|FAILED)", re.M)


def parse_formal(text: str, rc: int):
    jobs = []
    for name, depth, verdict in _FORMAL_JOB_RE.findall(text):
        jobs.append({
            "job": name,
            "depth": int(depth) if depth.isdigit() else None,
            "status": "pass" if verdict == "PASSED" else "fail",
        })
    if not jobs:
        return ("not-run", {}) if "[FORMAL] SKIP:" in text else (None, {})
    passed = sum(1 for j in jobs if j["status"] == "pass")
    depths = [j["depth"] for j in jobs if j["depth"] is not None]
    extra = {
        "formal_jobs_passed": passed,
        "formal_jobs_total": len(jobs),
        # Deepest bound reached this run; the per-job depths go to `formal_jobs`.
        "formal_depth_max": max(depths) if depths else None,
        FORMAL_JOBS_KEY: jobs,
    }
    return ("fail" if passed != len(jobs) else "pass"), extra


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
    "coverage": ("coverage_line_pct", "coverage_branch_pct"),
    "formal": ("formal_jobs_passed", "formal_jobs_total", "formal_depth_max"),
    "pyuvm": ("roundtrip_cycles",),
}

# Signal-level sources owned by a tier, as (source_col, value_col): carrying a
# tier forward must also downgrade its own signals to 'estimated' (never leave
# them 'measured'). Per-job `formal_jobs` rows are deliberately NOT carried
# forward — a BMC depth is never attributed to a job that did not run.
TIER_SIGNAL_SOURCES = {
    "coverage": (("coverage_branch_source", "coverage_branch_pct"),),
    "formal": (("formal_depth_source", "formal_depth_max"),),
    "pyuvm": (("roundtrip_cycles_source", "roundtrip_cycles"),),
}

# Schema v2 additions, applied to a v1 database with ALTER TABLE ADD COLUMN.
# Column order/decl must match metrics/schema.sql. NOT NULL columns carry a
# DEFAULT so existing rows migrate cleanly.
V2_RUNS_COLUMNS = (
    ("coverage_branch_pct", "REAL"),
    ("coverage_branch_source",
     "TEXT NOT NULL DEFAULT 'none' "
     "CHECK (coverage_branch_source IN ('measured','estimated','none'))"),
    ("formal_depth_max", "INTEGER"),
    ("formal_depth_source",
     "TEXT NOT NULL DEFAULT 'none' "
     "CHECK (formal_depth_source IN ('measured','estimated','none'))"),
    ("roundtrip_cycles", "INTEGER"),
    ("roundtrip_cycles_source",
     "TEXT NOT NULL DEFAULT 'none' "
     "CHECK (roundtrip_cycles_source IN ('measured','estimated','none'))"),
    ("collect_peak_rss_mb", "REAL"),
    ("collect_source",
     "TEXT NOT NULL DEFAULT 'none' "
     "CHECK (collect_source IN ('measured','estimated','none'))"),
    ("regressions", "INTEGER"),
    ("regression_notes", "TEXT"),
)


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


def migrate(conn: sqlite3.Connection) -> list:
    """Bring a pre-existing `runs` table up to schema v2, preserving all rows.

    Purely additive: `ALTER TABLE ... ADD COLUMN` for every v2 column that is
    missing. SQLite keeps existing rows and fills them with the column DEFAULT
    ('none' for the `*_source` columns, NULL for the values) — i.e. "this row
    never measured that signal", which is the honest answer for a v1 row.
    Idempotent, and a no-op on a database created fresh from schema.sql.
    """
    have = {r[1] for r in conn.execute("PRAGMA table_info(runs)")}
    if not have:                                  # brand-new DB: schema.sql does it
        return []
    added = []
    for name, decl in V2_RUNS_COLUMNS:
        if name not in have:
            conn.execute(f"ALTER TABLE runs ADD COLUMN {name} {decl}")
            added.append(name)
    if added:
        conn.commit()
    return added


def open_db(db_path: Path, schema_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    before = conn.execute("PRAGMA user_version").fetchone()[0]
    added = migrate(conn)
    conn.executescript(schema_path.read_text())   # CREATE ... IF NOT EXISTS
    conn.commit()                                 # also sets PRAGMA user_version = 2
    after = conn.execute("PRAGMA user_version").fetchone()[0]
    if added or after != before:
        nrows = conn.execute("SELECT COUNT(*) FROM runs").fetchone()[0]
        print(f"[METRICS] schema migrated v{before} -> v{after}: "
              f"+{len(added)} column(s), {nrows} existing row(s) preserved",
              flush=True)
    return conn


def last_measured(conn: sqlite3.Connection, tier: str):
    """Newest row where `tier` was actually measured, or None."""
    cur = conn.execute(
        f"SELECT * FROM runs WHERE {tier}_source = 'measured' "
        f"AND {tier}_status != 'not-run' ORDER BY id DESC LIMIT 1"
    )
    return cur.fetchone()


def peak_rss_mb():
    """Peak RSS of this process or its heaviest child, in MiB (None if N/A)."""
    if _resource is None:
        return None
    try:
        kb = max(_resource.getrusage(_resource.RUSAGE_SELF).ru_maxrss,
                 _resource.getrusage(_resource.RUSAGE_CHILDREN).ru_maxrss)
    except (ValueError, OSError):                # pragma: no cover
        return None
    if not kb:
        return None
    # Linux reports KiB; macOS reports bytes. Disambiguate on magnitude.
    mb = kb / 1024.0 if kb < 1 << 30 else kb / (1024.0 * 1024.0)
    return round(mb, 1)


def trace_cycle_count(path: Path):
    """Simulated cycles in a per-cycle trace = data rows (header excluded).

    Read-only: the emitter (dv/pyuvm/test_roundtrip.py) and its fixed
    clock/reset/stimulus schedule are never touched by the metrics tier.
    """
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            n = sum(1 for line in fh if line.strip())
    except OSError:
        return None
    return (n - 1) if n > 1 else None             # first line is the CSV header


# --------------------------------------------------------------------------
# Advisory regression flags (Phase G increment 1)
#
# Each signal is compared with the most recent PRIOR row on the same branch that
# measured THAT SAME signal — never with a carried-forward ('estimated') value,
# and never across branches. Purely informational: the caller ignores the result
# for exit-status purposes and no gate ever reads it.
# --------------------------------------------------------------------------
# (column, its *_source column, display name, absolute tolerance)
HIGHER_IS_BETTER = (
    ("coverage_line_pct",   "coverage_source",        "coverage line%",   0.05),
    ("coverage_branch_pct", "coverage_branch_source", "coverage branch%", 0.05),
    ("fcov_pct",            "fcov_source",            "fcov%",            0.05),
    ("formal_depth_max",    "formal_depth_source",    "formal BMC depth", 0),
    ("trace_cycles",        "trace_compare_source",   "trace cycles",     0),
    ("roundtrip_cycles",  "roundtrip_cycles_source",  "round-trip cycles", 0),
)
# A duration only counts as "ballooned" when it BOTH at least doubled and grew
# by >= 5 s — so a 0.09 s -> 0.20 s lint blip is never reported.
DURATION_RATIO = 2.0
DURATION_ABS_S = 5.0


def _prior(conn, branch: str, source_col: str, value_col=None):
    """Newest earlier row on `branch` that measured this signal, or None."""
    sql = f"SELECT * FROM runs WHERE git_branch = ? AND {source_col} = 'measured'"
    if value_col:
        sql += f" AND {value_col} IS NOT NULL"
    sql += " ORDER BY id DESC LIMIT 1"
    return conn.execute(sql, (branch,)).fetchone()


def detect_regressions(conn: sqlite3.Connection, row: dict) -> list:
    """Human-readable regression flags for `row`. Never raises."""
    flags = []
    branch = row.get("git_branch") or "unknown"
    try:
        for tier in TIERS:
            src, status = row[f"{tier}_source"], row[f"{tier}_status"]
            if src != "measured":
                continue
            if status == "fail":
                prev = _prior(conn, branch, f"{tier}_source")
                if prev is not None and prev[f"{tier}_status"] == "pass":
                    flags.append(f"{TIERS[tier]}: pass -> fail "
                                 f"(vs run #{prev['id']})")
            secs = row.get(f"{tier}_secs")
            if secs is None:
                continue
            prev = _prior(conn, branch, f"{tier}_source", f"{tier}_secs")
            if prev is None:
                continue
            was = prev[f"{tier}_secs"]
            if was and secs >= was * DURATION_RATIO and secs - was >= DURATION_ABS_S:
                flags.append(f"{TIERS[tier]}: runtime {was:.1f}s -> {secs:.1f}s "
                             f"(>={DURATION_RATIO:g}x, vs run #{prev['id']})")

        for col, src_col, label, tol in HIGHER_IS_BETTER:
            now = row.get(col)
            if now is None or row.get(src_col) != "measured":
                continue
            prev = _prior(conn, branch, src_col, col)
            if prev is None:
                continue
            was = prev[col]
            if was is not None and now < was - tol:
                fmt = "{:.1f}" if isinstance(was, float) else "{}"
                flags.append(f"{label}: {fmt.format(was)} -> {fmt.format(now)} "
                             f"(vs run #{prev['id']})")
    except (sqlite3.Error, KeyError, TypeError) as exc:   # advisory: never fatal
        flags.append(f"(regression check skipped: {exc})")
    return flags


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
    # v2 signal sources start at 'none' — nothing measured until proven so.
    for pairs in TIER_SIGNAL_SOURCES.values():
        for src_col, _value_col in pairs:
            row[src_col] = "none"

    notes = []
    formal_jobs = []
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
        formal_jobs = extra.pop(FORMAL_JOBS_KEY, formal_jobs)
        for col, val in extra.items():
            row[col] = val

        # v2 signal sources: 'measured' only where this run produced a number.
        if tier == "coverage" and row.get("coverage_branch_pct") is not None:
            row["coverage_branch_source"] = row[f"{tier}_source"]
        if tier == "formal" and row.get("formal_depth_max") is not None:
            row["formal_depth_source"] = row[f"{tier}_source"]
        if tier == "pyuvm" and status == "pass":
            # Cycle count read back from the trace the tier just wrote. Only
            # trusted when the tier ran here (a stale trace from an older
            # checkout must never be reported as this commit's measurement).
            cycles = trace_cycle_count(PYUVM_TRACE) if tier in wanted else None
            if cycles:
                row["roundtrip_cycles"] = cycles
                row["roundtrip_cycles_source"] = "measured"
            elif tier in wanted:
                notes.append("pyuvm: no per-cycle trace on disk -> "
                             "roundtrip_cycles not recorded")

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
            # A carried-forward tier's own signals are estimated too — but only
            # where the source row actually had a number.
            for src_col, value_col in TIER_SIGNAL_SOURCES.get(tier, ()):
                if prev[value_col] is not None:
                    row[src_col] = "estimated"
            notes.append(f"{tier}: ESTIMATED, carried from run #{prev['id']}")
        conn_peek.close()

    sources = {row[f"{t}_source"] for t in TIERS}
    if "measured" in sources and "estimated" in sources:
        row["source"] = "mixed"
    elif "measured" in sources:
        row["source"] = "measured"
    else:
        row["source"] = "estimated"
    # Resources of the collect run itself (v2). Wall time is `total_secs`.
    row["total_secs"] = round(time.monotonic() - t_start, 2)
    rss = peak_rss_mb()
    row["collect_peak_rss_mb"] = rss
    row["collect_source"] = "measured" if rss is not None else "none"

    if args.note:
        notes.insert(0, args.note)

    summary = "  ".join(
        f"{TIERS[t]}={row[f'{t}_status']}"
        + ("*" if row[f"{t}_source"] == "estimated" else "")
        for t in TIERS
    )

    # Advisory regression flags vs. the newest prior MEASURED row on this
    # branch. Computed against the store, so the DB is opened (and migrated)
    # even for --dry-run; only the INSERT below is skipped there.
    conn = open_db(args.db, args.schema)
    flags = detect_regressions(conn, row)
    row["regressions"] = len(flags)
    row["regression_notes"] = "; ".join(flags) if flags else None
    row["notes"] = "; ".join(notes) if notes else None

    if args.dry_run:
        conn.close()
        print(f"[METRICS] dry-run (nothing written): {summary}")
        print(f"[METRICS] regressions: {len(flags)} (advisory)")
        for flag in flags:
            print(f"[METRICS]   ! {flag}")
        return 0

    cols = ", ".join(row)
    marks = ", ".join("?" for _ in row)
    cur = conn.execute(f"INSERT INTO runs ({cols}) VALUES ({marks})",
                       list(row.values()))
    rowid = cur.lastrowid
    # Per-job formal BMC depth (measured runs only).
    if row["formal_source"] == "measured":
        conn.executemany(
            "INSERT OR REPLACE INTO formal_jobs "
            "(run_id, job, depth, status, source) VALUES (?, ?, ?, ?, 'measured')",
            [(rowid, j["job"], j["depth"], j["status"]) for j in formal_jobs])
    conn.commit()
    nrows = conn.execute("SELECT COUNT(*) FROM runs").fetchone()[0]
    conn.close()

    try:
        shown_db = args.db.relative_to(ROOT)
    except ValueError:
        shown_db = args.db
    print(f"[METRICS] {summary}")
    if any(row[f"{t}_source"] == "estimated" for t in TIERS):
        print("[METRICS] '*' = ESTIMATED (carried forward, not measured here)")
    extras = []
    if row.get("coverage_branch_pct") is not None:
        extras.append(f"cov-branch={row['coverage_branch_pct']:.1f}%")
    if row.get("formal_depth_max") is not None:
        extras.append(f"formal-depth<={row['formal_depth_max']}"
                      f" ({len(formal_jobs)} job(s))")
    if row.get("roundtrip_cycles") is not None:
        extras.append(f"roundtrip-cycles={row['roundtrip_cycles']}")
    if rss is not None:
        extras.append(f"peak-rss={rss:.0f}MiB")
    extras.append(f"wall={row['total_secs']:.1f}s")
    print(f"[METRICS] signals: {'  '.join(extras)}")
    # ADVISORY: this line never changes the exit status below.
    print(f"[METRICS] regressions: {len(flags)}"
          f"{' (advisory, not a gate)' if flags else ''}")
    for flag in flags:
        print(f"[METRICS]   ! {flag}")
    print(f"[METRICS] row #{rowid} appended to {shown_db} "
          f"({nrows} row(s), source={row['source']}, "
          f"sha={row['git_sha']}, {row['ts_utc']})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
