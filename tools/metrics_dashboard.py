#!/usr/bin/env python3
"""Regenerate ``metrics/dashboard.html`` from ``metrics/metrics.db``.

Phase F increment 4. ADDITIVE and OUTSIDE the sacred gate: this reads the
metrics database only and writes one HTML file. It never runs a DV tier, never
touches RTL/dv, and cannot perturb the byte-identical per-cycle trace.

The output is a **single self-contained** file: all CSS is inlined in a
``<style>`` block, the trend charts are inline ``<svg>`` polylines drawn here
(no chart library), and there is **no CDN, no external fetch, no <script src>**.
Double-clicking the file renders it fully offline.

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
.legend{color:var(--dim);font-size:12px;line-height:1.9}
footer{color:var(--dim);font-size:12px;margin-top:34px;border-top:1px solid var(--line);
 padding-top:14px}
"""


def esc(value) -> str:
    return html.escape("" if value is None else str(value))


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
    return row[f"{key}_status"]


def sparkline(values, *, width=300, height=64, pad=8, fmt="{:.1f}") -> str:
    """Inline SVG polyline drawn from scratch. `values` may contain None."""
    pts = [(i, v) for i, v in enumerate(values) if v is not None]
    if not pts:
        return ('<svg width="100%" viewBox="0 0 %d %d" role="img">'
                '<text x="%d" y="%d" fill="#93a1bd" font-size="12">no data yet'
                '</text></svg>' % (width, height, pad, height // 2))
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


def render(rows, db_path: Path) -> str:
    latest = rows[0]
    history = list(reversed(rows))          # oldest -> newest for the charts
    gen = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    tiles = []
    for key, name, desc in TIERS:
        st = latest[f"{key}_status"]
        src = latest[f"{key}_source"]
        badge = (f'<span class="badge {src}">{esc(src)}</span>'
                 if src != "none" else "")
        post = "" if key in GATE else '<span class="badge none">post-gate</span>'
        tiles.append(
            f'<div class="tile {status_class(st)}">'
            f'<div class="n">{esc(name)} {post}</div>'
            f'<div class="v">{esc(tier_value(latest, key))}</div>'
            f'<div class="d"><span class="pill {status_class(st)}">{esc(st)}</span>'
            f'{badge} · {esc(fmt_secs(latest[f"{key}_secs"]))}</div>'
            f'<div class="d">{esc(desc)}</div></div>'
        )

    head = ("<tr><th>#</th><th>timestamp (UTC)</th><th>sha</th><th>branch</th>"
            "<th>env</th><th>row source</th>"
            + "".join(f"<th>{esc(n)}</th>" for _, n, _ in TIERS)
            + "<th>cov %</th><th>fcov</th><th>formal</th><th>total</th></tr>")
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
        fc = ("—" if not r["fcov_bins_total"]
              else f"{r['fcov_bins_hit']}/{r['fcov_bins_total']}")
        fm = ("—" if not r["formal_jobs_total"]
              else f"{r['formal_jobs_passed']}/{r['formal_jobs_total']}")
        dirty = " <span class='badge estimated'>dirty</span>" if r["git_dirty"] else ""
        body.append(
            f'<tr><td>{r["id"]}</td><td class="mono">{esc(r["ts_utc"])}</td>'
            f'<td class="mono">{esc(r["git_sha"])}{dirty}</td>'
            f'<td class="mono">{esc(r["git_branch"])}</td><td>{esc(r["env"])}</td>'
            f'<td><span class="badge {"estimated" if r["source"] != "measured" else "measured"}">'
            f'{esc(r["source"])}</span></td>'
            + "".join(cells)
            + f'<td>{esc(cov)}</td><td>{esc(fc)}</td><td>{esc(fm)}</td>'
            f'<td>{esc(fmt_secs(r["total_secs"]))}</td></tr>'
        )

    charts = "".join([
        chart("RTL line coverage", "%",
              [r["coverage_line_pct"] for r in history]),
        chart("Functional coverage", "%", [r["fcov_pct"] for r in history]),
        chart("pyuvm tier runtime", "s",
              [r["pyuvm_secs"] for r in history]),
        chart("collect wall time", "s", [r["total_secs"] for r in history]),
    ])

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
  </div>
  <div class="tiles">{"".join(tiles)}</div>
  <p class="note">collector notes: {esc(notes)}</p>
  {'<p class="note">This row mixes ESTIMATED (carried-forward) values with measured ones — see the badges.</p>' if est_here else ''}
</div>

<h2>Trends</h2>
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
heavy for that host). Never counted as a failure, and no number is invented.
</p></div>

<footer>Phase F increment 4 — <code>make metrics</code> appends a row,
<code>make dashboard</code> regenerates this file. Both are additive and outside
the gate. Store: <code>metrics/metrics.db</code> (schema:
<code>metrics/schema.sql</code>).</footer>
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
    conn.close()
    if not rows:
        print(f"[DASH] ERROR: {args.db} has no rows — run `make metrics` first",
              file=sys.stderr)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(rows, args.db), encoding="utf-8")
    try:
        shown = args.out.relative_to(ROOT)
    except ValueError:
        shown = args.out
    print(f"[DASH] wrote {shown} ({args.out.stat().st_size} bytes, "
          f"{len(rows)} of {total} row(s), self-contained: no CDN/JS/external fetch)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
