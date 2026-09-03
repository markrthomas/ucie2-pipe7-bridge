Implement **increment 3** of `docs/phase_g_env_enhancements.md` (waves: FST
generation + GTKWave flow, sibling-style), and nothing beyond it.

**Environment notes (read first):**
- You run on a GitHub runner that cloned ONLY this repo — build from the spec, not
  by copying any sibling repo (you do not have it). The "sibling-style" flow is
  described in the increment; reproduce its shape, don't fetch it.
- **Your GitHub token CANNOT write `.github/workflows/**`.** If you want a
  `make wave-check` CI step, author it as a fenced YAML block in
  `docs/phase_g_env_enhancements.md` under a "### CI step — for maintainer to
  apply" heading. Touch no file under `.github/workflows/`. You MAY edit the
  `Dockerfile` and `.devcontainer/` directly to add apt `gtkwave`.
- **No OSS CAD Suite.** Waves use apt `gtkwave` (its `fst2vcd` for the drift-guard)
  and Verilator's own FST writer. Any browser viewer stays self-contained/no-CDN
  (that's increment 4 — do NOT start it here).

1. Read `docs/phase_g_env_enhancements.md` (Hard invariants + increment 3) in
   full, plus the current test flow you will add dumping to: `dv/pyuvm/`
   (`Makefile`, `test_roundtrip.py`) and, if you extend it, `dv/uvm/vlt/Makefile`.
   Understand exactly how the gate builds run so your wave path stays disjoint.
2. Build **increment 3 only** — ADDITIVE, off-gate, strictly opt-in:
   - **FST dumping compiled in ONLY under a dedicated `-DWAVES` (or `+WAVES`)
     define** that the wave targets set and nothing else does (e.g. a
     `dv/common/*_wave_dump.svh` and/or the cocotb `WAVES=1` path). The gate builds
     (`lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`) MUST stay wave-free,
     GTKWave-independent, and **byte-identical** — dumping must never perturb timing
     or the per-cycle trace.
   - **`make waves`** — dump the pyuvm round-trip FST (`TEST=<name>` for one test).
     **`make wave`** — dump + open in GTKWave with the matching
     `dv/waves/<key>.gtkw` layout, falling back to `dv/waves/default.gtkw`. Extend
     to the UVM env (`make waves-uvm`/`make wave-uvm`) **only if tractable** — say
     so honestly if you defer it.
   - **`dv/waves/`** holds one curated GTKWave layout per debug target — start with
     `dv/waves/default.gtkw`. Wave dumps themselves go to a build/`sim_build` dir
     and are git-ignored; commit only the curated `.gtkw` layout(s).
   - **`make wave-check`** — the drift-guard: resolve every net path in each
     committed `.gtkw` against that target's real dump hierarchy (via apt
     `gtkwave`'s `fst2vcd`) and FAIL naming any dead path. Dev-only; never on the
     gate. Skip cleanly (exit 0) where `gtkwave`/`fst2vcd` is absent.
   - **Infra:** add apt `gtkwave` to the `Dockerfile` and `.devcontainer/` (edit
     these directly). Any `make wave-check` CI step is optional + advisory —
     author it in the doc for the maintainer to apply (token limit). `[WAVES] …`
     banner from the wave targets.
3. Additive only. Do NOT fold anything into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`/`formal`/`metrics`, do
   not touch RTL, the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`,
   `dv/pyuvm/test_roundtrip.py` — beyond a strictly `-DWAVES`/`WAVES`-guarded dump
   hook that cannot run in the gate path), or the fixed clock/reset/stimulus
   schedule. Waveform dumping is OFF the gate.
4. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the
   RoundtripTest / 3-way cross-check PASS) and confirm they are **unchanged and
   equally fast** (prove the `-DWAVES` path did not leak into the gate). Run
   `make waves` and confirm an FST is produced; run `make wave-check` against the
   committed `dv/waves/default.gtkw` and confirm it passes (every net path
   resolves). Capture the `[WAVES]` banners. GTKWave GUI open is not runnable
   headless — say so; `wave-check` is the automatable proof.
5. Document it: `README.md` ("Waveform debugging") / `PLAN.md` / `docs` +
   `make help`; mark increment 3 "LANDED" in `docs/phase_g_env_enhancements.md`
   with the real banners (and any maintainer-apply CI block), like increments 1-2.
6. Branch `swarm/phaseG-waves-fst`, commit (co-author + Claude-Session trailers),
   push, and open a PR titled for Phase G increment 3. A human merges.
   Increment 4 (browser viewer) is a separate later run — do not start it.
7. Report: what you added (file:line), how `-DWAVES` keeps dumping off the gate,
   the `make waves`/`wave-check` `[WAVES]` banners, the local `[lint]`/pyuvm
   banners (unchanged), the Dockerfile/.devcontainer edits, any CI block authored
   in docs, and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 3; if it
would require perturbing the sacred gate or the trace emitters, report it instead
of guessing.
