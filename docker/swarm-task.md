Implement **increment 1** of `docs/phase_g_env_enhancements.md` (metrics: capture
more + trends + regression flags), and nothing beyond it.

**Environment notes (read first):**
- You run on a GitHub runner that cloned ONLY this repo — build from the spec, not
  by copying any sibling repo (you do not have it).
- **Your GitHub token CANNOT write `.github/workflows/**`.** This increment needs
  no workflow change, so do not touch any workflow file.
- Metrics are **stdlib-only**: Python 3 `sqlite3` module. No `sqlite3` CLI, no pip
  package, NO CDN in the dashboard.

1. Read BOTH `docs/phase_g_env_enhancements.md` (Hard invariants + increment 1)
   and the existing increment-4 code — `metrics/schema.sql` (currently
   `user_version = 1`), `metrics/metrics.db`, `tools/metrics_collect.py`,
   `tools/metrics_dashboard.py` — in full. Honor the honesty rule already in the
   schema (`*_source` per tier: measured | estimated | none; never fabricate a
   number for a tier that did not run).
2. Build **increment 1 only** — extend, do not rewrite:
   - **Schema → `user_version = 2`** with a forward migration that preserves every
     existing row (add columns / a side table; `metrics_collect.py` migrates an
     old DB in place on first run). Add: coverage **branch %** (alongside the
     existing line %), per-job **formal BMC depth**, the round-trip **sim cycle
     count**, and the collect run's **wall-time + peak RAM** where cheaply
     available (e.g. `resource.getrusage`). Each new signal carries its own
     `*_source`.
   - **Trends**: compute per-metric history across rows of the same `git_branch`
     (coverage %, key tier durations, formal depth) and render an **inline-SVG**
     trend line you draw yourself — no chart library, no CDN — in
     `metrics/dashboard.html`.
   - **Regression flags**: compare each measured metric to the most recent prior
     **measured** row on the same branch; flag a regression (coverage dropped, a
     duration ballooned past a sensible threshold, a tier went pass→fail) with a
     dashboard badge and a `[METRICS] regressions: N` line from `make metrics`.
     **Advisory only** — it must never fail `make metrics`/`make dashboard` or any
     gate.
3. Additive only. Do NOT fold anything into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`/`formal`, do not touch
   RTL, the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`,
   `dv/pyuvm/test_roundtrip.py`), or the fixed clock/reset/stimulus schedule.
   `make metrics`/`make dashboard` stay post-gate and advisory.
4. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the
   RoundtripTest / 3-way cross-check PASS) yourself and confirm they are unchanged.
   Migrate the committed `metrics.db` to v2, run `make metrics` then `make
   dashboard`; confirm old rows survive, new signals populate for tiers that ran,
   trends + any regression badge render, and the dashboard stays self-contained
   (no CDN/external fetch). Capture the `[METRICS]`/dashboard banners.
5. Document it: `README.md` / `PLAN.md` / `docs` + `make help`; mark increment 1
   "LANDED" in `docs/phase_g_env_enhancements.md` with the real banners, like the
   Phase F increments. Keep measured-vs-estimated honest.
6. Branch `swarm/phaseG-metrics-trends`, commit (co-author + Claude-Session
   trailers), push, and open a PR titled for Phase G increment 1. A human merges.
   Increments 2-4 are separate later runs — do not start them.
7. Report: what you added (file:line), the schema-v2 migration, the
   `[METRICS]`/dashboard banners, the local `[lint]`/pyuvm banners (unchanged),
   and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 1; if it
would require perturbing the sacred gate or the trace emitters, report it instead
of guessing.
