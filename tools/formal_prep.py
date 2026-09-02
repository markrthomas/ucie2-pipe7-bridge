#!/usr/bin/env python3
"""formal_prep.py -- make an RTL source readable by the apt `yosys` Verilog frontend.

WHY THIS EXISTS
---------------
The formal tier (Phase F increment 3, `make formal`) drives SymbiYosys, which reads
the RTL with yosys' own Verilog/SystemVerilog frontend. That frontend (yosys 0.33,
the Ubuntu apt package -- we deliberately do NOT use OSS CAD Suite) does not accept
a wildcard package import:

    module pipe7_mac_ctrl_fsm
        import ucie2_pipe7_pkg::*;          <-- syntax error in yosys 0.33
    #(...) (...);

It *does* accept explicitly scoped package references (`ucie2_pipe7_pkg::BLOCK_BITS`,
`ucie2_pipe7_pkg::ctrl_req_e`, `ucie2_pipe7_pkg::PD_P0`, ...).

The same frontend also rejects `return <expr>;` inside a function (it wants the
`<funcname> = <expr>;` form) and an unsized `int'(...)` cast.

So, for the proof only, this script emits a mechanically-transformed COPY of the
source into the formal work dir:
  1. the `import <pkg>::*;` header line is removed;
  2. every identifier declared by that package is rewritten to `<pkg>::<id>`;
  3. `return <expr>;` inside a function becomes `<funcname> = <expr>;`;
  4. `int'(x)` becomes the equivalent sized cast `32'(x)`.

This is a purely lexical, behaviour-preserving rewrite of a build artefact. The RTL
in `rtl/` is NEVER modified, and nothing in the sacred gate (lint / pyuvm / fcov /
uvm / trace-compare) reads the transformed copy -- it lives under `build/formal/`.

Usage:
    formal_prep.py --pkg rtl/ucie2_pipe7_pkg.sv --outdir build/formal/src FILE.sv...
"""

import argparse
import os
import re
import sys

# Package-scope declarations we need to qualify: parameters, typedef'd type names,
# and enum member names.
_PARAM_RE = re.compile(r"^\s*(?:localparam|parameter)\b[^;]*?\b([A-Za-z_]\w*)\s*=", re.M)
_TYPEDEF_RE = re.compile(r"\}\s*([A-Za-z_]\w*)\s*;")
_ENUM_RE = re.compile(r"typedef\s+enum\b[^{]*\{(.*?)\}", re.S)


def package_symbols(pkg_src):
    """Return (package_name, sorted list of identifiers declared at package scope)."""
    m = re.search(r"\bpackage\s+([A-Za-z_]\w*)\s*;", pkg_src)
    if not m:
        raise SystemExit("formal_prep: no `package <name>;` found in the package source")
    pkg = m.group(1)

    # Strip comments so commented-out declarations do not leak into the symbol set.
    body = re.sub(r"//[^\n]*", "", pkg_src)
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)

    syms = set()
    for line in _PARAM_RE.finditer(body):
        syms.add(line.group(1))
    for td in _TYPEDEF_RE.finditer(body):
        syms.add(td.group(1))
    for en in _ENUM_RE.finditer(body):
        for member in en.group(1).split(","):
            mm = re.match(r"\s*([A-Za-z_]\w*)", member)
            if mm:
                syms.add(mm.group(1))
    syms.discard(pkg)
    # Longest first so a prefix name can never shadow a longer one.
    return pkg, sorted(syms, key=lambda s: (-len(s), s))


_FUNC_RE = re.compile(r"function\s+automatic\s+[^;]*?\b(\w+)\s*\(.*?endfunction", re.S)


def _return_to_assign(m):
    """yosys 0.33 has no `return` in functions -- use the `<name> = expr;` form."""
    return re.sub(r"\breturn\s+", m.group(1) + " = ", m.group(0))


def transform(src, pkg, syms):
    # 1. Drop the wildcard import (module-header or file-scope form).
    src, n_import = re.subn(r"^[ \t]*import\s+%s::\*\s*;[ \t]*\n" % re.escape(pkg), "", src, flags=re.M)
    # 2. Qualify every package identifier that is not already qualified.
    pattern = re.compile(r"(?<![\w:])(%s)\b" % "|".join(re.escape(s) for s in syms))
    src = pattern.sub(lambda m: "%s::%s" % (pkg, m.group(1)), src)
    # 3. `return expr;` -> `<funcname> = expr;` (unsupported by the yosys frontend).
    src = _FUNC_RE.sub(_return_to_assign, src)
    # 4. `int'(x)` -> `32'(x)` (the yosys frontend takes only sized casts).
    src = src.replace("int'(", "32'(")
    return src, n_import


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pkg", required=True, help="package source (read verbatim, also copied)")
    ap.add_argument("--outdir", required=True)
    ap.add_argument("sources", nargs="+")
    args = ap.parse_args(argv)

    with open(args.pkg) as fh:
        pkg_src = fh.read()
    pkg, syms = package_symbols(pkg_src)

    os.makedirs(args.outdir, exist_ok=True)
    # The package itself parses fine as-is.
    with open(os.path.join(args.outdir, os.path.basename(args.pkg)), "w") as fh:
        fh.write(pkg_src)

    for path in args.sources:
        if os.path.abspath(path) == os.path.abspath(args.pkg):
            continue  # already copied verbatim above; must not be self-qualified
        with open(path) as fh:
            src = fh.read()
        out, n_import = transform(src, pkg, syms)
        if n_import == 0 and ("%s::" % pkg) not in out:
            print("formal_prep: WARNING: %s uses neither `import %s::*` nor %s::"
                  % (path, pkg, pkg), file=sys.stderr)
        with open(os.path.join(args.outdir, os.path.basename(path)), "w") as fh:
            fh.write(out)

    print("[formal_prep] %d source(s) -> %s (package %s, %d symbols qualified)"
          % (len(args.sources) + 1, args.outdir, pkg, len(syms)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
