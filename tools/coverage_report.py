#!/usr/bin/env python3
"""Summarise a Verilator ``coverage.dat`` into an RTL line-coverage report.

Phase F increment 2 (see ``docs/phase_f_env_enhancements.md``). Consumes the
``--coverage-line`` datafile written by the directed round-trip run
(``make coverage``) and prints a per-file table plus the banner::

    [COV] line=NN.N%

Verilator's ``--coverage-line`` emits both ``v_line`` and ``v_branch`` points,
and one point *per instance* of a module. This tool reports **line** coverage
the usual way: points are merged by ``(file, line)`` and a line counts as
covered when any instance hit it. Branch points are summarised separately and
are NOT part of the ``[COV] line=`` number.

Only files under the RTL directory are scored (``--rtl-dir``), so testbench or
library code can never inflate the number.

The floor is **advisory** by default (report only, always exit 0). Pass
``--min NN`` to make it a hard gate once a baseline is agreed.
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict

# Verilator's coverage.dat record: C '<\x01key\x02value...>' <count>
FIELD_SEP = "\x01"
KV_SEP = "\x02"


def parse(dat_path):
    """Yield (fields_dict, count) for every coverage point in *dat_path*."""
    with open(dat_path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.startswith("C "):
                continue  # header / comment
            body = line[2:].strip()
            if not body.startswith("'"):
                continue
            end = body.rfind("'")
            if end <= 0:
                continue
            payload, tail = body[1:end], body[end + 1:].strip()
            try:
                count = int(tail)
            except ValueError:
                continue
            fields = {}
            for chunk in payload.split(FIELD_SEP):
                if KV_SEP in chunk:
                    key, val = chunk.split(KV_SEP, 1)
                    fields[key] = val
            yield fields, count


def collect(dat_path, rtl_dir):
    """Merge points by (file, line). Returns (line_map, branch_map)."""
    rtl_dir = os.path.abspath(rtl_dir)
    lines = defaultdict(int)     # (file, line) -> max hit count
    branches = defaultdict(int)
    for fields, count in parse(dat_path):
        page = fields.get("page", "")
        src = fields.get("f") or fields.get("filename")
        lineno = fields.get("l")
        if not src or not lineno:
            continue
        src = os.path.abspath(src)
        if os.path.commonpath([src, rtl_dir]) != rtl_dir:
            continue  # score RTL only
        try:
            key = (src, int(lineno))
        except ValueError:
            continue
        if page.startswith("v_line"):
            lines[key] = max(lines[key], count)
        elif page.startswith("v_branch"):
            branches[key] = max(branches[key], count)
    return lines, branches


def per_file(points):
    """(file -> (covered, total)) plus the overall (covered, total)."""
    tally = defaultdict(lambda: [0, 0])
    for (src, _lineno), count in points.items():
        tally[src][1] += 1
        if count > 0:
            tally[src][0] += 1
    covered = sum(v[0] for v in tally.values())
    total = sum(v[1] for v in tally.values())
    return tally, covered, total


def pct(covered, total):
    return 100.0 * covered / total if total else 0.0


def render(dat_path, rtl_dir, uncovered_limit):
    lines, branches = collect(dat_path, rtl_dir)
    tally, covered, total = per_file(lines)
    _, br_covered, br_total = per_file(branches)

    out = []
    out.append("Verilator line coverage — directed FDI round-trip (make coverage)")
    out.append(f"datafile: {dat_path}")
    out.append("")
    out.append(f"{'file':<34} {'covered':>8} {'total':>7} {'line%':>7}")
    out.append("-" * 59)
    for src in sorted(tally):
        cov, tot = tally[src]
        out.append(f"{os.path.basename(src):<34} {cov:>8} {tot:>7} {pct(cov, tot):>6.1f}%")
    out.append("-" * 59)
    out.append(f"{'TOTAL':<34} {covered:>8} {total:>7} {pct(covered, total):>6.1f}%")
    out.append("")
    out.append(f"branch points (informational, not gated): "
               f"{br_covered}/{br_total} = {pct(br_covered, br_total):.1f}%")

    uncovered = sorted(k for k, v in lines.items() if v == 0)
    if uncovered:
        out.append("")
        out.append(f"uncovered lines ({len(uncovered)}):")
        for src, lineno in uncovered[:uncovered_limit]:
            out.append(f"  {os.path.basename(src)}:{lineno}")
        if len(uncovered) > uncovered_limit:
            out.append(f"  ... {len(uncovered) - uncovered_limit} more")
    return "\n".join(out), covered, total


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("datafile", help="Verilator coverage.dat")
    ap.add_argument("--rtl-dir", default="rtl", help="only score sources under here")
    ap.add_argument("--report", help="also write the text report here")
    ap.add_argument("--min", type=float, default=None,
                    help="fail (exit 1) below this line%%; omit = advisory only")
    ap.add_argument("--uncovered-limit", type=int, default=40)
    args = ap.parse_args(argv)

    if not os.path.isfile(args.datafile):
        print(f"[COV] ERROR: no coverage datafile at {args.datafile}", file=sys.stderr)
        return 2

    text, covered, total = render(args.datafile, args.rtl_dir, args.uncovered_limit)
    if total == 0:
        print("[COV] ERROR: no RTL line-coverage points found "
              f"(rtl-dir={args.rtl_dir})", file=sys.stderr)
        return 2
    print(text)
    if args.report:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        print(f"\n[COV] report: {args.report}")

    value = pct(covered, total)
    print(f"[COV] line={value:.1f}% ({covered}/{total} RTL lines)")
    if args.min is None:
        print("[COV] floor: advisory (report only) — no threshold enforced")
        return 0
    if value + 1e-9 < args.min:
        print(f"[COV] FAIL: line={value:.1f}% < floor {args.min:.1f}%")
        return 1
    print(f"[COV] PASS: line={value:.1f}% >= floor {args.min:.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
