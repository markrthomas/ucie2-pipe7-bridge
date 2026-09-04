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


def _framing_model():
    """Import the shared framing model (single source of truth) with a path shim,
    so `python gen_vectors.py` works standalone (no PYTHONPATH needed)."""
    import os
    import sys
    models = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")
    if models not in sys.path:
        sys.path.insert(0, models)
    import framing_model as fm
    return fm


def frame_words(flits, width=80):
    """Serialize data flits into the block-aligned PIPE word stream (width-bit words)
    via the shared framing model -- the SAME words the DUT framer emits. Used for the
    B2B 'external PCIe' config, whose SV UVM tier has no framer and must $readmemh a
    pre-framed word vector; the PyUVM tier reads the identical file."""
    fm = _framing_model()
    return fm.frame_stream([(d, False) for d in flits], width)


def write_words(path, words, width=80):
    """Write PIPE words as a $readmemh-compatible hex file (one width-bit word/line)."""
    nib = (width + 3) // 4
    with open(path, "w") as f:
        for w in words:
            f.write(format(w & ((1 << width) - 1), "0{}x".format(nib)) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Generate shared FDI stimulus vectors.")
    ap.add_argument("--profile", choices=("ramp", "random"), default="ramp")
    ap.add_argument("--n", type=int, default=8, help="number of flits")
    ap.add_argument("--seed", type=lambda s: int(s, 0), default=0xC0FFEE)
    ap.add_argument("--out", default="fdi_flits.vec", help="output .vec path")
    ap.add_argument("--words-out", default=None,
                    help="also emit the block-aligned PIPE word stream (for the B2B "
                         "external-PCIe config; framed via the shared model)")
    ap.add_argument("--pipe-width", type=int, default=80,
                    help="PIPE word width for --words-out (default 80)")
    args = ap.parse_args(argv)

    flits = make_flits(args.profile, args.n, args.seed)
    write_vec(args.out, flits)
    # Self-check: the file round-trips to the exact list.
    assert read_vec(args.out) == flits, "write_vec/read_vec round-trip mismatch"
    print(f"wrote {len(flits)} '{args.profile}' flits -> {args.out}")

    if args.words_out:
        words = frame_words(flits, args.pipe_width)
        write_words(args.words_out, words, args.pipe_width)
        # Self-check: the words deframe back to exactly the driven flits.
        fm = _framing_model()
        got = [d for (d, _o, _s) in fm.deframe_stream(words, args.pipe_width, len(flits))]
        assert got == flits, "frame/deframe round-trip mismatch"
        print(f"wrote {len(words)} {args.pipe_width}b PIPE words -> {args.words_out}")


if __name__ == "__main__":
    main()
