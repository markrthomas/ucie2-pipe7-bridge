Implement **increment 2** of `docs/phase_g_env_enhancements.md` (metrics:
auto-commit rows from CI + richer dashboard UX), and nothing beyond it.

**Environment notes (read first):**
- You run on a GitHub runner that cloned ONLY this repo — build from the spec, not
  by copying any sibling repo (you do not have it).
- **Your GitHub token CANNOT write `.github/workflows/**`.** This increment's
  auto-commit half IS a workflow change, so you must NOT write it directly —
  author it as a fenced YAML block in `docs/phase_g_env_enhancements.md` under a
  "### CI step — for maintainer to apply" heading. Touch no file under
  `.github/workflows/`.
- Metrics are **stdlib-only**: Python 3 `sqlite3` module. No `sqlite3` CLI, no pip
  package, NO CDN in the dashboard.

1. Read BOTH `docs/phase_g_env_enhancements.md` (Hard invariants + increment 2)
   and the current metrics code — `metrics/schema.sql` (now `user_version = 2`
   after increment 1), `metrics/metrics.db`, `tools/metrics_collect.py`,
   `tools/metrics_dashboard.py` — in full. Honor the honesty rule already in the
   schema (`*_source` per tier: measured | estimated | none; never fabricate a
   number for a tier that did not run). Increment 1 (trends + regression flags) is
   LANDED — build ON it, do not rewrite or refold it.
2. Build **increment 2 only** — extend, do not rewrite:
   - **Auto-commit from CI (authored in docs, NOT applied):** design a **separate**
     workflow (or a guarded post-merge job) that, **on push to `main` only**, runs
     `make metrics` and commits the appended row + regenerated
     `metrics/dashboard.html` back to `main` with `[skip ci]`, using a
     `contents: write` token. It must NOT run on PR branches (never race a PR),
     must be its **own** job so it can never perturb the gate, and — because your
     token cannot write workflows — is delivered as a fenced YAML block in
     `docs/phase_g_env_enhancements.md` under "### CI step — for maintainer to
     apply", not committed under `.github/workflows/`. Make `make metrics` safe to
     run this way (idempotent append; no-op cleanly when nothing changed).
   - **Richer dashboard UX:** in the single self-contained **no-CDN**
     `metrics/dashboard.html` (generator `tools/metrics_dashboard.py`), add
     **filterable/sortable run history**, **per-tier drill-down**, and
     **`git_sha` → commit links** (GitHub commit URL). Measured vs
     estimated/carried-forward must stay **visually distinct**. All JS/CSS inlined;
     no external fetch.
3. Additive only. Do NOT fold anything into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`/`formal`, do not touch
   RTL, the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`,
   `dv/pyuvm/test_roundtrip.py`), or the fixed clock/reset/stimulus schedule.
   `make metrics`/`make dashboard` stay post-gate and advisory.
4. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the
   RoundtripTest / 3-way cross-check PASS) yourself and confirm they are unchanged.
   Run `make metrics` then `make dashboard`; confirm old rows survive, the enriched
   dashboard renders (filter/sort, drill-down, commit links) and stays
   self-contained (no CDN/external fetch), and the measured-vs-estimated distinction
   holds. Capture the `[METRICS]`/dashboard banners.
5. Document it: `README.md` / `PLAN.md` / `docs` + `make help`; mark increment 2
   "LANDED" in `docs/phase_g_env_enhancements.md` with the real banners and the
   maintainer-apply CI block, like the Phase F increments and increment 1. Keep
   measured-vs-estimated honest.
6. Branch `swarm/phaseG-metrics-autocommit`, commit (co-author + Claude-Session
   trailers), push, and open a PR titled for Phase G increment 2. A human merges.
   Increments 3-4 are separate later runs — do not start them.
7. Report: what you added (file:line), the auto-commit workflow you authored in
   docs (for the maintainer to apply), the dashboard UX additions, the
   `[METRICS]`/dashboard banners, the local `[lint]`/pyuvm banners (unchanged),
   and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 2; if it
would require perturbing the sacred gate or the trace emitters, report it instead
of guessing.
