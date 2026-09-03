#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# wave_check.py — GTKWave layout drift-guard (Phase G increment 3).
#
# A committed `dv/waves/*.gtkw` layout is a list of net paths into a waveform
# dump. Rename a signal, move it between modules or delete it, and the layout
# silently opens with rows missing — the classic way a "curated debug view" rots.
#
# This tool re-proves every committed layout against a REAL dump of its target:
#   1. figure out which dump each layout belongs to (the `[*] wave-check-target:`
#      directive, else the layout's own `[dumpfile]` line),
#   2. build that dump if it is not there yet (`make waves TEST=<key>`),
#   3. read the dump's true hierarchy with apt gtkwave's `fst2vcd`, and
#   4. FAIL, naming file:line and the dead path, if any net path in the layout
#      does not resolve.
#
# DEV-ONLY and strictly OFF-GATE: nothing in lint/pyuvm/fcov/uvm/trace-compare/
# coverage/formal/metrics runs this, and it never touches rtl/ or dv/ sources.
# Where gtkwave/fst2vcd is not installed it SKIPS with exit 0 rather than
# pretending to have checked something.
#
# Stdlib Python only. Toolchain: apt gtkwave (fst2vcd) + Verilator's FST writer
# — NOT OSS CAD Suite.
# -----------------------------------------------------------------------------
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# `[*] wave-check-target: <flow> <module>`  e.g. "pyuvm test_roundtrip"
TARGET_RE = re.compile(r"^\[\*\]\s*wave-check-target:\s*(\S+)\s+(\S+)\s*$")
DUMPFILE_RE = re.compile(r'^\[dumpfile\]\s*"([^"]*)"\s*$')
# A trailing GTKWave bit range, e.g. "foo[127:0]" or "foo[3]".
RANGE_RE = re.compile(r"^(.*?)(\[\d+(?::\d+)?\])$")
# Leading "(N)" on an expanded-bus bit row, and a leading "+{alias} ".
BITROW_RE = re.compile(r"^\(\d+\)")
ALIAS_RE = re.compile(r"^\+\{[^}]*\}\s*")


# ---- the dump's true hierarchy ----------------------------------------------
def fst_hierarchy(fst: Path, fst2vcd: str):
    """Return {net path -> set of range strings} for every $var in the dump.

    Paths are built the way GTKWave builds them: scope names joined with '.',
    with EMPTY scope names contributing nothing. cocotb's Verilator main
    constructs the model as `new Vtop("")`, so the root scope of these dumps is
    literally unnamed and a top-level port is just `pclk`, not `TOP.pclk`.
    A scalar contributes the empty range '' so a bare name still resolves.
    """
    with tempfile.TemporaryDirectory() as td:
        vcd = Path(td) / "hier.vcd"
        proc = subprocess.run([fst2vcd, str(fst), "-o", str(vcd)],
                              capture_output=True, text=True)
        if proc.returncode != 0 or not vcd.exists():
            sys.exit(f"[WAVES] wave-check ERROR: {fst2vcd} failed on {fst}\n"
                     f"{proc.stderr.strip()}")
        hier, scopes = {}, []
        for raw in vcd.read_text(errors="replace").splitlines():
            tok = raw.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                # "$scope module <name> $end"; an unnamed scope has no <name>.
                scopes.append(tok[2] if len(tok) > 3 else "")
            elif tok[0] == "$upscope":
                if scopes:
                    scopes.pop()
            elif tok[0] == "$var":
                # $var <type> <width> <id> <name> [<range>] $end
                name = tok[4]
                rng = tok[5] if tok[5] != "$end" else ""
                path = ".".join([s for s in scopes if s] + [name])
                hier.setdefault(path, set()).add(rng)
            elif tok[0] == "$enddefinitions":
                break
        return hier


# ---- the committed layout ---------------------------------------------------
def layout_paths(gtkw: Path):
    """Yield (lineno, net path) for every signal row in a GTKWave savefile.

    Skipped: `[...]` directives, `@hex` trace-attribute lines, `*` marker rows,
    `-` comment/blank rows and `#{...}` bundle headers. `(N)` expanded-bus bit
    rows and `+{alias}` prefixes are normalised away first.
    """
    for lineno, raw in enumerate(gtkw.read_text().splitlines(), start=1):
        line = raw.strip()
        if not line or line[0] in "[@*-#":
            continue
        line = ALIAS_RE.sub("", BITROW_RE.sub("", line)).strip()
        if line:
            yield lineno, line


def layout_target(gtkw: Path):
    """(flow, module) this layout is a view of, from its own header."""
    for raw in gtkw.read_text().splitlines():
        m = TARGET_RE.match(raw.strip())
        if m:
            return m.group(1), m.group(2)
        m = DUMPFILE_RE.match(raw.strip())
        if m and m.group(1):
            return "pyuvm", Path(m.group(1)).stem
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--layout-dir", default="dv/waves",
                    help="directory of committed .gtkw layouts")
    ap.add_argument("--wave-dir", default="build/waves",
                    help="directory the dumps are written to")
    ap.add_argument("--fst2vcd", default="fst2vcd",
                    help="gtkwave's fst2vcd (skip cleanly if absent)")
    ap.add_argument("--no-build", action="store_true",
                    help="never run `make waves`; fail if a dump is missing")
    ap.add_argument("--make-arg", action="append", default=[],
                    help="extra VAR=VALUE passed to `make waves` "
                         "(e.g. PYTHON3=$(command -v python3))")
    args = ap.parse_args()

    layout_dir = (REPO / args.layout_dir).resolve()
    wave_dir = (REPO / args.wave_dir).resolve()

    layouts = sorted(layout_dir.glob("*.gtkw"))
    if not layouts:
        print(f"[WAVES] wave-check: no layouts in {args.layout_dir} — nothing to check")
        return 0

    fst2vcd = shutil.which(args.fst2vcd)
    if fst2vcd is None:
        # Honest skip: without fst2vcd there is no hierarchy to resolve against,
        # and claiming a pass would be a lie. Never reds anything.
        print(f"[WAVES] wave-check SKIPPED: '{args.fst2vcd}' not on PATH "
              f"(apt-get install -y gtkwave) — {len(layouts)} layout(s) unchecked")
        return 0

    hier_cache, dead, checked = {}, [], 0
    for gtkw in layouts:
        rel = gtkw.relative_to(REPO)
        target = layout_target(gtkw)
        if target is None:
            dead.append(f"{rel}: no '[*] wave-check-target:' directive and no "
                        f"[dumpfile] line — cannot tell which dump this views")
            continue
        flow, module = target
        if flow != "pyuvm":
            print(f"[WAVES] wave-check: {rel} targets flow '{flow}', "
                  f"which this host cannot dump — skipped")
            continue

        fst = wave_dir / f"{module}.fst"
        if not fst.exists():
            if args.no_build:
                dead.append(f"{rel}: dump {fst.relative_to(REPO)} is missing "
                            f"(--no-build, so it was not generated)")
                continue
            test = module[len("test_"):] if module.startswith("test_") else module
            cmd = ["make", "waves", f"TEST={test}"] + args.make_arg
            print(f"[WAVES] wave-check: {fst.relative_to(REPO)} missing — "
                  f"running: {' '.join(cmd)}")
            if subprocess.run(cmd, cwd=REPO).returncode != 0 or not fst.exists():
                sys.exit(f"[WAVES] wave-check ERROR: could not build {fst}")

        if fst not in hier_cache:
            hier_cache[fst] = fst_hierarchy(fst, fst2vcd)
        hier = hier_cache[fst]

        for lineno, path in layout_paths(gtkw):
            checked += 1
            m = RANGE_RE.match(path)
            bare, rng = (m.group(1), m.group(2)) if m else (path, "")
            if bare not in hier:
                dead.append(f"{rel}:{lineno}: dead net path '{path}' — "
                            f"not in {fst.relative_to(REPO)}")
            elif rng and rng not in hier[bare] and "" not in hier[bare]:
                dead.append(f"{rel}:{lineno}: '{bare}' exists but its range "
                            f"{rng} does not — dump has "
                            f"{sorted(r for r in hier[bare] if r)}")

    if dead:
        for d in dead:
            print(f"[WAVES] {d}")
        print(f"[WAVES] wave-check FAILED: {len(dead)} dead path(s) in "
              f"{len(layouts)} layout(s) — re-curate them against a fresh "
              f"`make waves` dump")
        return 1

    print(f"[WAVES] wave-check: {len(layouts)} layout(s), {checked} net path(s), "
          f"{len(hier_cache)} dump(s) — every path resolves "
          f"(hierarchy read with {Path(fst2vcd).name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
