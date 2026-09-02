# Phase G — DV env enhancements II (swarm plan)

Successor to Phase F (`docs/phase_f_env_enhancements.md`, all four increments
landed). Two thrusts the maintainer asked for on 2026-09-02: **richer metrics
tracking** and **waveform generation + viewing**. Same house rules as Phase F —
**land one increment per PR** (a human merges), in order. Read the whole file,
then implement **only the increment named in your task** (default: increment 1).

## Hard invariants (do not violate)

- **The cycle-accurate cross-check is sacred.** `make lint`/`pyuvm`/`fcov`/`uvm`
  and the per-cycle trace stay **byte-identical** and equally fast. Every new tier
  is **additive**, behind its own `make` target, and **outside** the existing gate
  — never fold it into `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`/
  `formal`/`metrics`/`dashboard`, never change the trace emitters
  (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`, `dv/pyuvm/test_roundtrip.py`) or the fixed
  clock/reset/stimulus schedule.
- **Waveform dumping is strictly opt-in and off-gate.** FST/VCD dumping is
  compiled in **only** under a dedicated `-DWAVES` (or `+WAVES`) define that the
  wave targets set and nothing else does. The gate builds must stay wave-free and
  GTKWave-independent — dumping must never perturb timing or the byte-identical
  trace. Wave artifacts live under `dv/waves/` (layouts) and a build/`sim_build`
  dir (dumps), and are git-ignored except curated layout files.
- **No OSS CAD Suite** in the reproducible envs (`.devcontainer`, `Dockerfile*`,
  CI). Waves use **apt `gtkwave`** (its `fst2vcd` for the drift-guard) and
  Verilator's own FST writer; the browser viewer is **self-contained, no CDN, no
  external fetch**. Metrics stay **stdlib-only** (Python `sqlite3`, no CLI/pip).
- **Swarm realities** (proven across Phase F): you run on a GitHub runner that
  cloned **only this repo** (no sibling to copy). **Your GitHub token cannot write
  `.github/workflows/**`** — author any workflow/CI change as a fenced block in
  this doc under a "### CI step — for maintainer to apply" heading; the maintainer
  applies it over HTTPS. Pinned-tool paths, `[BANNER]` style, `Co-Authored-By` +
  `Claude-Session` trailers, **never commit on `main`** — branch
  `swarm/phaseG-<slug>`, push incrementally, open a PR (draft early). CI validates.

## Increment 1 — metrics: capture more + trends + regression flags

Extend the increment-4 store (`metrics/schema.sql` at `user_version = 1`,
`tools/metrics_collect.py`, `tools/metrics_dashboard.py`). Bump the schema to
`user_version = 2` with a forward migration (existing rows preserved):
- **Capture more signals** (honesty rule intact — `*_source` per signal, never
  fabricate a number for a tier that did not run): coverage **branch %** (not just
  line), per-job **formal BMC depth**, the round-trip **sim cycle count**, and
  collect **wall-time + peak RAM** of the collect run where cheaply available.
- **Trends**: the collector/dashboard compute per-metric history across rows for
  the same branch (coverage %, tier durations, formal depth) and render an
  inline-SVG trend line (drawn yourself — no chart lib, no CDN).
- **Regression flags**: compare each measured metric to the most recent prior
  **measured** row on the same branch; flag a regression (coverage dropped, a
  duration ballooned past a threshold, a tier went pass→fail) with a badge in the
  dashboard and a `[METRICS] regressions: N` line. Advisory — never reds a gate.
Docs + `make help`. `make metrics`/`make dashboard` stay post-gate + advisory.

## Increment 2 — metrics: auto-commit rows from CI + richer dashboard UX

- **Auto-commit from CI** (deliberately out of scope in inc4): a **separate**
  workflow (or a guarded post-merge step) that, on push to `main` only, runs
  `make metrics` and commits the appended row + regenerated dashboard back to
  `main` with `[skip ci]`, using a `contents:write` token — so the committed store
  grows automatically. It must NOT run on PR branches (no racing the PR), must be
  its own job so it can never perturb the gate, and (workflows-token limit) is
  **authored in this doc for the maintainer to apply**.
- **Richer dashboard UX**: filterable/sortable run history, per-tier drill-down,
  and `git_sha` → commit links, all still in the single self-contained no-CDN
  `metrics/dashboard.html`. Measured vs estimated/carried-forward stays visually
  distinct.

## Increment 3 — waves: FST generation + GTKWave flow (sibling-style)

Port the sibling's dev-only wave flow, adapted to this repo (no oss-cad-suite):
- FST dumping under `-DWAVES`, compiled **only** into the wave targets (a
  `dv/common/*_wave_dump.svh` or the cocotb `WAVES=1` path) — the gate builds are
  untouched and stay byte-identical.
- `make waves` (dump the pyuvm round-trip FST; `TEST=<name>` for one test) and
  `make wave` (dump + open in GTKWave with the matching `dv/waves/<key>.gtkw`
  layout, falling back to `dv/waves/default.gtkw`). Extend to the UVM env
  (`make waves-uvm`/`wave-uvm`) if tractable.
- `dv/waves/` holds one curated GTKWave layout per debug target (start with
  `default.gtkw`).
- `make wave-check` — the drift-guard: resolve every net path in each committed
  `.gtkw` against that target's real dump hierarchy (via apt `gtkwave`'s
  `fst2vcd`) and FAIL naming any dead path. Dev-only; never on the gate.
- Infra (author CI in docs; apply Dockerfile yourself): apt `gtkwave` in the
  `Dockerfile` + `.devcontainer`; a `make wave-check` CI step is optional and
  advisory. `[WAVES] …` banner.

## Increment 4 — waves: self-contained browser viewer

A committed, **self-contained** waveform viewer so an FST/VCD opens in a
Codespace/browser with no desktop app or X11 (your browser-centric workflow):
- `make wave-web [TEST=<name>]` bundles a dumped wave + a **no-CDN**, all-inlined
  HTML/JS (or WASM) viewer into a single openable file under `build/waves/`
  (e.g. a vendored Surfer WASM build, or a small vcd.js viewer — vendor the assets
  into the repo, never fetch at runtime). It must render offline by opening the
  file. Reuse the same `-DWAVES` dumps from increment 3 — do not add a second
  dump path or perturb the gate.
- Docs (`README` "Waveform debugging", `PLAN.md`) + `make help`. If a full WASM
  viewer is too heavy for one increment, ship a smaller self-contained VCD viewer
  and say so honestly.

## Acceptance (every increment)

`make lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare` byte-identical green, unchanged
timings; the new target(s) work and are documented (`README`/`PLAN.md`/`docs` +
`make help`); wave dumping stays behind `-DWAVES` and off the gate; one PR, CI
green, a human merges.
