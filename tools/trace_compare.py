#!/usr/bin/env python3
"""Cycle-accurate cross-check: diff the PyUVM per-cycle trace against the SV UVM
per-cycle trace (PLAN Section 5).

Both testbenches emit one CSV line per PCLK using the shared column order in
dv/common/models/trace_format.py. This tool fails on:
  - a header mismatch (the two envs disagree on columns), or
  - the FIRST cycle where any observable column differs, or
  - a length mismatch (one env ran more cycles than the other).

Exit 0 = the two environments track cycle-for-cycle. Non-zero = divergence, with
the offending cycle and column reported.
"""
import argparse
import sys


def load(path):
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f if ln.strip()]
    if not lines:
        sys.exit(f"trace_compare: {path} is empty")
    return lines[0], lines[1:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pyuvm", required=True, help="PyUVM trace CSV")
    ap.add_argument("--uvm", required=True, help="SV UVM trace CSV")
    args = ap.parse_args()

    p_hdr, p_rows = load(args.pyuvm)
    u_hdr, u_rows = load(args.uvm)

    if p_hdr != u_hdr:
        print("HEADER MISMATCH", file=sys.stderr)
        print(f"  pyuvm: {p_hdr}", file=sys.stderr)
        print(f"  uvm  : {u_hdr}", file=sys.stderr)
        return 2
    cols = p_hdr.split(",")

    n = min(len(p_rows), len(u_rows))
    for i in range(n):
        pc = p_rows[i].split(",")
        uc = u_rows[i].split(",")
        if pc != uc:
            diffs = [
                f"{cols[j]}: pyuvm={pc[j]} uvm={uc[j]}"
                for j in range(min(len(pc), len(uc)))
                if pc[j] != uc[j]
            ]
            print(f"DIVERGENCE at cycle {i}:", file=sys.stderr)
            for d in diffs:
                print(f"  {d}", file=sys.stderr)
            return 1

    if len(p_rows) != len(u_rows):
        print(
            f"LENGTH MISMATCH: pyuvm={len(p_rows)} cycles, uvm={len(u_rows)} cycles "
            f"(matched first {n})",
            file=sys.stderr,
        )
        return 1

    print(f"trace_compare: OK — {len(p_rows)} cycles identical across both TBs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
