"""Shared FDI stimulus-vector generator (PLAN Phase C, item 10; PLAN §5).

The two testbenches must drive the *identical* flit sequence for the cycle-accurate
cross-check (tools/trace_compare.py) to be meaningful. This module is the single
source of truth for that sequence: it emits a ``$readmemh``-compatible ``.vec`` file
(one 128-bit FDI payload per line, 32 hex nibbles, no prefix) that BOTH the PyUVM
env (Python ``read_vec``) and the SV UVM TB (``$readmemh``) load, and it is also
importable so a test can get the same list in-process without a file.

Profiles:
  ramp    -- the deterministic directed sequence used by the B4 round-trip
             (payload[i] = (0x1000+i)<<64 | (0xABCD0000+i)). Kept bit-identical so
             switching the TBs onto the file changes no trace.
  random  -- seeded pseudo-random 128-bit payloads (reproducible via --seed).

Scope note: every generated flit is a *data* block (is_os = False). Driving
ordered-set blocks over FDI is FLAGGED (the FDI ingress forces is_os=0 until the
flit-type hook lands, crosscheck B.1), so OS vectors would not round-trip as OS.
The payload width is FDI_DW = 128 (frozen, Item 0).
"""
import argparse
import random

FDI_DW = 128
_MASK = (1 << FDI_DW) - 1
_NIB = FDI_DW // 4   # 32 hex nibbles per line


def ramp_flits(n):
    """The directed ramp: payload[i] = (0x1000+i)<<64 | (0xABCD0000+i)."""
    return [(((0x1000 + i) << 64) | (0xABCD0000 + i)) & _MASK for i in range(n)]


def random_flits(n, seed=0xC0FFEE):
    """Seeded pseudo-random 128-bit data payloads (reproducible)."""
    rng = random.Random(seed)
    return [rng.getrandbits(FDI_DW) for _ in range(n)]


def make_flits(profile, n, seed=0xC0FFEE):
    if profile == "ramp":
        return ramp_flits(n)
    if profile == "random":
        return random_flits(n, seed)
    raise ValueError(f"unknown profile {profile!r} (expected 'ramp' or 'random')")


def write_vec(path, flits):
    """Write flits as a $readmemh-compatible hex file (one 128b payload per line)."""
    with open(path, "w") as f:
        for v in flits:
            f.write(format(v & _MASK, "0{}x".format(_NIB)) + "\n")


def read_vec(path):
    """Read a .vec file back into a list of ints (inverse of write_vec)."""
    out = []
    with open(path) as f:
        for line in f:
            line = line.split("//", 1)[0].strip()
            if line:
                out.append(int(line, 16))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Generate shared FDI stimulus vectors.")
    ap.add_argument("--profile", choices=("ramp", "random"), default="ramp")
    ap.add_argument("--n", type=int, default=8, help="number of flits")
    ap.add_argument("--seed", type=lambda s: int(s, 0), default=0xC0FFEE)
    ap.add_argument("--out", default="fdi_flits.vec", help="output .vec path")
    args = ap.parse_args(argv)

    flits = make_flits(args.profile, args.n, args.seed)
    write_vec(args.out, flits)
    # Self-check: the file round-trips to the exact list.
    assert read_vec(args.out) == flits, "write_vec/read_vec round-trip mismatch"
    print(f"wrote {len(flits)} '{args.profile}' flits -> {args.out}")


if __name__ == "__main__":
    main()
