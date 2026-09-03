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

## Increment 1 — metrics: capture more + trends + regression flags — **LANDED**

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

### What landed

- **`metrics/schema.sql` → `PRAGMA user_version = 2`.** Ten new `runs` columns
  plus a `formal_jobs` side table (`run_id, job, depth, status, source`) and a
  `runs (git_branch, id)` index. `tools/metrics_collect.py:migrate()` brings an
  existing store up in place — `PRAGMA table_info(runs)`, then
  `ALTER TABLE runs ADD COLUMN` for whatever is missing, then the unchanged
  `CREATE … IF NOT EXISTS` script. Idempotent, and a no-op on a fresh DB.
  **Every existing row is preserved**; the new columns come up `NULL`/`'none'`,
  which is the honest reading of "that row never measured this".
- **Four new signals, each with its own `*_source`** (`measured` | `estimated` |
  `none`), so a number is never implied by its tier's roll-up:
  - `coverage_branch_pct` — `tools/coverage_report.py` gained a
    `[COV] branch=NN.N%` banner. It already *computed* branch points and printed
    them in prose; the banner just makes them parseable. Reported **alongside**
    the gated `[COV] line=` number, never folded into it, and omitted entirely
    (rather than printed as `0%`) when the datafile carries no branch points.
  - `formal_depth_max` + the `formal_jobs` rows — parsed from the **existing**
    `[FORMAL] <job>: BMC depth N PASSED` lines; `tools/formal_run.sh` is
    unchanged. Per-job rows are written for measured runs only, so a depth can
    never be attributed to a job that did not run (carry-forward copies only the
    `formal_depth_max` roll-up, tagged `estimated`).
  - `roundtrip_cycles` — counted **read-only** from the per-cycle trace the
    `pyuvm` tier just wrote (`dv/pyuvm/build/bridge.trace`, rows minus header).
    `dv/pyuvm/test_roundtrip.py` and the fixed clock/reset/stimulus schedule are
    untouched. Distinct from `trace_cycles` (what `trace-compare` diffed across
    **both** TBs). Only recorded when the tier ran in this invocation — a stale
    trace from an older checkout is never reported as this commit's measurement.
  - `collect_peak_rss_mb` + `collect_source` — `resource.getrusage` `ru_maxrss`,
    `max(self, heaviest child)`. Collect **wall time** is the pre-existing
    `total_secs` (no duplicate column was added for it).
- **Trends** (`tools/metrics_dashboard.py`): the chart row now follows the
  latest row's **`git_branch` only** — a feature branch is never silently
  compared against `main` — and plots **measured points only**, so a
  carried-forward value leaves a gap instead of faking a data point. Ten
  sparklines (line/branch/functional coverage, formal BMC depth, round-trip
  cycles, `lint`/`pyuvm`/`fcov` runtimes, collect wall time, peak RSS), all
  hand-drawn inline `<svg>` polylines: **no chart library, no CDN, no
  `<script>`** — verified by grepping the generated HTML for `http`, `<script`,
  `src=`, `@import` and `url(` (zero hits).
- **Regression flags** (`tools/metrics_collect.py:detect_regressions`): each
  measured signal is compared with the most recent prior row on the same branch
  that measured *that same signal*. Flags on pass→fail, a
  coverage/BMC-depth/cycle-count drop, or a runtime that **both** at least
  doubled **and** grew ≥ 5 s (so a 0.09 s → 0.20 s `lint` blip is never
  reported). The count and notes are stored on the row (`regressions`,
  `regression_notes`), printed as `[METRICS] regressions: N`, and badged in the
  dashboard. **Advisory:** the whole check is exception-guarded, the exit status
  is untouched, and no gate reads it. A pre-v2 row renders `—` / "regressions
  n/a" rather than a fabricated `0`.
- Fixed a latent crash in `sparkline()`'s empty-series path (`%`-formatting
  choked on the literal `width="100%"`), which the new charts made reachable —
  it now renders "no measured data yet" for a signal a branch never measured.
- Docs: `README.md` ("Metrics + dashboard" → new "Schema v2" section, coverage
  section, quick start, repo map), `PLAN.md` item **G1**, and `make help`.

Nothing was folded into the gate: `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/
`coverage`/`formal` are byte-for-byte unchanged in behaviour, no RTL or trace
emitter was touched, and no workflow file was edited (none was needed).

**LANDED banners (local, GitHub runner: apt Verilator 5.020, Icarus 12,
yosys 0.33 + sby 0.68 + z3 4.8.12):**

```
[lint] RTL OK
** test_roundtrip.RoundtripTest   PASS         410.00           0.06       7352.66  **
** TESTS=1 PASS=1 FAIL=0 SKIP=0                410.00           0.09       4621.96  **
[SB] driven=8 recovered=8 stream_words=13 model_words=13
[SB] integrated-bridge cross-check PASS (3-way agreement)
[FCOV] bins=39/39 = 100.0%  tool=cocotb_coverage
[COV] line=63.3% (38/60 RTL lines)
[COV] branch=75.6% (34/45 RTL branch points, informational — not gated)
[METRICS] schema migrated v1 -> v2: +10 column(s), 1 existing row(s) preserved
[METRICS] lint=pass  pyuvm=pass  fcov=pass  uvm=not-run  trace-compare=not-run  coverage=pass  formal=pass
[METRICS] signals: cov-branch=75.6%  formal-depth<=24 (3 job(s))  roundtrip-cycles=200  peak-rss=132MiB  wall=31.9s
[METRICS] regressions: 0
[METRICS] row #3 appended to metrics/metrics.db (3 row(s), source=measured, sha=b577055, 2026-09-02T21:43:21Z)
[DASH] wrote metrics/dashboard.html (16307 bytes, 3 of 3 row(s), self-contained: no CDN/JS/external fetch)
[DASH] trends: branch swarm/phaseG-metrics-trends (2 run(s)), inline SVG; regressions: 0 (advisory)
```

`uvm` and `trace-compare` are honestly `not-run` here — they need the
from-source UVM Verilator, which this host does not have; CI/Railway measure
them. The regression comparator was additionally exercised against a
deliberately-degraded copy of the store and produced all seven flag kinds
(`pyuvm: pass -> fail`, `coverage: runtime 2.4s -> 39.4s (>=2x)`,
`coverage line% 63.3 -> 55.0`, `coverage branch% 75.6 -> 60.0`,
`fcov% 100.0 -> 92.3`, `formal BMC depth 24 -> 12`,
`round-trip cycles 200 -> 100`) — on a throwaway DB, never the committed one.

### CI step — none needed

Increment 1 changes no workflow: the existing post-gate `continue-on-error`
metrics step (authored in `docs/phase_f_env_enhancements.md` increment 4) picks
up the new signals, the migration and the regression line for free, because they
ride the same `make metrics` / `make dashboard` invocations.

## Increment 2 — metrics: auto-commit rows from CI + richer dashboard UX — **LANDED**

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

### What landed

**1. `make metrics` is now safe to auto-commit — `tools/metrics_collect.py`.**

- New `--once-per-sha` flag (off by default). Before **any** tier runs, the
  collector asks the store whether this exact `(git_sha, env)` pair already has a
  row *that was written from a clean tree*. If so it runs nothing, appends
  nothing, prints `[METRICS] up to date: …` and exits 0. A workflow re-run is
  therefore a free no-op instead of a duplicate row, and the commit step that
  follows finds nothing to commit. Off by default, so a maintainer running
  `make metrics` twice locally still gets two honest rows.
- The clean-tree condition is deliberate: a row collected with uncommitted
  changes (`git_dirty = 1`) does **not** describe that commit, so it can never
  stand in for a clean measurement of it — the collector falls through and
  measures for real. (Rows #1–#3 in the committed store are exactly such dirty
  rows; row #4 is the first clean one.)
- Best-effort and read-only: an absent or unreadable store just means "not
  recorded yet".

**2. Richer dashboard UX — `tools/metrics_dashboard.py`.** Still **one**
self-contained file:

- **Filterable + sortable run history.** A toolbar (free-text filter over the
  visible row text, plus `branch` / `env` selects, a *measured rows only*
  checkbox and a reset button) and click-to-sort on **every** column, driven by a
  dependency-free ES5 snippet inlined in a `<script>` block. Sorting is by a
  per-cell `data-v` sort key, so `63.3%` sorts numerically and a never-measured
  `—` sorts as empty rather than as a fabricated `0`. With JavaScript disabled
  the whole table still renders — just unsorted and unfiltered.
- **Per-tier drill-down.** One `<details>` panel per tier (plain HTML, no JS)
  with that tier's own history: status, `*_source` badge, duration and its own
  signals — round-trip cycles for `pyuvm`, bins + `fcov %`, identical cycles for
  `trace-compare`, line % + branch % for `coverage`, and jobs + BMC depth +
  **per-job depths** (from the `formal_jobs` side table) for `formal`.
- **`git_sha` → commit links.** Resolved **once, at generation time**, from
  `git remote get-url origin` (`--repo-url` overrides, `--repo-url ''` disables);
  `git@…:owner/repo.git` is normalized to `https://…/owner/repo`. These are plain
  `<a href>` navigation links the reader may click — not a fetch, not a script
  source, not a stylesheet. The page still renders completely offline.
- **Measured vs estimated stays visually distinct** everywhere it appears: the
  `*` marker and `s-est` colour on the status cell, the `estimated` row badge, an
  `est` badge beside every carried-forward signal in the drill-down, and `—` for
  anything never measured.
- **The no-CDN claim is now checked, not asserted.** `external_refs()` re-scans
  the generated HTML for every construct that would make the browser *load*
  something (`<script src>`, `<link>`, `@import`, `url(...)`, `<img>/<iframe>/
  <object>/<embed>`, `fetch()`/`XMLHttpRequest`/`importScripts`, `srcset`) and
  the banner prints the count — measured at **0**.
- The old banner said "no CDN/**JS**/external fetch". That is no longer true and
  was corrected rather than left standing: there is now exactly **one** inlined
  `<script>` block. No CDN and no external fetch remain true and are verified.

Nothing was folded into the gate: `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/
`coverage`/`formal` are unchanged, no RTL, testbench, trace emitter or
clock/reset/stimulus schedule was touched, and no file under
`.github/workflows/` was edited (see the maintainer block below).

**LANDED banners (local, GitHub runner: apt Verilator 5.020, Icarus 12,
cocotb 1.9.2 + pyuvm 4.0.1 + cocotb_coverage 1.2.0, yosys 0.33 + sby 0.68 + z3):**

```
[lint] RTL OK
** test_roundtrip.RoundtripTest   PASS         410.00           0.06       7026.25  **
** TESTS=1 PASS=1 FAIL=0 SKIP=0                410.00           0.09       4555.38  **
[SB] driven=8 recovered=8 stream_words=13 model_words=13
[SB] integrated-bridge cross-check PASS (3-way agreement)
[METRICS] lint=pass  pyuvm=pass  fcov=pass  uvm=not-run  trace-compare=not-run  coverage=pass  formal=pass
[METRICS] signals: cov-branch=75.6%  formal-depth<=24 (3 job(s))  roundtrip-cycles=200  peak-rss=253MiB  wall=54.9s
[METRICS] regressions: 0
[METRICS] row #4 appended to metrics/metrics.db (4 row(s), source=measured, sha=b647b69, 2026-09-03T05:41:07Z)
[DASH] wrote metrics/dashboard.html (39398 bytes, 4 of 4 row(s), self-contained: inline CSS/JS/SVG, 0 external resource ref(s))
[DASH] trends: branch swarm/phaseG-metrics-autocommit (1 run(s)), inline SVG; regressions: 0 (advisory)
[DASH] ux: filter+sort over 4 row(s), 7 tier drill-down(s), commit links -> https://github.com/markrthomas/ucie2-pipe7-bridge
```

Idempotency, proven on a clean tree at that same sha (throwaway copy of the DB,
never the committed one) — instant, no tier ran:

```
[METRICS] up to date: sha b647b69 (env=ci) already recorded as row #4 (2026-09-03T05:41:07Z) — nothing run, nothing appended
```

`uvm` and `trace-compare` are honestly `not-run` here and in the auto-commit job
below — both need the from-source UVM Verilator, which neither host has; CI's
`uvm-verilator.yml` measures them. All three pre-existing rows survived (4 rows
total, schema already at `user_version = 2`, so no migration line was printed).
The inlined filter/sort script was additionally exercised head-less against a DOM
stub (`node --check` plus a scripted run): free-text filter, branch/env/measured
filters, reset, and ascending/descending numeric + text sort all behave, and a
never-measured `—` sorts as empty. The carried-forward rendering was re-checked
by generating a dashboard from a **throwaway** carry-forward store.

### CI step — APPLIED (`.github/workflows/metrics-autocommit.yml`)

The swarm's token cannot write `.github/workflows/**`, so this was authored here
and **applied by the maintainer over HTTPS** (the block below is the source of
truth for that committed file). It is a **new, separate workflow file**,
`.github/workflows/metrics-autocommit.yml` — not a step bolted onto `ci.yml` or
`uvm-verilator.yml`:

- **`push` to `main` only.** No `pull_request` trigger at all, so it can never
  race a PR branch, and `if: github.repository == …` keeps forks out.
- **Its own workflow, its own job.** It shares nothing with the gate jobs, runs
  in its own runner, and is `continue-on-error` — a metrics hiccup can never red
  `lint` / `uvm-verilator`, and nothing it does is visible to them.
- **`concurrency`** serializes runs so two pushes never fight over
  `metrics/metrics.db`.
- **`permissions: contents: write`** on that job alone (the workflow default is
  `read`), used only to push the two `metrics/` files.
- **`[skip ci]`** in the auto-commit message, so the commit it makes does not
  re-trigger any workflow (including itself). Note the consequence, honestly: the
  resulting commit on `main` touches only `metrics/metrics.db` +
  `metrics/dashboard.html` and is deliberately **not** re-gated.
- **`--once-per-sha`** makes a workflow re-run a clean no-op, and the commit step
  additionally checks `git diff --quiet` before committing anything.
- Tier honesty: this job carries only the **light** toolchain (apt Verilator +
  Icarus + pinned cocotb/pyuvm/cocotb_coverage + yosys/sby/z3), so it measures
  `lint,pyuvm,fcov,coverage,formal`. `uvm` and `trace-compare` need the
  from-source UVM Verilator and are recorded **`not-run`, never `fail`** — no
  number is invented for them, and `--carry-forward` is deliberately NOT used.
- The `--make-arg PYTHON3=…` is the documented GitHub-runner workaround
  (Verilator's `verilated.mk` hardcodes `/usr/bin/python3`, which is a different
  interpreter from the one cocotb runs on).

```yaml
name: DV metrics auto-commit

# Phase G increment 2. ADDITIVE, POST-GATE, ADVISORY. This workflow is entirely
# separate from `lint` (ci.yml) and `uvm-verilator` (uvm-verilator.yml): it
# shares no job with them, runs after the fact on the pushed commit, and cannot
# perturb the byte-identical per-cycle cross-check. It runs `make metrics` +
# `make dashboard` (both outside the gate by construction) and commits the
# appended row + regenerated dashboard back to `main`, so the committed store
# grows on its own instead of only when a maintainer remembers to run it.
#
# `main` ONLY -- there is deliberately no `pull_request` trigger, so this can
# never race a PR branch or write to one.

on:
  push:
    branches: [ main ]

# Never let two pushes fight over metrics/metrics.db. Queue, don't cancel: a
# cancelled run would just skip a row, but a cancelled PUSH would lose it.
concurrency:
  group: dv-metrics-autocommit
  cancel-in-progress: false

permissions:
  contents: read

jobs:
  metrics-autocommit:
    runs-on: ubuntu-latest
    # Own repo only (not forks), and never react to the commit we ourselves
    # push. `[skip ci]` already prevents that trigger; this is belt and braces.
    if: >-
      github.repository == 'markrthomas/ucie2-pipe7-bridge' &&
      !contains(github.event.head_commit.message, '[skip ci]')
    # ADVISORY: a metrics hiccup must never show up as a red check on `main`.
    continue-on-error: true
    permissions:
      contents: write          # the only elevated scope, used only to push
    steps:
      # Check out the BRANCH (not the detached pushed sha) so we can commit back.
      - uses: actions/checkout@v5
        with:
          ref: ${{ github.ref_name }}
          fetch-depth: 0
          persist-credentials: true

      # Light toolchain only -- NOT OSS CAD Suite, and deliberately NOT the
      # from-source UVM Verilator: this job measures the cheap tiers. `uvm` and
      # `trace-compare` are recorded 'not-run' (never 'fail', never guessed);
      # uvm-verilator.yml is what measures them.
      - name: Install the light DV toolchain (apt + pinned pip)
        run: |
          set -euo pipefail
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            verilator iverilog yosys z3
          python3 -m pip install --upgrade pip
          python3 -m pip install \
            "cocotb==1.9.2" "cocotb_coverage==1.2.0" "pyuvm==4.0.1" click
          git clone --depth 1 https://github.com/YosysHQ/sby /tmp/sby
          sudo make -C /tmp/sby install
          rm -rf /tmp/sby

      # Idempotent: --once-per-sha runs nothing and appends nothing when this
      # (sha, env) already has a row from a clean tree, so re-running this
      # workflow is a free no-op rather than a duplicate row.
      - name: Collect the DV metrics row + regenerate the dashboard
        run: |
          set -euo pipefail
          make metrics \
            METRICS_TIERS=lint,pyuvm,fcov,coverage,formal \
            METRICS_ARGS="--env ci --once-per-sha \
              --note auto-commit-from-push-to-main \
              --make-arg PYTHON3=$(command -v python3)"
          make dashboard

      # Commit ONLY the two metrics/ files, and only if they actually changed.
      # `[skip ci]` keeps this commit from re-triggering any workflow.
      - name: Commit the row + dashboard back to main
        run: |
          set -euo pipefail
          if git diff --quiet -- metrics/metrics.db metrics/dashboard.html; then
            echo "[METRICS-CI] nothing changed -- no commit, no push"
            exit 0
          fi
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add -- metrics/metrics.db metrics/dashboard.html
          git commit \
            -m "metrics: auto-append DV row for ${GITHUB_SHA:0:7} [skip ci]" \
            -m "Appended by .github/workflows/metrics-autocommit.yml (Phase G increment 2). Post-gate and advisory; only metrics/ changes." \
            -m "Tiers this job cannot run (uvm, trace-compare need the from-source UVM Verilator) are recorded 'not-run', never 'fail' -- no number is invented for them."
          for attempt in 1 2 3; do
            if git pull --rebase --autostash origin "$GITHUB_REF_NAME" \
               && git push origin "HEAD:$GITHUB_REF_NAME"; then
              echo "[METRICS-CI] pushed the metrics row to $GITHUB_REF_NAME"
              exit 0
            fi
            echo "[METRICS-CI] push attempt $attempt failed, retrying"
            sleep $((5 * attempt))
          done
          echo "[METRICS-CI] could not push after 3 attempts (advisory, not fatal)"

      - name: Upload the metrics dashboard
        if: always()
        continue-on-error: true
        uses: actions/upload-artifact@v4
        with:
          name: dv-metrics-dashboard-main
          path: |
            metrics/dashboard.html
            metrics/metrics.db
          retention-days: 14
          if-no-files-found: ignore
```

The existing post-gate metrics step in `uvm-verilator.yml` (Phase F increment 4)
is **left exactly as it is** — it still uploads its row as an artifact and does
not commit. That one measures `uvm` + `trace-compare` for real on PRs; this new
workflow is the one that grows the committed store on `main`.

## Increment 3 — waves: FST generation + GTKWave flow (sibling-style) — **LANDED**

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

### What landed

**0. First, a wave leak was found IN the gate and removed.**
`dv/pyuvm/Makefile` had `EXTRA_ARGS += --trace --timing -Wno-fatal` for
Verilator. cocotb appends `EXTRA_ARGS` to **both** the verilate command **and**
the simulation command (see `Makefile.verilator`: the run rule is
`$< $(SIM_ARGS) $(EXTRA_ARGS) $(PLUSARGS)`), and cocotb's `verilator.cpp` main
switches tracing on when it sees `--trace` in `argv`. So every `make pyuvm` /
`make fcov FCOV_SIM=verilator` / `make coverage` compiled the VCD tracer in
(`-DVM_TRACE=1 -DVM_TRACE_VCD=1`) and wrote a ~170 KB `dv/pyuvm/dump.vcd`. That
is exactly what this increment's hard invariant forbids ("the gate builds must
stay wave-free"), so `--trace` was dropped from that unconditional line. The gate
now builds `-DVM_TRACE=0 -DVM_TRACE_FST=0 -DVM_TRACE_VCD=0`, writes no dump, and
got slightly **faster** (clean `make pyuvm`: 15.7 s → 12.5 s on this runner;
sim ratio 7350 → 7749 ns/s). The per-cycle trace is **byte-identical** —
`dv/pyuvm/build/bridge.trace` has md5 `c1b8a30cc2e822e5efe7e5e103cc9b12` before
and after, and also from the `WAVES=1` run.

**1. Opt-in FST dumping — `dv/pyuvm/Makefile` `ifeq ($(WAVES),1)`.**
The one place dumping is compiled in, set by nothing but the three wave targets:

```make
ifeq ($(WAVES),1)
    SIM_BUILD    := $(abspath wave_build)
    COMPILE_ARGS += -DWAVES --trace-fst --trace-structs
    SIM_ARGS     += --trace --trace-file $(WAVE_FILE)
endif
```

Four independent reasons this cannot reach the gate:
- `WAVES` is only ever set by `make waves`/`wave`/`wave-check`; no gate target,
  no CI step and no `metrics` tier passes it.
- `-DWAVES --trace-fst --trace-structs` go in `COMPILE_ARGS` and
  `--trace --trace-file` in `SIM_ARGS` — the two variables cocotb does **not**
  share between the verilate and the run command. The mistake that caused the
  leak above is structurally not repeatable.
- `SIM_BUILD` is redirected to `dv/pyuvm/wave_build/`, so the gate's own
  `sim_build/` objects are never replaced by instrumented ones (the same
  separation `RTL_COVERAGE=1` already uses for `cov_build/`).
- Verified by the tier run, not asserted: a gate build's `Vtop.mk` carries
  `VM_TRACE=0` and links no `verilated_vcd_c`/`verilated_fst_c` object, and
  `find . -name '*.vcd' -o -name '*.fst'` after `make lint && make pyuvm &&
  make fcov` returns nothing.

`-DWAVES` is a real Verilator `` `define `` (not just decoration) — it is the
name the deferred SV UVM `$dumpfile` hook will key off, so there is exactly one
switch for the whole project.

**2. `make waves` / `make wave` / `make wave-check` (repo-root `Makefile`).**
`TEST=<name>` selects `dv/pyuvm/test_<name>.py` (default `roundtrip`); dumps go
to `build/waves/test_<name>.fst`. `make wave` opens the dump in GTKWave with
`dv/waves/<TEST>.gtkw` if that exists, else `dv/waves/default.gtkw`
(`gtkwave --save=<layout> <fst>`), and prints a clear message instead of a
stack trace when `gtkwave` is not on PATH. `make clean` removes `build/waves`;
`make -C dv/pyuvm clean` removes `wave_build/` and any stray `dump.vcd`/
`dump.fst`.

**3. `dv/waves/default.gtkw` — curated, and authored BY GTKWave.**
50 net paths in 10 labelled groups, following the round-trip end to end: clocks
+ reset, FDI TX, FDI RX, the link FSM (incl. `ucie2_pipe7_bridge.link.state_q`),
ingress → 128b block, Gen5 framer → PIPE TX, PIPE RX → deframer (`rfill`,
`pl_cnt`, `block_locked`, `sync_error`), egress → flit, PIPE MAC control + PHY
status, and bridge status. It was generated by driving GTKWave itself headless
(`xvfb-run -a gtkwave -a <out>.gtkw -S <tcl> <fst>` with
`addSignalsFromList` + `/File/Write_Save_File`), so every path string is
*exactly* what GTKWave resolves rather than something hand-guessed; the
machine-specific `[dumpfile_mtime]`/`[dumpfile_size]` lines were stripped and the
paths made repo-relative. Re-loading the committed file in GTKWave yields
`LOADED_TRACES 60` (50 signals + 10 group rows) — i.e. the layout genuinely
opens, which the GUI-less `wave-check` alone would not prove.

**4. `make wave-check` — `tools/wave_check.py` (stdlib, ~190 lines).**
For each committed layout: read its `[*] wave-check-target: <flow> <module>`
directive (falling back to its own `[dumpfile]` line), build that dump with
`make waves TEST=<key>` if it is missing, dump the **real** hierarchy with apt
GTKWave's `fst2vcd`, and resolve every signal row. It fails with `file:line` and
the offending path, and distinguishes a *dead* path from one whose **bit range**
moved. Rows that are not net paths (`[...]` directives, `@hex` attributes, `*`
markers, `-` comment/group rows, `#{...}` bundles) are skipped; `(N)` expanded-bit
prefixes and `+{alias}` prefixes are normalised away.

One subtlety worth recording: cocotb's Verilator main constructs the model as
`new Vtop("")`, so these dumps have an **unnamed root scope** — a top-level port
is `pclk`, not `TOP.pclk`, and DUT internals are
`ucie2_pipe7_bridge.<inst>.<net>`. The checker builds paths the same way (empty
scope names contribute nothing), which is why it and GTKWave agree.

**Dev-only, and honest when it cannot check.** No gate target, no CI job and no
`metrics` tier invokes it; with `fst2vcd` absent it prints
`wave-check SKIPPED: … N layout(s) unchecked` and exits **0** rather than
claiming a pass.

**5. Infra.** apt `gtkwave` added to `Dockerfile.dev` (the image
`.devcontainer/devcontainer.json` builds — that JSON has no package list of its
own and was left untouched) and to the root `Dockerfile`'s runtime stage, where
only the CLI `fst2vcd` half is used and the fail-fast toolchain check gained
`command -v fst2vcd`. Still apt, still **not** OSS CAD Suite. `.gitignore` gains
`build/waves/` and `dv/pyuvm/wave_build/`; `dv/waves/*.gtkw` stays committed.

Nothing was folded into the gate: no RTL, no trace emitter
(`dv/pyuvm/test_roundtrip.py`, `dv/uvm/sv/**`) and no clock/reset/stimulus
schedule was touched — the only DV-side edit is the `WAVES`-guarded block plus
the removal of the leaking `--trace`, and no file under `.github/workflows/` was
edited.

**LANDED banners (local, GitHub runner: apt Verilator 5.020, Icarus 12,
cocotb 1.9.2 + pyuvm 4.0.1 + cocotb_coverage 1.2.0, apt gtkwave 3.3.116):**

```
[lint] RTL OK
** test_roundtrip.RoundtripTest   PASS         410.00           0.05       7749.54  **
** TESTS=1 PASS=1 FAIL=0 SKIP=0                410.00           0.08       4874.26  **
[SB] driven=8 recovered=8 stream_words=13 model_words=13
[SB] integrated-bridge cross-check PASS (3-way agreement)
[FCOV] bins=39/39 = 100.0%  tool=cocotb_coverage
[WAVES] wrote build/waves/test_roundtrip.fst (9597 bytes) from dv/pyuvm MODULE=test_roundtrip (Verilator FST, -DWAVES build)
[WAVES] open with: make wave TEST=roundtrip   layout: dv/waves/default.gtkw
[WAVES] wave-check: 1 layout(s), 50 net path(s), 1 dump(s) — every path resolves (hierarchy read with fst2vcd)
```

The drift-guard's three other paths were exercised for real, not assumed. Dead
path + moved range (injected into a throwaway copy of the layout, then reverted):

```
[WAVES] dv/waves/default.gtkw:126: dead net path 'ucie2_pipe7_bridge.link.state_qq[3:0]' — not in build/waves/test_roundtrip.fst
[WAVES] dv/waves/default.gtkw:127: 'tx_data' exists but its range [63:0] does not — dump has ['[79:0]']
[WAVES] wave-check FAILED: 2 dead path(s) in 1 layout(s) — re-curate them against a fresh `make waves` dump   (exit 1)
```

Clean skip with no `fst2vcd`, and the auto-build path after `rm -rf build/waves`:

```
[WAVES] wave-check SKIPPED: 'fst2vcd-nope' not on PATH (apt-get install -y gtkwave) — 1 layout(s) unchecked   (exit 0)
[WAVES] wave-check: build/waves/test_roundtrip.fst missing — running: make waves TEST=roundtrip
```

**Not runnable here, said plainly:** opening the GTKWave **GUI** (`make wave`)
needs a display, so it was not run as a target on this headless runner; what was
proven instead is that the exact command line `make wave` issues
(`gtkwave --save=dv/waves/default.gtkw build/waves/test_roundtrip.fst`) loads the
committed layout and materialises all 60 rows, under `xvfb`. `make uvm` /
`make trace-compare` / `make lint-uvm` were **not** run — this runner has no
from-source UVM Verilator and no `UVM_HOME`; CI's `uvm-verilator.yml` measures
them on this PR, and no file they compile was changed.

### Deferred (deliberately, not forgotten)

`make waves-uvm` / `make wave-uvm` for the SV UVM env. The mechanism is a small
`` `ifdef WAVES `` `$dumpfile`/`$dumpvars` block plus a `WAVES=1` branch in
`dv/uvm/vlt/Makefile`, but it needs the from-source UVM Verilator to compile at
all — this runner has none, and the light CI job does not either — so it could
not be built, run or proven anywhere reachable from here. Landing unverifiable
SystemVerilog into `dv/uvm/sv/tb_ucie2_pipe7.sv` would additionally have forced a
regeneration of the committed EDA Playground bundle, which `make eda-check`
gates. Better done in an increment that runs where the UVM Verilator lives.

### CI step — for maintainer to apply

Optional and **advisory**. The swarm's token cannot write
`.github/workflows/**`, so this is authored here. It adds one post-gate step to
the **existing** `.github/workflows/uvm-verilator.yml`, next to the other
advisory post-gate steps (`coverage`, `eda-check`, `metrics`) — a new job is not
warranted for a check this cheap. `make wave-check` builds its own dump, so it
needs apt `gtkwave` (for `fst2vcd`) and nothing else new.

Add `gtkwave` to that workflow's apt install list, and append:

```yaml
      - name: GTKWave layout drift-guard (advisory, post-gate)
        continue-on-error: true
        run: make wave-check WAVE_CHECK_ARGS="--make-arg PYTHON3=$(command -v python3)"
```

Notes for whoever applies it:
- **`continue-on-error: true`** and placed **after** the cross-check, so a rotted
  layout can never red `lint`, `uvm-verilator` or `trace-compare`. This is a
  documentation-quality check, not a correctness gate.
- `--make-arg PYTHON3=$(command -v python3)` is the same documented GitHub-runner
  workaround the metrics job uses: `make wave-check` may need to run `make waves`
  to produce the dump, and Verilator's `verilated.mk` hardcodes
  `/usr/bin/python3`, which is a different interpreter from the one cocotb runs
  on.
- If `gtkwave` is *not* added to the apt list, the step still passes — it prints
  `wave-check SKIPPED` and exits 0. That is the honest outcome, not a false green.

## Increment 4 — waves: self-contained browser viewer — **LANDED**

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

### What landed

**Honest headline first: this is the smaller self-contained VCD viewer, not a
vendored Surfer WASM build.** That was a deliberate choice, and the plan
explicitly allows it. A Surfer/WASM bundle is a multi-megabyte binary artifact
that would have to be committed here, that nobody reviewing a PR can read, and
whose provenance we could not verify offline. `dv/waves/viewer/wave_viewer.html`
is ~700 lines of dependency-free ES5 + CSS that a reviewer can read end to end.
It is **not** a GTKWave replacement — no bundles, no expressions, no saved
layouts, no analog traces — and the README says so. Where a display exists,
`make wave` is still the better tool; this is for the Codespace/browser workflow
where GTKWave is simply not reachable.

**1. `make wave-web [TEST=<name>]` → `tools/wave_web.py` (stdlib).**
It consumes **increment 3's dump, unchanged** — `build/waves/test_<TEST>.fst`,
the one the `-DWAVES` build wrote — and runs `make waves TEST=<name>` itself if
it is missing. There is **no second dump path**: nothing new is compiled or
simulated, and `dv/pyuvm/Makefile` is not touched by this increment at all. The
FST is converted to VCD **once, at bundle time**, by apt GTKWave's `fst2vcd`
(already an increment-3 dependency); the browser never sees an FST. That VCD is
base64'd into the committed viewer template along with a small JSON metadata
blob, and the result is ONE file under `build/waves/`.

**2. "Self-contained" is checked on the artifact, not asserted.** After writing
the page, `wave_web.py` re-scans it with `external_refs()` **imported from
`tools/metrics_dashboard.py`** — one implementation of that scanner for the whole
repo, so `make dashboard` and `make wave-web` can never drift on what "no CDN"
means — and prints the count. If the count is non-zero the target **fails**, so a
viewer that ever grew a CDN link, a web font or an async request could not ship.
Measured **0**, on the generated bundles and on the committed template:

```
build/waves/test_roundtrip.html, build/waves/test_smoke.html,
dv/waves/viewer/wave_viewer.html — all three:
  http 0   https 0   "<script src=" 0   @import 0   "url(" 0   "fetch(" 0
  XMLHttpRequest 0   WebSocket 0   "<link" 0   srcset 0   "<img" 0
  "<iframe" 0   importScripts 0   //cdn 0   integrity= 0
```

The only hits anywhere in this increment are inside `tools/wave_web.py` itself,
in the comment and the imported regex list that *name* those constructs in order
to look for them — a Python script the browser never loads.

**3. It really renders, offline — proven headlessly, not claimed.** Rendering is
a browser action, so it was driven as one: headless Chrome with
`--host-resolver-rules="MAP * ~NOTFOUND"` (every hostname fails to resolve — the
network is gone) on the `file://` URL produced a full screenshot of the waveform.
It was then driven over the W3C WebDriver protocol (chromedriver + stdlib
`urllib`; no extra pip) to exercise the UI for real:

- 50 default rows materialise from `dv/waves/default.gtkw`; 559 signals in the
  tree; `8668 value changes, 410001ps @ 1ps`;
- radix round-trip on the 128-bit `lp_data` at a cursor 204838.502ps into the
  run — `0x100700000000abcd0007` / `75686990934433172619271` / `b0000…0111` —
  with the udec and bin renderings cross-checked against Python's own `int()`
  (equal);
- filter (`deframer` → 26 of 559), `clear` → 0 rows, `default` → 50 rows,
  click-to-add from the tree → 51 rows, zoom-in → `view 61500.15ps …
  348500.85ps`, `fit` → `view 0ps … 410001ps`, click-to-set-cursor;
- the canvas is genuinely painted (106660 non-background pixels sampled).

The committed **template** was opened directly too: unfilled it is still valid
HTML/JS and renders "No waveform bundled … run `make wave-web`" rather than
throwing. That check found a real bug — the metadata placeholder had been spliced
into a JS expression position, a syntax error before substitution — now fixed by
carrying it in its own `application/json` data block.

**4. Reuse instead of re-implementation.** The default signal list comes from the
same curated `dv/waves/<TEST>.gtkw` (else `default.gtkw`) increment 3 committed,
read with `layout_paths()` / `RANGE_RE` **imported from `tools/wave_check.py`** —
so the page opens on the same 50 signals GTKWave would, and `make wave-check`
stays the single guard on those paths. Group/comment rows are not carried over
(the viewer has no group concept); paths a dump does not contain are silently
skipped, which is what makes `default.gtkw` a usable default view for
`TEST=smoke` too.

**5. Off-gate, and structurally unable to reach it.** No RTL, no testbench, no
trace emitter (`dv/pyuvm/test_roundtrip.py`, `dv/uvm/sv/**`), no clock/reset/
stimulus schedule and no simulator flag was touched. The whole increment is: a
new committed viewer template, a new `tools/` script, one new `.PHONY` target,
`make help`, and docs. `build/waves/` was already git-ignored, so the bundle is
too. No file under `.github/workflows/` was edited, and none needs to be.
Proof rather than assertion: after `make lint && make pyuvm && make fcov` on a
cleaned tree, `dv/pyuvm/sim_build/Vtop_classes.mk` still carries `VM_TRACE = 0` /
`VM_TRACE_VCD = 0` / `VM_TRACE_FST = 0`, no `*.vcd`/`*.fst` exists anywhere under
`dv/pyuvm/` or `rtl/`, and `dv/pyuvm/build/bridge.trace` still has md5
`c1b8a30cc2e822e5efe7e5e103cc9b12` — byte-identical to the value increment 3
recorded.

**LANDED banners (local, GitHub runner: apt Verilator 5.020, Icarus 12,
cocotb 1.9.2 + pyuvm 4.0.1 + cocotb_coverage 1.2.0, apt gtkwave 3.3.116,
Chrome + chromedriver for the headless render check):**

```
[lint] RTL OK
** test_roundtrip.RoundtripTest   PASS         410.00           0.04      10317.06  **
** TESTS=1 PASS=1 FAIL=0 SKIP=0                410.00           0.07       5841.17  **
[SB] driven=8 recovered=8 stream_words=13 model_words=13
[SB] integrated-bridge cross-check PASS (3-way agreement)
[FCOV] bins=39/39 = 100.0%  tool=cocotb_coverage
[WAVES] wrote build/waves/test_roundtrip.fst (9597 bytes) from dv/pyuvm MODULE=test_roundtrip (Verilator FST, -DWAVES build)
[WAVES] wrote build/waves/test_roundtrip.html (256304 bytes) — single self-contained file: inlined viewer + base64 VCD, 0 external resource ref(s) [none]
[WAVES] source dump build/waves/test_roundtrip.fst (9597 bytes, the -DWAVES FST from `make waves`) -> 170712 bytes of VCD, 50 default signal(s) from dv/waves/default.gtkw
[WAVES] open it in a browser — offline, no CDN, no external fetch: file:///…/build/waves/test_roundtrip.html
```

Timings unchanged: `make lint` 0.09 s, a clean `make pyuvm` 12.05 s (increment 3
recorded 12.5 s), `make fcov FCOV_SIM=icarus` 2.95 s.

The auto-build path was exercised for real on a second target, with no
`build/waves/test_smoke.fst` present:

```
[WAVES] wave-web: build/waves/test_smoke.fst missing — running: make waves TEST=smoke
[WAVES] wrote build/waves/test_smoke.html (93159 bytes) — single self-contained file: inlined viewer + base64 VCD, 0 external resource ref(s) [none]
```

and so was the self-guard — the viewer's own header comment originally spelled
those constructs out, and the target refused to ship the bundle until it was
reworded:

```
[WAVES] wrote build/waves/test_roundtrip.html (255791 bytes) — … 3 external resource ref(s) [<link ...>=1, css url(...)=1, fetch()/XHR=1]
[WAVES] wave-web FAILED: 3 external resource ref(s) in build/waves/test_roundtrip.html — the bundle must be openable offline   (exit 1)
```

**Not runnable here, said plainly:** `make uvm` / `make trace-compare` /
`make lint-uvm` were **not** run — this runner has no from-source UVM Verilator
and no `UVM_HOME`; CI's `uvm-verilator.yml` measures them on this PR, and this
increment changes no file they compile. (`make pyuvm` needs this runner's
documented `PYTHON3="$(command -v python3)"` workaround — a pre-existing host
quirk described in `README.md`, not something this increment introduced.)
Whether the page *looks* right is ultimately a human judgement in a real browser;
what is automated is that it is one file, that it contains zero external
references, and that a headless browser with no network parses it, paints the
canvas and answers correctly when driven.

### CI step — none needed

`make wave-web` is a developer artifact generator, not a check: it produces a
git-ignored file for a human to open. Wiring it into CI would upload a ~250 KB
artifact nobody asked for on every run. The one thing worth guarding — that the
curated layout still resolves — is already increment 3's `make wave-check`, whose
optional advisory step is authored above. No workflow file was edited.

**This closes Phase G.** There is no increment 5 in this thrust; the "Increment
5" heading below predates it and was authored directly by the maintainer.

## Increment 5 — UVM Cookbook restructure + EDA Playground bundle

Maintainer request (2026-09-02): make the SV UVM env read like standard UVM
(UVM Cookbook / Easier-UVM — **one class per file**, in an agent/env/test tree)
and add a **paste-ready EDA Playground bundle** of the whole DUT + testbench.
Authored directly (not via the swarm), structural split only.

- **Split** `dv/uvm/sv/` into one-class-per-file `.sv` sources under
  `fdi_agent/`, `pipe_agent/`, `env/`, `test/`, kept in the single package
  `ucie2_pipe7_uvm_pkg` via an ordered `` `include `` list (Cookbook's own
  idiom; one compilation unit ⇒ no cross-package risk). The five old `.svh`
  blobs are gone. **Pure textual reorganization** — the token stream is
  byte-identical to the pre-split package (verified by a comment/whitespace-
  normalized diff: 268 lines each, zero delta), so `test/ucie2_roundtrip_test.sv`
  (the trace emitter) and `trace_compare` are untouched. `dv/uvm/vlt/Makefile`
  `SRCS` is unchanged (it still compiles the package, which now `` `include ``s
  the split files).
- **EDA Playground bundle**: `tools/gen_eda_playground.py` (stdlib) +
  `make eda-playground` / `make eda-check`. Concatenates `rtl/` + `dv/uvm/sv/`
  in vlt compile order into `dv/uvm/eda_playground/{design.sv, testbench.sv,
  ucie2_pipe7_bridge_top.sv}`, flattening the UVM package's project `` `include ``s
  inline (EDA Playground has no incdir). Additive, **off-gate**; the bundle
  cannot run `trace_compare` (documented honestly in its README).

**LANDED banners (local):** `[lint] RTL OK`; PyUVM `RoundtripTest PASS`
(3-way agreement, driven=8 recovered=8); `[lint-uvm] SV UVM env elaborates OK`
(from-source Verilator 5.050, split tree); `[EDA] wrote 3 files (5103 lines)` +
`[EDA] up to date` (drift-guard) + all-in-one elaborates under Verilator. The
byte-identical `make uvm` + `make trace-compare` proof runs in CI.

### CI step — APPLIED in this PR (advisory, post-gate)

`make eda-check` is a pure-Python drift-guard (no simulator), wired into
`.github/workflows/uvm-verilator.yml` as an advisory, **post-gate**
(`continue-on-error`) step after the cross-check — authored directly (this PR
carries workflow scope), not deferred to a follow-up:

```yaml
      - name: EDA Playground bundle drift-guard (advisory, post-gate)
        continue-on-error: true
        run: make eda-check
```

## Acceptance (every increment)

`make lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare` byte-identical green, unchanged
timings; the new target(s) work and are documented (`README`/`PLAN.md`/`docs` +
`make help`); wave dumping stays behind `-DWAVES` and off the gate; one PR, CI
green, a human merges.
