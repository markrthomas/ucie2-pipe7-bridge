#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# wave_web.py — bundle a dumped waveform into ONE self-contained, offline,
# no-CDN HTML file you can open in a browser (Phase G increment 4).
#
# The maintainer's workflow is a Codespace / a browser — no desktop app, no X11,
# so `make wave` (GTKWave) is not reachable there. This target produces a single
# file under build/waves/ that renders the SAME dump increment 3 already writes:
#
#     make waves TEST=roundtrip      ->  build/waves/test_roundtrip.fst
#     make wave-web TEST=roundtrip   ->  build/waves/test_roundtrip.html
#
# There is NO second dump path. The FST is exactly the one the `-DWAVES` build
# produced; this tool only converts it to VCD (apt gtkwave's `fst2vcd`, already
# an increment-3 dependency), base64s it, and substitutes it plus a small JSON
# metadata blob into the committed viewer template
# `dv/waves/viewer/wave_viewer.html`.
#
# SELF-CONTAINED, and checked rather than asserted: the generated page is
# re-scanned for every construct that would make a browser load something
# (<script src>, <link>, @import, css url(), <img>/<iframe>/<object>/<embed>,
# fetch()/XMLHttpRequest/importScripts, srcset) and the count is printed in the
# [WAVES] banner. The scanner is imported from tools/metrics_dashboard.py so the
# two "single self-contained page" generators can never drift apart.
#
# DEV-ONLY and strictly OFF-GATE: no gate target, no CI job and no `metrics`
# tier runs this, and it never touches rtl/ or dv/ sources.
#
# Stdlib Python only. Toolchain: apt gtkwave (fst2vcd) + Verilator's FST writer
# — NOT OSS CAD Suite.
# -----------------------------------------------------------------------------
import argparse
import base64
import datetime
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

# Reused, deliberately: the layout reader from the increment-3 drift-guard and
# the external-resource scanner from the metrics dashboard. One implementation
# of each, so `make wave-check`, `make dashboard` and `make wave-web` all agree.
from wave_check import layout_paths, RANGE_RE          # noqa: E402
from metrics_dashboard import external_refs            # noqa: E402

VIEWER = Path("dv/waves/viewer/wave_viewer.html")


def fst_to_vcd(dump: Path, fst2vcd: str) -> str:
    """VCD text for `dump` — converted if it is an FST, read as-is if a VCD."""
    if dump.suffix.lower() == ".vcd":
        return dump.read_text(errors="replace")
    with tempfile.TemporaryDirectory() as td:
        vcd = Path(td) / "wave.vcd"
        proc = subprocess.run([fst2vcd, str(dump), "-o", str(vcd)],
                              capture_output=True, text=True)
        if proc.returncode != 0 or not vcd.exists():
            sys.exit(f"[WAVES] wave-web ERROR: {fst2vcd} failed on {dump}\n"
                     f"{proc.stderr.strip()}")
        return vcd.read_text(errors="replace")


def default_signals(layout: Path):
    """Bare net paths from a committed .gtkw, in layout order, de-duplicated.

    The curated GTKWave layout is already the maintainer's "these are the 50
    signals worth looking at" answer, so the browser bundle opens on the same
    view instead of an arbitrary first-N. Group/comment rows are not carried
    over (the viewer has no group concept); GTKWave bit ranges are stripped,
    because the viewer addresses a signal by path and knows its own width.
    """
    if layout is None or not layout.exists():
        return []
    seen, out = set(), []
    for _lineno, path in layout_paths(layout):
        m = RANGE_RE.match(path)
        bare = m.group(1) if m else path
        if bare not in seen:
            seen.add(bare)
            out.append(bare)
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Bundle an increment-3 waveform dump into ONE "
                    "self-contained, offline, no-CDN HTML file.")
    ap.add_argument("--test", default="roundtrip",
                    help="which dv/pyuvm test_<name>.py dump to bundle")
    ap.add_argument("--wave-dir", default="build/waves",
                    help="directory the increment-3 dumps live in")
    ap.add_argument("--layout-dir", default="dv/waves",
                    help="directory of committed .gtkw layouts (default view)")
    ap.add_argument("--viewer", default=str(VIEWER),
                    help="the vendored, committed viewer template")
    ap.add_argument("--out", default=None,
                    help="output HTML (default <wave-dir>/test_<test>.html)")
    ap.add_argument("--fst2vcd", default="fst2vcd",
                    help="gtkwave's fst2vcd (FST -> VCD, bundle time only)")
    ap.add_argument("--no-build", action="store_true",
                    help="never run `make waves`; fail if the dump is missing")
    ap.add_argument("--make-arg", action="append", default=[],
                    help="extra VAR=VALUE passed to `make waves` "
                         "(e.g. PYTHON3=$(command -v python3))")
    ap.add_argument("--max-mb", type=float, default=64.0,
                    help="refuse to inline a VCD larger than this (default 64)")
    args = ap.parse_args(argv)

    module = f"test_{args.test}"
    wave_dir = (REPO / args.wave_dir).resolve()
    dump = wave_dir / f"{module}.fst"
    out = Path(args.out).resolve() if args.out else wave_dir / f"{module}.html"

    # 1. The dump — increment 3's, rebuilt through increment 3's own target.
    if not dump.exists():
        if args.no_build:
            sys.exit(f"[WAVES] wave-web ERROR: {dump.relative_to(REPO)} is "
                     f"missing (--no-build, so it was not generated) — "
                     f"run: make waves TEST={args.test}")
        cmd = ["make", "waves", f"TEST={args.test}"] + args.make_arg
        print(f"[WAVES] wave-web: {dump.relative_to(REPO)} missing — "
              f"running: {' '.join(cmd)}")
        if subprocess.run(cmd, cwd=REPO).returncode != 0 or not dump.exists():
            sys.exit(f"[WAVES] wave-web ERROR: could not build {dump}")

    # 2. FST -> VCD (bundle time only; the browser never sees an FST).
    fst2vcd = shutil.which(args.fst2vcd)
    if fst2vcd is None and dump.suffix.lower() != ".vcd":
        sys.exit(f"[WAVES] wave-web ERROR: '{args.fst2vcd}' is not on PATH, so "
                 f"the FST cannot be converted for the browser — "
                 f"apt-get install -y gtkwave (NOT OSS CAD Suite)")
    vcd = fst_to_vcd(dump, fst2vcd)
    if len(vcd) > args.max_mb * 1024 * 1024:
        sys.exit(f"[WAVES] wave-web ERROR: the VCD is "
                 f"{len(vcd) / 1048576:.1f} MiB, over --max-mb={args.max_mb} — "
                 f"dump a shorter window or raise the limit "
                 f"(the whole point is ONE openable file)")

    # 3. The template + its three substitutions.
    viewer = (REPO / args.viewer).resolve()
    if not viewer.exists():
        sys.exit(f"[WAVES] wave-web ERROR: no viewer template at "
                 f"{args.viewer} — it is committed; did it get deleted?")
    page = viewer.read_text()

    layout = REPO / args.layout_dir / f"{args.test}.gtkw"
    if not layout.exists():
        layout = REPO / args.layout_dir / "default.gtkw"
    defaults = default_signals(layout)

    meta = {
        "test": args.test,
        "module": module,
        "dump": str(dump.relative_to(REPO)),
        "dumpBytes": dump.stat().st_size,
        "vcdBytes": len(vcd),
        "layout": str(layout.relative_to(REPO)) if defaults else "",
        "defaults": defaults,
        "generated": datetime.datetime.now(datetime.timezone.utc)
                             .strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    # `<` escaped so the JSON can never terminate the <script> that carries it.
    meta_js = json.dumps(meta).replace("<", "\\u003c")
    title = f"ucie2-pipe7-bridge waves — {module}"

    page = page.replace("@@WAVE_TITLE@@", title)
    page = page.replace("@@WAVE_META@@", meta_js)
    page = page.replace("@@WAVE_VCD_B64@@",
                        base64.b64encode(vcd.encode("utf-8")).decode("ascii"))

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(page)

    # 4. Prove the no-CDN claim on the artifact we just wrote, not on intent.
    refs = external_refs(page)
    nrefs = sum(c for _k, c in refs)
    detail = ", ".join(f"{k}={c}" for k, c in refs) or "none"

    print(f"[WAVES] wrote {out.relative_to(REPO)} ({out.stat().st_size} bytes) "
          f"— single self-contained file: inlined viewer + base64 VCD, "
          f"{nrefs} external resource ref(s) [{detail}]")
    print(f"[WAVES] source dump {dump.relative_to(REPO)} "
          f"({dump.stat().st_size} bytes, the -DWAVES FST from `make waves`) "
          f"-> {len(vcd)} bytes of VCD, {len(defaults)} default signal(s)"
          + (f" from {meta['layout']}" if defaults else ""))
    if nrefs:
        # Hard invariant, self-guarded: if the vendored viewer ever grows a CDN
        # link, a web font or a fetch(), this target fails instead of shipping a
        # page that silently needs the network.
        print(f"[WAVES] wave-web FAILED: {nrefs} external resource ref(s) in "
              f"{out.relative_to(REPO)} — the bundle must be openable offline")
        return 1
    print(f"[WAVES] open it in a browser — offline, no CDN, no external fetch: "
          f"file://{out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
