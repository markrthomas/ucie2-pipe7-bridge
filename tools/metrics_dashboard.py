#!/usr/bin/env python3
"""Regenerate ``metrics/dashboard.html`` from ``metrics/metrics.db``.

Phase F increment 4 + Phase G increment 1. ADDITIVE and OUTSIDE the sacred gate:
this reads the metrics database only and writes one HTML file. It never runs a
DV tier, never touches RTL/dv, and cannot perturb the byte-identical per-cycle
trace.

The output is a **single self-contained** file: all CSS is inlined in a
``<style>`` block, the trend charts are inline ``<svg>`` polylines drawn here
(no chart library), and there is **no CDN, no external fetch, no <script src>**.
Double-clicking the file renders it fully offline.

Phase G increment 1 adds:

* **Trends per branch** — the charts plot the history of the *latest row's*
  ``git_branch`` only, so a feature branch is never compared against ``main``.
* **Extra signals** — coverage branch %, per-job formal BMC depth (from the
  ``formal_jobs`` side table), round-trip sim cycles, collect peak RSS. Each is
  rendered from its own ``*_source`` and shown as "—" when never measured.
* **Regression badge** — the advisory flags ``tools/metrics_collect.py`` stored
  on the row. Display only: this script has no exit-status opinion about them.

Rows written before the v2 migration simply lack the new columns; every read
goes through :func:`get`, so an un-migrated v1 database still renders.

Stdlib only (``sqlite3`` module; the ``sqlite3`` CLI is not required).

    python3 tools/metrics_dashboard.py [--db metrics/metrics.db]
                                       [--out metrics/dashboard.html]
                                       [--limit 50]
"""

from __future__ import annotations

import argparse
import datetime as _dt
import html
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DB = ROOT / "metrics" / "metrics.db"
DEFAULT_OUT = ROOT / "metrics" / "dashboard.html"

# (column prefix, display name, one-line description)
TIERS = [
    ("lint",          "lint",          "RTL strict lint (Verilator -Wall)"),
    ("pyuvm",         "pyuvm",         "PyUVM-on-cocotb directed round-trip"),
    ("fcov",          "fcov",          "functional coverage (cocotb_coverage)"),
    ("uvm",           "uvm",           "SV UVM --binary build + run"),
    ("trace_compare", "trace-compare", "cycle-accurate PyUVM == UVM trace diff"),
    ("coverage",      "coverage",      "RTL line coverage (post-gate, advisory)"),
    ("formal",        "formal",        "SymbiYosys BMC (post-gate)"),
]
GATE = {"lint", "pyuvm", "fcov", "uvm", "trace_compare"}

CSS = """
:root{--bg:#0f1420;--panel:#171e2e;--panel2:#1d2537;--fg:#e6ecf7;--dim:#93a1bd;
--line:#2a3448;--pass:#3fb950;--fail:#f85149;--warn:#d29922}
*{box-sizing:border-box}
body{margin:0;padding:32px 24px 64px;background:var(--bg);color:var(--fg);
 font:14px/1.5 ui-sans-serif,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:1080px;margin:0 auto}
h1{font-size:22px;margin:0 0 4px}
h2{font-size:15px;text-transform:uppercase;letter-spacing:.08em;color:var(--dim);
 margin:34px 0 12px;font-weight:600}
.sub{color:var(--dim);font-size:13px;margin:0 0 8px}
code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:18px}
.meta{display:flex;flex-wrap:wrap;gap:10px 26px;margin-bottom:18px}
.meta div{font-size:13px;color:var(--dim)}
.meta b{display:block;color:var(--fg);font-size:14px;font-weight:600}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(196px,1fr));gap:12px}
.tile{background:var(--panel2);border:1px solid var(--line);border-left-width:4px;
 border-radius:8px;padding:12px 14px}
.tile.pass{border-left-color:var(--pass)}
.tile.fail{border-left-color:var(--fail)}
.tile.notrun{border-left-color:#3d4761}
.tile .n{font-weight:600;font-size:14px}
.tile .v{font-size:20px;margin:6px 0 2px;font-variant-numeric:tabular-nums}
.tile .d{color:var(--dim);font-size:12px}
.pill{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;
 font-weight:700;letter-spacing:.04em;text-transform:uppercase}
.pill.pass{background:rgba(63,185,80,.16);color:var(--pass)}
.pill.fail{background:rgba(248,81,73,.16);color:var(--fail)}
.pill.notrun{background:rgba(147,161,189,.14);color:var(--dim)}
.badge{display:inline-block;margin-left:6px;padding:0 6px;border-radius:4px;
 font-size:10px;font-weight:700;letter-spacing:.05em;text-transform:uppercase}
.badge.measured{background:rgba(88,166,255,.14);color:#58a6ff}
.badge.estimated{background:rgba(210,153,34,.18);color:var(--warn)}
.badge.none{background:rgba(147,161,189,.10);color:var(--dim)}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{padding:7px 9px;border-bottom:1px solid var(--line);text-align:left;
 white-space:nowrap;font-variant-numeric:tabular-nums}
th{color:var(--dim);font-weight:600;font-size:11px;text-transform:uppercase;
 letter-spacing:.06em}
tr:last-child td{border-bottom:none}
tbody tr:hover{background:rgba(255,255,255,.03)}
.s-pass{color:var(--pass);font-weight:700}
.s-fail{color:var(--fail);font-weight:700}
.s-notrun{color:#5d6982}
.s-est{color:var(--warn);font-weight:700}
.charts{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}
.chart{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px}
.chart .t{font-size:13px;font-weight:600;margin-bottom:2px}
.chart .r{color:var(--dim);font-size:12px;margin-bottom:8px}
.note{color:var(--dim);font-size:12px;margin-top:10px}
.note-inline{color:var(--dim);font-size:11px}
.tile .sig{margin-top:4px;color:#7d8cab;font-size:11px}
.flags{margin:12px 0 0;padding-left:20px;color:var(--fail);font-size:12.5px}
.flags li{margin:2px 0}
.legend{color:var(--dim);font-size:12px;line-height:1.9}
footer{color:var(--dim);font-size:12px;margin-top:34px;border-top:1px solid var(--line);
 padding-top:14px}
"""


def esc(value) -> str:
    return html.escape("" if value is None else str(value))


def get(row: sqlite3.Row, key: str, default=None):
    """Column value, or `default` when the row predates that column (v1 DB)."""
    try:
        return row[key]
    except (IndexError, KeyError):
        return default


def status_class(status: str) -> str:
    return {"pass": "pass", "fail": "fail"}.get(status, "notrun")


def fmt_secs(secs) -> str:
    if secs is None:
        return "—"
    return f"{secs:.1f}s" if secs < 60 else f"{secs / 60:.1f}m"


def tier_value(row: sqlite3.Row, key: str) -> str:
    """The headline number for a tier, or '—' when there isn't one."""
    if row[f"{key}_status"] == "not-run":
        return "not run"
    if key == "fcov" and row["fcov_bins_total"]:
        return f"{row['fcov_bins_hit']}/{row['fcov_bins_total']} bins"
    if key == "coverage" and row["coverage_line_pct"] is not None:
        return f"{row['coverage_line_pct']:.1f}% lines"
    if key == "formal" and row["formal_jobs_total"]:
        return f"{row['formal_jobs_passed']}/{row['formal_jobs_total']} jobs"
    if key == "trace_compare" and row["trace_cycles"]:
        return f"{row['trace_cycles']} cycles"
    if key == "pyuvm" and get(row, "roundtrip_cycles"):
        return f"{row['roundtrip_cycles']} cycles"
    return row[f"{key}_status"]


def tier_detail(row: sqlite3.Row, key: str) -> str:
    """Second-line detail for a tile: the v2 signals, honest about absence."""
    if key == "coverage":
        br = get(row, "coverage_branch_pct")
        src = get(row, "coverage_branch_source", "none")
        if br is not None:
            return f"branch {br:.1f}% ({src})"
        return "branch % not measured"
    if key == "formal":
        depth = get(row, "formal_depth_max")
        src = get(row, "formal_depth_source", "none")
        if depth is not None:
            return f"BMC depth &le; {depth} ({src})"
        return "BMC depth not measured"
    if key == "pyuvm":
        cycles = get(row, "roundtrip_cycles")
        src = get(row, "roundtrip_cycles_source", "none")
        if cycles is not None:
            return f"round-trip sim {cycles} cycles ({src})"
        return "sim cycle count not measured"
    return ""


def sparkline(values, *, width=300, height=64, pad=8, fmt="{:.1f}") -> str:
    """Inline SVG polyline drawn from scratch. `values` may contain None."""
    pts = [(i, v) for i, v in enumerate(values) if v is not None]
    if not pts:
        # NB: f-string, not %-formatting — the literal `width="100%"` below is
        # not a format spec and %-formatting choked on it.
        return (f'<svg width="100%" viewBox="0 0 {width} {height}" role="img">'
                f'<text x="{pad}" y="{height // 2}" fill="#93a1bd" '
                f'font-size="12">no measured data yet</text></svg>')
    lo = min(v for _, v in pts)
    hi = max(v for _, v in pts)
    span = (hi - lo) or 1.0
    n = max(len(values) - 1, 1)

    def sx(i):
        return pad + (width - 2 * pad) * (i / n)

    def sy(v):
        return height - pad - (height - 2 * pad) * ((v - lo) / span)

    poly = " ".join(f"{sx(i):.1f},{sy(v):.1f}" for i, v in pts)
    area = (f"{sx(pts[0][0]):.1f},{height - pad:.1f} " + poly +
            f" {sx(pts[-1][0]):.1f},{height - pad:.1f}")
    dots = "".join(
        f'<circle cx="{sx(i):.1f}" cy="{sy(v):.1f}" r="2.4" fill="#58a6ff"/>'
        for i, v in pts[-12:]
    )
    return (
        f'<svg width="100%" viewBox="0 0 {width} {height}" preserveAspectRatio="none" '
        f'role="img" aria-label="trend, latest {fmt.format(pts[-1][1])}">'
        f'<polygon points="{area}" fill="rgba(88,166,255,.13)"/>'
        f'<polyline points="{poly}" fill="none" stroke="#58a6ff" stroke-width="2" '
        f'stroke-linejoin="round" stroke-linecap="round"/>{dots}</svg>'
    )


def chart(title: str, unit: str, values, fmt="{:.1f}") -> str:
    seen = [v for v in values if v is not None]
    rng = (f"latest {fmt.format(seen[-1])}{unit} · min {fmt.format(min(seen))}"
           f"{unit} · max {fmt.format(max(seen))}{unit} · n={len(seen)}"
           if seen else "no measured points yet")
    return (f'<div class="chart"><div class="t">{esc(title)}</div>'
            f'<div class="r">{esc(rng)}</div>{sparkline(values, fmt=fmt)}</div>')


def render(rows, branch_rows, formal_jobs, db_path: Path) -> str:
    latest = rows[0]
    # Trends follow ONE branch (the latest row's), so a feature branch is never
    # silently compared against main. Oldest -> newest for the charts.
    history = list(reversed(branch_rows)) or list(reversed(rows))
    branch = latest["git_branch"]
    gen = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    tiles = []
    for key, name, desc in TIERS:
        st = latest[f"{key}_status"]
        src = latest[f"{key}_source"]
        badge = (f'<span class="badge {src}">{esc(src)}</span>'
                 if src != "none" else "")
        post = "" if key in GATE else '<span class="badge none">post-gate</span>'
        detail = tier_detail(latest, key)
        tiles.append(
            f'<div class="tile {status_class(st)}">'
            f'<div class="n">{esc(name)} {post}</div>'
            f'<div class="v">{esc(tier_value(latest, key))}</div>'
            f'<div class="d"><span class="pill {status_class(st)}">{esc(st)}</span>'
            f'{badge} · {esc(fmt_secs(latest[f"{key}_secs"]))}</div>'
            f'<div class="d">{esc(desc)}</div>'
            + (f'<div class="d sig">{detail}</div>' if detail else "")
            + '</div>'
        )

    head = ("<tr><th>#</th><th>timestamp (UTC)</th><th>sha</th><th>branch</th>"
            "<th>env</th><th>row source</th>"
            + "".join(f"<th>{esc(n)}</th>" for _, n, _ in TIERS)
            + "<th>cov line%</th><th>cov br%</th><th>fcov</th><th>formal</th>"
              "<th>bmc depth</th><th>rt cycles</th><th>total</th><th>peak RSS</th>"
              "<th>regr</th></tr>")
    body = []
    for r in rows:
        cells = []
        for key, _, _ in TIERS:
            st, src = r[f"{key}_status"], r[f"{key}_source"]
            cls = "s-est" if src == "estimated" else f"s-{status_class(st)}"
            mark = "*" if src == "estimated" else ""
            cells.append(f'<td class="{cls}">{esc(st)}{mark}</td>')
        cov = ("—" if r["coverage_line_pct"] is None
               else f"{r['coverage_line_pct']:.1f}%")
        covb = ("—" if get(r, "coverage_branch_pct") is None
                else f"{r['coverage_branch_pct']:.1f}%")
        fc = ("—" if not r["fcov_bins_total"]
              else f"{r['fcov_bins_hit']}/{r['fcov_bins_total']}")
        fm = ("—" if not r["formal_jobs_total"]
              else f"{r['formal_jobs_passed']}/{r['formal_jobs_total']}")
        depth = ("—" if get(r, "formal_depth_max") is None
                 else f"&le;{r['formal_depth_max']}")
        rtc = ("—" if get(r, "roundtrip_cycles") is None
               else str(r["roundtrip_cycles"]))
        rss = ("—" if get(r, "collect_peak_rss_mb") is None
               else f"{r['collect_peak_rss_mb']:.0f}M")
        nr = get(r, "regressions")
        reg = ("—" if nr is None
               else f'<span class="s-pass">0</span>' if nr == 0
               else f'<span class="s-fail">{nr}</span>')
        dirty = " <span class='badge estimated'>dirty</span>" if r["git_dirty"] else ""
        body.append(
            f'<tr><td>{r["id"]}</td><td class="mono">{esc(r["ts_utc"])}</td>'
            f'<td class="mono">{esc(r["git_sha"])}{dirty}</td>'
            f'<td class="mono">{esc(r["git_branch"])}</td><td>{esc(r["env"])}</td>'
            f'<td><span class="badge {"estimated" if r["source"] != "measured" else "measured"}">'
            f'{esc(r["source"])}</span></td>'
            + "".join(cells)
            + f'<td>{esc(cov)}</td><td>{esc(covb)}</td><td>{esc(fc)}</td>'
            f'<td>{esc(fm)}</td><td>{depth}</td><td>{esc(rtc)}</td>'
            f'<td>{esc(fmt_secs(r["total_secs"]))}</td><td>{esc(rss)}</td>'
            f'<td>{reg}</td></tr>'
        )

    def series(col, src_col=None):
        """History of one column, keeping only points that were MEASURED."""
        out = []
        for r in history:
            val = get(r, col)
            if src_col is not None and get(r, src_col, "measured") != "measured":
                val = None                  # carried-forward: not a data point
            out.append(val)
        return out

    charts = "".join([
        chart("RTL line coverage", "%",
              series("coverage_line_pct", "coverage_source")),
        chart("RTL branch coverage", "%",
              series("coverage_branch_pct", "coverage_branch_source")),
        chart("Functional coverage", "%", series("fcov_pct", "fcov_source")),
        chart("Formal BMC depth (deepest job)", "",
              series("formal_depth_max", "formal_depth_source"), fmt="{:.0f}"),
        chart("Round-trip sim cycles", "",
              series("roundtrip_cycles", "roundtrip_cycles_source"),
              fmt="{:.0f}"),
        chart("lint tier runtime", "s", series("lint_secs", "lint_source")),
        chart("pyuvm tier runtime", "s", series("pyuvm_secs", "pyuvm_source")),
        chart("fcov tier runtime", "s", series("fcov_secs", "fcov_source")),
        chart("collect wall time", "s", series("total_secs")),
        chart("collect peak RSS", " MiB",
              series("collect_peak_rss_mb", "collect_source"), fmt="{:.0f}"),
    ])

    # Advisory regression flags, as stored by tools/metrics_collect.py.
    nreg = get(latest, "regressions")
    reg_notes = get(latest, "regression_notes")
    if nreg is None:
        reg_badge = ('<span class="pill notrun">regressions n/a</span>'
                     ' <span class="note-inline">row predates the v2 check</span>')
        reg_block = ""
    elif nreg:
        reg_badge = f'<span class="pill fail">{nreg} regression(s)</span>'
        reg_block = ('<ul class="flags">'
                     + "".join(f"<li>{esc(f)}</li>"
                               for f in (reg_notes or "").split("; ") if f)
                     + "</ul>")
    else:
        reg_badge = '<span class="pill pass">no regressions</span>'
        reg_block = ""

    if formal_jobs:
        fj = ('<p class="note">formal BMC depth per job (measured): '
              + ", ".join(
                  f'<code>{esc(j["job"])}</code> depth {esc(j["depth"])}'
                  f' {esc(j["status"])}' for j in formal_jobs)
              + "</p>")
    else:
        fj = ('<p class="note">formal BMC depth per job: not measured for this '
              "row.</p>")

    notes = latest["notes"] or "—"
    est_here = any(latest[f"{k}_source"] == "estimated" for k, _, _ in TIERS)

    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ucie2-pipe7-bridge — DV metrics</title>
<style>{CSS}</style></head>
<body><div class="wrap">
<h1>ucie2-pipe7-bridge — DV metrics</h1>
<p class="sub">Self-contained dashboard (no CDN, no external fetch) generated by
<code>tools/metrics_dashboard.py</code> from <code>{esc(db_path.name)}</code> at
{esc(gen)}. Post-gate and advisory: nothing here runs, gates, or perturbs
<code>lint / pyuvm / fcov / uvm / trace-compare</code>.</p>

<h2>Latest run</h2>
<div class="card">
  <div class="meta">
    <div>run<b>#{latest["id"]}</b></div>
    <div>timestamp<b class="mono">{esc(latest["ts_utc"])}</b></div>
    <div>commit<b class="mono">{esc(latest["git_sha"])}{" (dirty)" if latest["git_dirty"] else ""}</b></div>
    <div>branch<b class="mono">{esc(latest["git_branch"])}</b></div>
    <div>env<b>{esc(latest["env"])}</b></div>
    <div>row source<b>{esc(latest["source"])}</b></div>
    <div>collect wall time<b>{esc(fmt_secs(latest["total_secs"]))}</b></div>
    <div>collect peak RSS<b>{esc(f"{get(latest, 'collect_peak_rss_mb'):.0f} MiB") if get(latest, 'collect_peak_rss_mb') is not None else "—"}</b></div>
    <div>regressions<b>{reg_badge}</b></div>
  </div>
  <div class="tiles">{"".join(tiles)}</div>
  {reg_block}
  {fj}
  <p class="note">collector notes: {esc(notes)}</p>
  {'<p class="note">This row mixes ESTIMATED (carried-forward) values with measured ones — see the badges.</p>' if est_here else ''}
</div>

<h2>Trends — branch <code>{esc(branch)}</code> ({len(history)} run(s))</h2>
<p class="sub">Inline SVG drawn by <code>tools/metrics_dashboard.py</code> — no
chart library, no CDN. Only <b>measured</b> points are plotted: a carried-forward
(estimated) value leaves a gap rather than faking a data point, and history is
restricted to this one branch.</p>
<div class="charts">{charts}</div>

<h2>History ({len(rows)} run(s))</h2>
<div class="card"><table><thead>{head}</thead><tbody>{"".join(body)}</tbody></table>
<p class="legend">
<span class="badge measured">measured</span> the tier ran for this row and this
banner is its own output.<br>
<span class="badge estimated">estimated</span> (also marked <span class="s-est">*</span>)
carried forward from an older measured run — <b>not</b> a measurement of this
commit.<br>
<span class="s-notrun">not-run</span> the tier did not run (tool absent, or too
heavy for that host). Never counted as a failure, and no number is invented.<br>
<span class="s-fail">regr</span> advisory regression count vs. the most recent
prior <b>measured</b> row on the same branch (coverage/depth/cycle drop, a
runtime that at least doubled AND grew &ge;5 s, or a tier going pass&rarr;fail).
<b>Advisory only</b> — it never fails <code>make metrics</code>,
<code>make dashboard</code>, or any gate. "—" = the row predates the check.
</p></div>

<footer>Phase F increment 4 + Phase G increment 1 — <code>make metrics</code>
appends a row, <code>make dashboard</code> regenerates this file. Both are
additive and outside the gate. Store: <code>metrics/metrics.db</code> (schema:
<code>metrics/schema.sql</code>, <code>user_version = 2</code>).</footer>
</div></body></html>
"""


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--limit", type=int, default=50,
                    help="most recent N rows to show (default 50)")
    args = ap.parse_args(argv)

    if not args.db.exists():
        print(f"[DASH] ERROR: no metrics database at {args.db} — "
              f"run `make metrics` first", file=sys.stderr)
        return 1
    conn = sqlite3.connect(str(args.db))
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT * FROM runs ORDER BY id DESC LIMIT ?", (args.limit,)).fetchall()
    total = conn.execute("SELECT COUNT(*) FROM runs").fetchone()[0]
    if not rows:
        conn.close()
        print(f"[DASH] ERROR: {args.db} has no rows — run `make metrics` first",
              file=sys.stderr)
        return 1
    # Trend history: same branch only, newest first (render() reverses it).
    branch_rows = conn.execute(
        "SELECT * FROM runs WHERE git_branch = ? ORDER BY id DESC LIMIT ?",
        (rows[0]["git_branch"], args.limit)).fetchall()
    # Per-job formal BMC depth for the latest run (v2; absent on a v1 store).
    try:
        formal_jobs = conn.execute(
            "SELECT job, depth, status FROM formal_jobs WHERE run_id = ? "
            "ORDER BY job", (rows[0]["id"],)).fetchall()
    except sqlite3.Error:
        formal_jobs = []
    conn.close()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(rows, branch_rows, formal_jobs, args.db),
                        encoding="utf-8")
    try:
        shown = args.out.relative_to(ROOT)
    except ValueError:
        shown = args.out
    print(f"[DASH] wrote {shown} ({args.out.stat().st_size} bytes, "
          f"{len(rows)} of {total} row(s), self-contained: no CDN/JS/external fetch)")
    nreg = get(rows[0], "regressions")
    print(f"[DASH] trends: branch {rows[0]['git_branch']} "
          f"({len(branch_rows)} run(s)), inline SVG; regressions: "
          f"{'n/a (pre-v2 row)' if nreg is None else f'{nreg} (advisory)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
