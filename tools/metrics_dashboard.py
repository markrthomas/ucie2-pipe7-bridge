#!/usr/bin/env python3
"""Regenerate ``metrics/dashboard.html`` from ``metrics/metrics.db``.

Phase F increment 4 + Phase G increments 1-2. ADDITIVE and OUTSIDE the sacred
gate: this reads the metrics database only and writes one HTML file. It never
runs a DV tier, never touches RTL/dv, and cannot perturb the byte-identical
per-cycle trace.

The output is a **single self-contained** file: all CSS is inlined in a
``<style>`` block, the filter/sort behaviour is a dependency-free ES5 snippet
inlined in a ``<script>`` block, the trend charts are inline ``<svg>`` polylines
drawn here (no chart library), and there is **no CDN, no external fetch, no
``<script src>``, no ``<link>``, no ``@import``, no ``url(...)``**. Double-clicking
the file renders it fully offline; :func:`external_refs` re-checks that on every
generation and the ``[DASH]`` banner prints the count.

Phase G increment 1 adds:

* **Trends per branch** — the charts plot the history of the *latest row's*
  ``git_branch`` only, so a feature branch is never compared against ``main``.
* **Extra signals** — coverage branch %, per-job formal BMC depth (from the
  ``formal_jobs`` side table), round-trip sim cycles, collect peak RSS. Each is
  rendered from its own ``*_source`` and shown as "—" when never measured.
* **Regression badge** — the advisory flags ``tools/metrics_collect.py`` stored
  on the row. Display only: this script has no exit-status opinion about them.

Phase G increment 2 adds (display only — the store is untouched):

* **Filterable / sortable run history** — a free-text filter plus branch, env
  and "measured rows only" controls, and click-to-sort on every column, driven
  by the inlined script. With JavaScript disabled the table still renders in
  full, just unsorted and unfiltered.
* **Per-tier drill-down** — one ``<details>`` panel per tier with that tier's
  own history, signals and ``*_source`` per row (no JS needed).
* **``git_sha`` -> commit links** — resolved once at generation time from
  ``git remote get-url origin`` (override with ``--repo-url``, disable with
  ``--repo-url ''``). These are ``<a href>`` navigation links, not fetches.

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
import re
import sqlite3
import subprocess
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

/* --- Phase G increment 2: filter/sort toolbar, drill-down, commit links --- */
.toolbar{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin-bottom:14px}
.toolbar input[type=text],.toolbar select{background:var(--panel2);color:var(--fg);
 border:1px solid var(--line);border-radius:6px;padding:6px 9px;font:13px/1.4 inherit}
.toolbar input[type=text]{min-width:230px}
.toolbar label{color:var(--dim);font-size:12px;display:flex;align-items:center;gap:5px}
.toolbar button{background:var(--panel2);color:var(--dim);border:1px solid var(--line);
 border-radius:6px;padding:6px 11px;font:12px/1.4 inherit;cursor:pointer}
.toolbar button:hover{color:var(--fg)}
.toolbar .count{margin-left:auto;color:var(--dim);font-size:12px}
th.sortable{cursor:pointer;-webkit-user-select:none;user-select:none}
th.sortable:hover{color:var(--fg)}
th.sortable::after{content:"↕";opacity:.35;font-size:10px;margin-left:5px}
th.sortable[data-dir=asc]::after{content:"▲";opacity:1;color:#58a6ff}
th.sortable[data-dir=desc]::after{content:"▼";opacity:1;color:#58a6ff}
a.sha{color:#58a6ff;text-decoration:none;border-bottom:1px dotted rgba(88,166,255,.55)}
a.sha:hover{border-bottom-style:solid}
details.drill{background:var(--panel);border:1px solid var(--line);border-radius:10px;
 padding:0 16px;margin-bottom:10px}
details.drill>summary{cursor:pointer;padding:12px 0;font-weight:600;font-size:13.5px;
 list-style:none;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
details.drill>summary::-webkit-details-marker{display:none}
details.drill>summary::before{content:"▸";color:var(--dim);display:inline-block}
details.drill[open]>summary::before{content:"▾"}
details.drill .sum{color:var(--dim);font-weight:400;font-size:12px}
details.drill .body{padding:0 0 16px}
.scroll{overflow-x:auto}
.nojs{color:var(--dim);font-size:12px;margin:0 0 10px}
"""

# Inline, dependency-free filter + sort for the history table (Phase G
# increment 2). Deliberately plain ES5 in a <script> block inside the page:
# NO CDN, no <script src>, no fetch/XHR — the file still opens offline, and with
# JavaScript disabled the table below simply renders unfiltered and unsorted.
JS = """
(function () {
  var t = document.getElementById('hist');
  if (!t || !t.tHead || !t.tBodies.length) { return; }
  var tb = t.tBodies[0];
  var rows = Array.prototype.slice.call(tb.rows);
  var q = document.getElementById('f-text');
  var br = document.getElementById('f-branch');
  var ev = document.getElementById('f-env');
  var me = document.getElementById('f-measured');
  var cnt = document.getElementById('f-count');

  function apply() {
    var s = (q.value || '').toLowerCase();
    var b = br.value, e = ev.value, m = me.checked, n = 0;
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i];
      var ok = (!s || r.getAttribute('data-search').indexOf(s) >= 0)
            && (b === '*' || r.getAttribute('data-branch') === b)
            && (e === '*' || r.getAttribute('data-env') === e)
            && (!m || r.getAttribute('data-source') === 'measured');
      r.style.display = ok ? '' : 'none';
      if (ok) { n++; }
    }
    cnt.textContent = n + ' of ' + rows.length + ' run(s) shown';
  }

  function key(td) {
    var v = td.getAttribute('data-v');
    if (v === null) { v = (td.textContent || '').trim(); }
    if (v !== '' && /^-?[0-9]+(\\.[0-9]+)?$/.test(v)) { return parseFloat(v); }
    return v.toLowerCase();
  }

  var head = t.tHead.rows[0];
  var dir = {};
  for (var c = 0; c < head.cells.length; c++) {
    (function (th, idx) {
      th.className += ' sortable';
      th.tabIndex = 0;
      th.title = 'sort by ' + (th.textContent || '').trim();
      function sort() {
        var d = dir[idx] = (dir[idx] === 1 ? -1 : 1);
        for (var k = 0; k < head.cells.length; k++) {
          head.cells[k].removeAttribute('data-dir');
        }
        th.setAttribute('data-dir', d === 1 ? 'asc' : 'desc');
        rows.sort(function (a, b) {
          var x = key(a.cells[idx]), y = key(b.cells[idx]);
          if (x < y) { return -d; }
          if (x > y) { return d; }
          return 0;
        });
        for (var j = 0; j < rows.length; j++) { tb.appendChild(rows[j]); }
      }
      th.onclick = sort;
      th.onkeydown = function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); sort(); }
      };
    })(head.cells[c], c);
  }

  q.oninput = apply;
  br.onchange = apply;
  ev.onchange = apply;
  me.onchange = apply;
  var rst = document.getElementById('f-reset');
  if (rst) {
    rst.onclick = function () {
      q.value = ''; br.value = '*'; ev.value = '*'; me.checked = false; apply();
    };
  }
  apply();
})();
"""


def esc(value) -> str:
    return html.escape("" if value is None else str(value))


# --------------------------------------------------------------------------
# git_sha -> commit URL (Phase G increment 2)
#
# Derived once, at GENERATION time, from `git remote get-url origin`; the page
# itself never talks to the network. The resulting <a href> is an ordinary
# navigation link the reader may click — not a fetch, not a script source, not a
# stylesheet: the dashboard still renders completely offline.
# --------------------------------------------------------------------------
_SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")


def repo_url(explicit: str | None = None):
    """Base web URL of the origin remote (no trailing slash), or None."""
    if explicit:
        return explicit.rstrip("/") or None
    try:
        out = subprocess.run(["git", "-C", str(ROOT), "remote", "get-url", "origin"],
                             capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):       # pragma: no cover
        return None
    if out.returncode != 0:
        return None
    url = out.stdout.strip()
    if not url:
        return None
    if url.startswith("git@"):                          # git@host:owner/repo.git
        host, _, path = url[4:].partition(":")
        url = f"https://{host}/{path}"
    elif url.startswith("ssh://git@"):
        url = "https://" + url[len("ssh://git@"):]
    if not url.startswith("http"):                      # unknown scheme: no link
        return None
    return url[:-4].rstrip("/") if url.endswith(".git") else url.rstrip("/")


def commit_link(sha, base) -> str:
    """`sha` as a link to its commit page, or just the escaped sha."""
    text = esc(sha)
    if not base or not sha or not _SHA_RE.match(str(sha)):
        return text
    return (f'<a class="sha" href="{esc(base)}/commit/{text}" target="_blank" '
            f'rel="noopener noreferrer">{text}</a>')


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


# --------------------------------------------------------------------------
# Per-tier drill-down (Phase G increment 2)
#
# One <details> per tier: its own history, its own signals, its own sources.
# Plain HTML disclosure widgets — they work with JavaScript disabled, and a
# value that was never measured stays "—" rather than being back-filled.
# --------------------------------------------------------------------------
DRILL_HEADERS = {
    "pyuvm": ["rt cycles"],
    "fcov": ["bins", "fcov %"],
    "trace_compare": ["identical cycles"],
    "coverage": ["line %", "branch %"],
    "formal": ["jobs", "bmc depth", "per-job depth (measured only)"],
}


def num_td(value, text, *, raw=False) -> str:
    """A table cell whose sort key is `value` (empty when never measured)."""
    dv = "" if value is None else str(value)
    return f'<td data-v="{esc(dv)}">{text if raw else esc(text)}</td>'


def sig_cell(value, source, fmt="{}") -> str:
    """One signal, honest about where it came from."""
    if value is None:
        return '<span class="s-notrun">—</span>'
    txt = esc(fmt.format(value))
    if source == "estimated":
        return (f'<span class="s-est">{txt}*</span>'
                f'<span class="badge estimated">est</span>')
    return txt


def drill_cells(key: str, row: sqlite3.Row, jobs_by_run: dict) -> list:
    """Tier-specific signal cells for one row of the drill-down table."""
    if key == "pyuvm":
        return [sig_cell(get(row, "roundtrip_cycles"),
                         get(row, "roundtrip_cycles_source", "none"))]
    if key == "fcov":
        bins = (f"{row['fcov_bins_hit']}/{row['fcov_bins_total']}"
                if row["fcov_bins_total"] else None)
        return [sig_cell(bins, row["fcov_source"]),
                sig_cell(row["fcov_pct"], row["fcov_source"], "{:.1f}%")]
    if key == "trace_compare":
        return [sig_cell(row["trace_cycles"], row["trace_compare_source"])]
    if key == "coverage":
        return [sig_cell(row["coverage_line_pct"], row["coverage_source"], "{:.1f}%"),
                sig_cell(get(row, "coverage_branch_pct"),
                         get(row, "coverage_branch_source", "none"), "{:.1f}%")]
    if key == "formal":
        jobs = (f"{row['formal_jobs_passed']}/{row['formal_jobs_total']}"
                if row["formal_jobs_total"] else None)
        per = jobs_by_run.get(row["id"], [])
        per_txt = (", ".join(
            f'<code>{esc(j["job"])}</code> '
            f'≤{esc(j["depth"]) if j["depth"] is not None else "?"} '
            f'{esc(j["status"])}' for j in per)
            if per else '<span class="s-notrun">—</span>')
        return [sig_cell(jobs, row["formal_source"]),
                sig_cell(get(row, "formal_depth_max"),
                         get(row, "formal_depth_source", "none"), "≤{}"),
                per_txt]
    return []


def drilldowns(rows, jobs_by_run: dict, base_url) -> str:
    """A collapsible per-tier history for every tier."""
    out = []
    for key, name, desc in TIERS:
        extra = DRILL_HEADERS.get(key, [])
        measured = sum(1 for r in rows if r[f"{key}_source"] == "measured")
        est = sum(1 for r in rows if r[f"{key}_source"] == "estimated")
        latest_st = rows[0][f"{key}_status"]
        head = ("<tr><th>#</th><th>timestamp (UTC)</th><th>sha</th><th>branch</th>"
                "<th>env</th><th>status</th><th>source</th><th>secs</th>"
                + "".join(f"<th>{esc(h)}</th>" for h in extra) + "</tr>")
        body = []
        for r in rows:
            st, src = r[f"{key}_status"], r[f"{key}_source"]
            cls = "s-est" if src == "estimated" else f"s-{status_class(st)}"
            body.append(
                f'<tr><td>{r["id"]}</td><td class="mono">{esc(r["ts_utc"])}</td>'
                f'<td class="mono">{commit_link(r["git_sha"], base_url)}</td>'
                f'<td class="mono">{esc(r["git_branch"])}</td>'
                f'<td>{esc(r["env"])}</td>'
                f'<td class="{cls}">{esc(st)}{"*" if src == "estimated" else ""}</td>'
                f'<td><span class="badge {src}">{esc(src)}</span></td>'
                f'<td>{esc(fmt_secs(r[f"{key}_secs"]))}</td>'
                + "".join(f"<td>{c}</td>" for c in drill_cells(key, r, jobs_by_run))
                + "</tr>")
        summary = (f'{esc(name)} <span class="pill {status_class(latest_st)}">'
                   f'{esc(latest_st)}</span>'
                   f'<span class="sum">{esc(desc)} · {measured} measured'
                   + (f", {est} carried forward" if est else "")
                   + f' of {len(rows)} row(s)</span>')
        out.append(f'<details class="drill"><summary>{summary}</summary>'
                   f'<div class="body scroll"><table><thead>{head}</thead>'
                   f'<tbody>{"".join(body)}</tbody></table></div></details>')
    return "".join(out)


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


def render(rows, branch_rows, formal_jobs, db_path: Path,
           jobs_by_run=None, base_url=None) -> str:
    jobs_by_run = jobs_by_run or {}
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
            # data-v drives the inline sorter; the '*' stays visual only, so an
            # estimated row still sorts with its own status.
            cells.append(f'<td class="{cls}" data-v="{esc(st)}">{esc(st)}{mark}</td>')
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
               else '<span class="s-pass">0</span>' if nr == 0
               else f'<span class="s-fail">{nr}</span>')
        dirty = " <span class='badge estimated'>dirty</span>" if r["git_dirty"] else ""
        # Free-text filter haystack: what the reader can see on the row.
        hay = " ".join(str(x) for x in (
            r["id"], r["ts_utc"], r["git_sha"], r["git_branch"], r["env"],
            r["source"], "dirty" if r["git_dirty"] else "",
            *(f'{n}:{r[f"{k}_status"]}' for k, n, _ in TIERS),
        )).lower()
        body.append(
            f'<tr data-search="{esc(hay)}" data-branch="{esc(r["git_branch"])}" '
            f'data-env="{esc(r["env"])}" data-source="{esc(r["source"])}">'
            f'<td data-v="{r["id"]}">{r["id"]}</td>'
            f'<td class="mono">{esc(r["ts_utc"])}</td>'
            f'<td class="mono" data-v="{esc(r["git_sha"])}">'
            f'{commit_link(r["git_sha"], base_url)}{dirty}</td>'
            f'<td class="mono">{esc(r["git_branch"])}</td><td>{esc(r["env"])}</td>'
            f'<td data-v="{esc(r["source"])}">'
            f'<span class="badge {"estimated" if r["source"] != "measured" else "measured"}">'
            f'{esc(r["source"])}</span></td>'
            + "".join(cells)
            + num_td(r["coverage_line_pct"], cov)
            + num_td(get(r, "coverage_branch_pct"), covb)
            + num_td(r["fcov_pct"], fc)
            + num_td(r["formal_jobs_passed"] if r["formal_jobs_total"] else None, fm)
            + num_td(get(r, "formal_depth_max"), depth, raw=True)
            + num_td(get(r, "roundtrip_cycles"), rtc)
            + num_td(r["total_secs"], fmt_secs(r["total_secs"]))
            + num_td(get(r, "collect_peak_rss_mb"), rss)
            + num_td(nr, reg, raw=True)
            + '</tr>'
        )

    branches = sorted({r["git_branch"] for r in rows})
    envs = sorted({r["env"] for r in rows})
    toolbar = (
        '<div class="toolbar">'
        '<input type="text" id="f-text" placeholder="filter: sha, branch, env, status…" '
        'aria-label="filter runs">'
        '<label>branch <select id="f-branch"><option value="*">all</option>'
        + "".join(f'<option value="{esc(b)}">{esc(b)}</option>' for b in branches)
        + '</select></label>'
        '<label>env <select id="f-env"><option value="*">all</option>'
        + "".join(f'<option value="{esc(e)}">{esc(e)}</option>' for e in envs)
        + '</select></label>'
        '<label><input type="checkbox" id="f-measured"> measured rows only</label>'
        '<button type="button" id="f-reset">reset</button>'
        f'<span class="count" id="f-count">{len(rows)} of {len(rows)} run(s) shown</span>'
        '</div>'
    )
    drill = drilldowns(rows, jobs_by_run, base_url)

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
<p class="sub">Self-contained dashboard — CSS, JavaScript and SVG all inlined,
<b>no CDN and no external fetch</b> — generated by
<code>tools/metrics_dashboard.py</code> from <code>{esc(db_path.name)}</code> at
{esc(gen)}. Post-gate and advisory: nothing here runs, gates, or perturbs
<code>lint / pyuvm / fcov / uvm / trace-compare</code>.
{'The only outbound URLs are the <code>git_sha</code> commit links below: ordinary '
 '<code>&lt;a href&gt;</code> navigation you may click, never something the page loads.'
 if base_url else 'No commit links: no <code>origin</code> remote was resolvable at generation time.'}</p>

<h2>Latest run</h2>
<div class="card">
  <div class="meta">
    <div>run<b>#{latest["id"]}</b></div>
    <div>timestamp<b class="mono">{esc(latest["ts_utc"])}</b></div>
    <div>commit<b class="mono">{commit_link(latest["git_sha"], base_url)}{" (dirty)" if latest["git_dirty"] else ""}</b></div>
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
<div class="card">
<p class="nojs">Type to filter, or click any column heading to sort (click again
to reverse). Filtering and sorting are done by the inlined script below — with
JavaScript off the full table still renders, just unsorted and unfiltered.</p>
{toolbar}
<div class="scroll"><table id="hist"><thead>{head}</thead>
<tbody>{"".join(body)}</tbody></table></div>
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
<code>make dashboard</code>, or any gate. "—" = the row predates the check.<br>
<span class="badge measured">sha</span> the <code>git_sha</code> column links to
that commit{' on <code>' + esc(base_url) + '</code>' if base_url else ''} — a
plain navigation link, not a fetch.
</p></div>

<h2>Per-tier drill-down</h2>
<p class="sub">One collapsible panel per tier: its full history with its own
signals and its own <code>*_source</code> per row. A signal that was never
measured shows <span class="s-notrun">—</span>; a carried-forward one is starred
and badged <span class="badge estimated">est</span> — it is never back-filled
into a measured claim.</p>
{drill}

<footer>Phase F increment 4 + Phase G increments 1–2 — <code>make metrics</code>
appends a row (<code>--once-per-sha</code> makes that idempotent, so CI can
commit it back), <code>make dashboard</code> regenerates this file. Both are
additive and outside the gate. Store: <code>metrics/metrics.db</code> (schema:
<code>metrics/schema.sql</code>, <code>user_version = 2</code>).</footer>
</div>
<script>{JS}</script>
</body></html>
"""


# --------------------------------------------------------------------------
# Self-containment guard (Phase G increment 2)
#
# Everything that would make the browser LOAD something. Plain `<a href>`
# navigation (the commit links) is deliberately NOT on this list: clicking a
# link is the reader's choice, not the page fetching anything to render itself.
# The banner reports the count, so the "no CDN / no external fetch" claim in the
# docs is checkable rather than asserted.
# --------------------------------------------------------------------------
EXTERNAL_PATTERNS = (
    ("<script src=",    re.compile(r"<script[^>]*\ssrc\s*=", re.I)),
    ("<link ...>",      re.compile(r"<link\b", re.I)),
    ("@import",         re.compile(r"@import", re.I)),
    ("css url(...)",    re.compile(r"url\s*\(", re.I)),
    ("<img/iframe/object/embed",
     re.compile(r"<(?:img|iframe|object|embed)\b", re.I)),
    ("fetch()/XHR",     re.compile(r"\bfetch\s*\(|XMLHttpRequest|importScripts",
                                   re.I)),
    ("srcset",          re.compile(r"\bsrcset\s*=", re.I)),
)


def external_refs(page: str) -> list:
    """[(kind, count)] for every construct that would load an external asset."""
    return [(name, len(rx.findall(page)))
            for name, rx in EXTERNAL_PATTERNS if rx.search(page)]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", type=Path, default=DEFAULT_DB)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--limit", type=int, default=50,
                    help="most recent N rows to show (default 50)")
    ap.add_argument("--repo-url", default=None,
                    help="base web URL for git_sha -> commit links (default: "
                         "derived from `git remote get-url origin`; pass an "
                         "empty string to disable the links entirely)")
    args = ap.parse_args(argv)
    base_url = None if args.repo_url == "" else repo_url(args.repo_url)

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
    # Per-job depths for EVERY shown run, for the formal drill-down.
    jobs_by_run: dict = {}
    try:
        for j in conn.execute(
                "SELECT run_id, job, depth, status FROM formal_jobs ORDER BY job"):
            jobs_by_run.setdefault(j["run_id"], []).append(j)
    except sqlite3.Error:
        jobs_by_run = {}
    conn.close()

    page = render(rows, branch_rows, formal_jobs, args.db,
                  jobs_by_run=jobs_by_run, base_url=base_url)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(page, encoding="utf-8")
    try:
        shown = args.out.relative_to(ROOT)
    except ValueError:
        shown = args.out
    ext = external_refs(page)
    print(f"[DASH] wrote {shown} ({args.out.stat().st_size} bytes, "
          f"{len(rows)} of {total} row(s), self-contained: inline CSS/JS/SVG, "
          f"{len(ext)} external resource ref(s))")
    for kind, hits in ext:
        print(f"[DASH]   ! {hits} x {kind}")
    nreg = get(rows[0], "regressions")
    print(f"[DASH] trends: branch {rows[0]['git_branch']} "
          f"({len(branch_rows)} run(s)), inline SVG; regressions: "
          f"{'n/a (pre-v2 row)' if nreg is None else f'{nreg} (advisory)'}")
    print(f"[DASH] ux: filter+sort over {len(rows)} row(s), "
          f"{len(TIERS)} tier drill-down(s), commit links "
          f"{'-> ' + base_url if base_url else 'disabled (no origin remote)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
