#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# gen_eda_playground.py — bundle the DUT + SV UVM testbench into paste-ready
# EDA Playground files (Phase G increment 5).
#
# EDA Playground has no include search path for our dv/uvm/sv/ subdirs, so this
# concatenates the canonical rtl/ and dv/uvm/sv/ sources in the SAME order the
# vlt flow compiles them (dv/uvm/vlt/Makefile) and FLATTENS every project
# `include "<subdir>/<file>.sv"` in the UVM package inline. `include
# "uvm_macros.svh" is left untouched — EDA Playground's chosen UVM provides it.
#
# It writes three self-contained files under dv/uvm/eda_playground/:
#   design.sv                    all rtl/ (pkg first)                -> Design pane
#   testbench.sv                 sva + if + flattened uvm_pkg + tb   -> Testbench pane
#   ucie2_pipe7_bridge_top.sv    design ++ testbench                 -> single all-in-one
#
# Stdlib only. This is a PORTABILITY/DEMO artifact: it is NOT part of the sacred
# gate and cannot run tools/trace_compare.py — verify it by running in EDA
# Playground. `make eda-check` guards the committed copies against drift.
# -----------------------------------------------------------------------------
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RTL = REPO / "rtl"
SV = REPO / "dv" / "uvm" / "sv"
OUT = REPO / "dv" / "uvm" / "eda_playground"

RTL_PKG = "ucie2_pipe7_pkg.sv"
# Testbench compile order mirrors dv/uvm/vlt/Makefile SRCS (after the RTL).
TB_ORDER = ["ucie2_pipe7_sva.sv", "ucie2_pipe7_if.sv",
            "ucie2_pipe7_uvm_pkg.sv", "tb_ucie2_pipe7.sv"]

INCLUDE_RE = re.compile(r'^\s*`include\s+"([^"]+)"\s*$')


def rtl_sources():
    """rtl/ucie2_pipe7_pkg.sv first (declares the types), then the rest sorted."""
    pkg = RTL / RTL_PKG
    rest = sorted(p for p in RTL.glob("*.sv") if p.name != RTL_PKG)
    return [pkg] + rest


def flatten(path: Path, seen: set) -> str:
    """Return the file's text with project `include "<...>" lines replaced by the
    included file's (recursively flattened) text. A `include whose target is not
    a real file under dv/uvm/sv/ (e.g. uvm_macros.svh) is left verbatim."""
    out = []
    for line in path.read_text().splitlines():
        m = INCLUDE_RE.match(line)
        if m:
            target = (SV / m.group(1)).resolve()
            if target.is_file():
                if target in seen:
                    continue  # include-guard-free: never inline the same file twice
                seen.add(target)
                out.append(f"// ---- inlined from {target.relative_to(REPO)} ----")
                out.append(flatten(target, seen))
                continue
        out.append(line)
    return "\n".join(out)


def banner(panes: str) -> str:
    return (
        "// ============================================================================\n"
        "// GENERATED FILE — DO NOT EDIT.\n"
        "//   Source of truth: rtl/*.sv + dv/uvm/sv/*.  Regenerate: make eda-playground\n"
        f"//   EDA Playground: {panes}\n"
        "//   Settings: top = tb_ucie2_pipe7; pick a UVM-capable tool + a UVM version;\n"
        "//             run-option +UVM_NO_RELNOTES. Assertions need the tool's SVA\n"
        "//             support enabled (the bound ucie2_pipe7_sva checker).\n"
        "//   This is a PORTABILITY/DEMO bundle: NOT part of the sacred gate and it\n"
        "//   cannot run tools/trace_compare.py. Verify by running it in EDA Playground.\n"
        "// ============================================================================\n"
        "`timescale 1ns/1ps\n"
    )


def concat(paths, flatten_uvm: bool) -> str:
    """Concatenate files; the UVM package is flattened, others copied verbatim."""
    chunks = []
    for p in paths:
        header = f"\n// ==== {p.relative_to(REPO)} ====\n"
        if flatten_uvm and p.name == "ucie2_pipe7_uvm_pkg.sv":
            chunks.append(header + flatten(p, set()))
        else:
            chunks.append(header + p.read_text().rstrip("\n"))
    return "\n".join(chunks) + "\n"


def build():
    rtl = rtl_sources()
    tb = [SV / n for n in TB_ORDER]
    missing = [p for p in rtl + tb if not p.is_file()]
    if missing:
        sys.exit("gen_eda_playground: missing sources: " +
                 ", ".join(str(m) for m in missing))

    design_body = concat(rtl, flatten_uvm=False)
    tb_body = concat(tb, flatten_uvm=True)

    files = {
        "design.sv": banner("Design pane (paste here)") + design_body,
        "testbench.sv": banner("Testbench pane (paste here)") + tb_body,
        "ucie2_pipe7_bridge_top.sv":
            banner("single all-in-one file (design + testbench)")
            + design_body + tb_body,
    }
    # Sanity: no project include may survive the flatten in a testbench bundle.
    for name in ("testbench.sv", "ucie2_pipe7_bridge_top.sv"):
        leftover = [ln for ln in files[name].splitlines()
                    if INCLUDE_RE.match(ln)
                    and (SV / INCLUDE_RE.match(ln).group(1)).is_file()]
        if leftover:
            sys.exit(f"gen_eda_playground: un-flattened include in {name}: "
                     f"{leftover[0]!r}")
    return files


def main():
    ap = argparse.ArgumentParser(description="Generate EDA Playground bundle.")
    ap.add_argument("--out", default=str(OUT),
                    help="output directory (default: dv/uvm/eda_playground)")
    ap.add_argument("--check", action="store_true",
                    help="regenerate in memory and diff against the committed "
                         "files; exit 1 on any drift (writes nothing)")
    args = ap.parse_args()
    outdir = Path(args.out)
    files = build()

    if args.check:
        drift = []
        for name, text in files.items():
            cur = outdir / name
            if not cur.is_file() or cur.read_text() != text:
                drift.append(name)
        if drift:
            print("[EDA] DRIFT: committed bundle is stale for: "
                  + ", ".join(drift))
            print("[EDA] run `make eda-playground` and commit the result.")
            sys.exit(1)
        print(f"[EDA] up to date: {', '.join(files)}")
        return

    outdir.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (outdir / name).write_text(text)
    total = sum(len(t.splitlines()) for t in files.values())
    print(f"[EDA] wrote {len(files)} files ({total} lines) to "
          f"{outdir.relative_to(REPO) if outdir.is_relative_to(REPO) else outdir}")
    for name in files:
        print(f"[EDA]   {name}")


if __name__ == "__main__":
    main()
