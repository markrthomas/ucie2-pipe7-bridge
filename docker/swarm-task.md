Implement **increment 4** of `docs/phase_f_env_enhancements.md` (metrics +
dashboard), and nothing beyond it. This is the LAST Phase F increment.

**Environment notes (read first):**
- You run on a GitHub runner that has cloned ONLY this repo. You do NOT have the
  sibling `axi-on-ucie-to-mem` repo — build the feature from the spec below, not
  by copying sibling files.
- **Your GitHub token CANNOT write `.github/workflows/**`** (it lacks `workflows`
  scope — a push that touches a workflow file is rejected). So do NOT edit any
  workflow. Instead AUTHOR the post-gate CI step as a fenced YAML block in
  `docs/phase_f_env_enhancements.md` under an "### CI step — for maintainer to
  apply" heading (exactly like increment 3 did); the maintainer applies it over
  HTTPS afterward.
- Only stdlib is guaranteed: use Python 3 with its built-in `sqlite3` module. Do
  NOT rely on the `sqlite3` CLI or any pip package, and NO CDN anywhere.

1. Read `docs/phase_f_env_enhancements.md` in full — honor its Hard invariants
   (the byte-identical cross-check is sacred; new tiers are additive, behind their
   own make target, OUTSIDE the existing gate; never touch the trace emitters or
   the fixed clock/reset/stimulus schedule) — then build **increment 4 only**: a
   committed metrics store + a self-contained dashboard.
2. Build these:
   - `metrics/schema.sql` — a small SQLite schema. One row per `make metrics` run
     with: ISO-8601 UTC timestamp, git short-sha, git branch, and per-tier result
     columns for the tiers this repo actually has — `lint`, `pyuvm`, `fcov`, `uvm`,
     `trace-compare`, `coverage` (the `[COV] line=NN.N%` number), `formal` (jobs
     passed / total). Store each tier's pass/fail and, where available, its
     duration. Keep a `source` column so **measured** rows (a tier actually ran
     this invocation) are never conflated with **estimated/carried-forward** values
     (mark those explicitly); do not fabricate a measurement for a tier that did
     not run.
   - `metrics/metrics.db` — the committed SQLite file, initialized from the schema
     with at least one real measured row from this environment.
   - `tools/metrics_collect.py` — parses the tier banners/outputs already produced
     by the gate (`[lint] RTL OK`, the pyuvm PASS line, `[FCOV] bins=…`, `[COV]
     line=…`, the `[FORMAL] … PASSED` lines) and appends one row. It must be
     robust to a tier being absent (record it as not-run, not as fail).
   - `tools/metrics_dashboard.py` — regenerates `metrics/dashboard.html` from
     `metrics.db`: a **single self-contained** HTML file, all CSS/JS INLINED, NO
     CDN / no external fetch, showing the latest row prominently plus the history
     (a simple table and/or an inline-SVG sparkline you draw yourself — no chart
     library). It must render offline by double-clicking the file.
   - `make metrics` (collect a row) and `make dashboard` (regen the HTML) targets,
     plus `make help` lines. Neither is part of the gate.
3. Additive only. These targets MUST NOT be folded into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`/`formal`, must not touch
   RTL, the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`,
   `dv/pyuvm/test_roundtrip.py`), or the fixed clock/reset/stimulus schedule.
4. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the
   RoundtripTest / 3-way cross-check PASS) yourself and confirm they are unchanged.
   Run `make metrics` then `make dashboard`; confirm a row is appended and
   `metrics/dashboard.html` regenerates and opens standalone. Capture the banners.
5. Author (do NOT apply) the post-gate CI step in
   `docs/phase_f_env_enhancements.md`: a step at the END of
   `.github/workflows/uvm-verilator.yml` (after the coverage steps) that runs
   `make metrics` and uploads `metrics/dashboard.html` as an artifact — advisory
   (`continue-on-error: true`), strictly post-gate, never inside a timed DV run.
6. Document it: `README.md` / `PLAN.md` / `docs` + the `make help` lines; mark
   increment 4 "LANDED" in `docs/phase_f_env_enhancements.md` with the real
   banners, like increments 1-3. Note measured-vs-estimated handling honestly.
7. Branch `swarm/phaseF-metrics`, commit (co-author + Claude-Session trailers),
   push, and open a PR titled for increment 4. A human merges. This is the last
   increment — do not start anything beyond it.
8. Report: what you added (file:line), the `make metrics`/`make dashboard`
   banners, the local `[lint]`/pyuvm banners (unchanged), and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 4; if it
would require perturbing the sacred gate, the trace emitters, or a workflow file
your token cannot write, report it (author it in docs) instead of guessing.
