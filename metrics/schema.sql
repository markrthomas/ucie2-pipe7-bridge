-- =============================================================================
-- ucie2-pipe7-bridge — DV metrics store.
--   user_version = 1  Phase F increment 4 — the `runs` table below.
--   user_version = 2  Phase G increment 1 — extra signals (coverage branch %,
--                     per-job formal BMC depth, round-trip sim cycles, collect
--                     peak RSS) + advisory regression flags. Purely ADDITIVE:
--                     every v1 column and row survives. `tools/metrics_collect.py`
--                     migrates a v1 database in place on first run (ALTER TABLE
--                     ADD COLUMN for each missing column, then this script).
--
-- One row per `make metrics` invocation. ADDITIVE and OUTSIDE the sacred gate:
-- nothing in lint/pyuvm/fcov/uvm/trace-compare/coverage/formal reads or writes
-- this database, and collecting a row never perturbs the per-cycle trace.
--
-- Applied with Python's stdlib sqlite3 module (`tools/metrics_collect.py`);
-- the `sqlite3` CLI is NOT required anywhere.
--
-- HONESTY RULE (why every tier carries its own `*_source`):
--   'measured'  — that tier actually ran during THIS invocation, and the
--                 status/number below came from its own banner.
--   'estimated' — carried forward from an older row (only with
--                 `metrics_collect.py --carry-forward`); it is NOT a
--                 measurement of this commit. Rendered in a distinct style by
--                 the dashboard and never mixed into a "measured" claim.
--   'none'      — the tier did not run and nothing was carried forward. Its
--                 status is 'not-run'. A tier that is absent (tool missing,
--                 too heavy for this host, skipped) is NEVER recorded as
--                 'fail', and no number is ever fabricated for it.
--
-- The rule is per SIGNAL, not just per tier: every v2 signal added below carries
-- its own `*_source` so a number can never outlive the run that measured it.
-- =============================================================================

PRAGMA user_version = 2;

CREATE TABLE IF NOT EXISTS runs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Provenance -------------------------------------------------------------
    ts_utc              TEXT    NOT NULL,   -- ISO-8601 UTC, e.g. 2026-09-02T14:52:31Z
    git_sha             TEXT    NOT NULL,   -- git short sha (or 'unknown')
    git_branch          TEXT    NOT NULL,   -- branch name (or 'unknown'/'detached')
    git_dirty           INTEGER NOT NULL DEFAULT 0,   -- 1 = uncommitted changes present
    env                 TEXT    NOT NULL DEFAULT 'local',  -- local | ci | railway | ...
    -- Row-level roll-up of the per-tier sources below:
    --   'measured' (every recorded tier ran here) | 'mixed' (some carried
    --   forward) | 'estimated' (nothing ran this invocation).
    source              TEXT    NOT NULL DEFAULT 'measured'
                        CHECK (source IN ('measured', 'mixed', 'estimated')),
    total_secs          REAL,               -- wall time of the collect run
    notes               TEXT,

    -- Per-tier results -------------------------------------------------------
    -- status: 'pass' | 'fail' | 'not-run'   secs: wall time when measured
    -- source: 'measured' | 'estimated' | 'none'
    lint_status         TEXT    NOT NULL DEFAULT 'not-run'
                        CHECK (lint_status IN ('pass', 'fail', 'not-run')),
    lint_secs           REAL,
    lint_source         TEXT    NOT NULL DEFAULT 'none'
                        CHECK (lint_source IN ('measured', 'estimated', 'none')),

    pyuvm_status        TEXT    NOT NULL DEFAULT 'not-run'
                        CHECK (pyuvm_status IN ('pass', 'fail', 'not-run')),
    pyuvm_secs          REAL,
    pyuvm_source        TEXT    NOT NULL DEFAULT 'none'
                        CHECK (pyuvm_source IN ('measured', 'estimated', 'none')),

    fcov_status         TEXT    NOT NULL DEFAULT 'not-run'
                        CHECK (fcov_status IN ('pass', 'fail', 'not-run')),
    fcov_secs           REAL,
    fcov_source         TEXT    NOT NULL DEFAULT 'none'
                        CHECK (fcov_source IN ('measured', 'estimated', 'none')),
    fcov_bins_hit       INTEGER,            -- from `[FCOV] bins=H/T = P%`
    fcov_bins_total     INTEGER,
    fcov_pct            REAL,

    uvm_status          TEXT    NOT NULL DEFAULT 'not-run'
                        CHECK (uvm_status IN ('pass', 'fail', 'not-run')),
    uvm_secs            REAL,
    uvm_source          TEXT    NOT NULL DEFAULT 'none'
                        CHECK (uvm_source IN ('measured', 'estimated', 'none')),

    trace_compare_status TEXT   NOT NULL DEFAULT 'not-run'
                        CHECK (trace_compare_status IN ('pass', 'fail', 'not-run')),
    trace_compare_secs  REAL,
    trace_compare_source TEXT   NOT NULL DEFAULT 'none'
                        CHECK (trace_compare_source IN ('measured', 'estimated', 'none')),
    trace_cycles        INTEGER,            -- identical cycles across both TBs

    coverage_status     TEXT    NOT NULL DEFAULT 'not-run'
                        CHECK (coverage_status IN ('pass', 'fail', 'not-run')),
    coverage_secs       REAL,
    coverage_source     TEXT    NOT NULL DEFAULT 'none'
                        CHECK (coverage_source IN ('measured', 'estimated', 'none')),
    coverage_line_pct   REAL,               -- from `[COV] line=NN.N%`

    formal_status       TEXT    NOT NULL DEFAULT 'not-run'
                        CHECK (formal_status IN ('pass', 'fail', 'not-run')),
    formal_secs         REAL,
    formal_source       TEXT    NOT NULL DEFAULT 'none'
                        CHECK (formal_source IN ('measured', 'estimated', 'none')),
    formal_jobs_passed  INTEGER,            -- from the `[FORMAL] <job>: … PASSED` lines
    formal_jobs_total   INTEGER,

    -- === user_version 2 (Phase G increment 1) ===============================
    -- Extra signals. Each carries its OWN `*_source` (measured|estimated|none)
    -- so it is never implied by a tier's roll-up source.

    -- Coverage branch %: the branch points Verilator's --coverage-line already
    -- emits, reported alongside (never folded into) the gated line %.
    -- From `[COV] branch=NN.N% (H/T …)`.
    coverage_branch_pct   REAL,
    coverage_branch_source TEXT NOT NULL DEFAULT 'none'
                        CHECK (coverage_branch_source IN ('measured', 'estimated', 'none')),

    -- Deepest BMC bound reached across this run's formal jobs, from the
    -- `[FORMAL] <job>: BMC depth N PASSED` lines. Per-JOB depths live in the
    -- `formal_jobs` side table below (measured runs only).
    formal_depth_max    INTEGER,
    formal_depth_source TEXT    NOT NULL DEFAULT 'none'
                        CHECK (formal_depth_source IN ('measured', 'estimated', 'none')),

    -- Simulated pclk cycles the directed round-trip traced, counted from the
    -- trace the pyuvm tier just wrote (dv/pyuvm/build/bridge.trace) — read-only,
    -- the emitter and its fixed schedule are never touched. Distinct from
    -- `trace_cycles`, which is what trace-compare diffed across BOTH TBs.
    roundtrip_cycles    INTEGER,
    roundtrip_cycles_source TEXT NOT NULL DEFAULT 'none'
                        CHECK (roundtrip_cycles_source IN ('measured', 'estimated', 'none')),

    -- Resources of the COLLECT run itself (not of any one tier). Wall time is
    -- the pre-existing `total_secs`; peak RSS is resource.getrusage()'s
    -- ru_maxrss, max(self, heaviest child), in MiB. `collect_source` covers
    -- both and is 'none' where the `resource` module is unavailable.
    collect_peak_rss_mb REAL,
    collect_source      TEXT    NOT NULL DEFAULT 'none'
                        CHECK (collect_source IN ('measured', 'estimated', 'none')),

    -- Advisory regression flags vs. the most recent prior MEASURED row on the
    -- same git_branch. NULL = not computed (e.g. a v1 row). NEVER a gate: these
    -- columns are reported by `make metrics`/`make dashboard` and nothing else.
    regressions         INTEGER,
    regression_notes    TEXT
);

-- Per-job formal BMC depth (user_version 2). One row per `[FORMAL] <job>:` line
-- of a MEASURED formal run; carried-forward (estimated) rows get no entries here,
-- so a depth can never be attributed to a job that did not run.
CREATE TABLE IF NOT EXISTS formal_jobs (
    run_id  INTEGER NOT NULL REFERENCES runs (id) ON DELETE CASCADE,
    job     TEXT    NOT NULL,               -- sby job name, e.g. ucie2_fdi_link_fsm
    depth   INTEGER,                        -- BMC bound N ('?' in the banner -> NULL)
    status  TEXT    NOT NULL
                        CHECK (status IN ('pass', 'fail')),
    source  TEXT    NOT NULL DEFAULT 'measured'
                        CHECK (source IN ('measured', 'estimated', 'none')),
    PRIMARY KEY (run_id, job)
);

CREATE INDEX IF NOT EXISTS runs_ts_idx  ON runs (ts_utc);
CREATE INDEX IF NOT EXISTS runs_sha_idx ON runs (git_sha);
CREATE INDEX IF NOT EXISTS runs_branch_idx ON runs (git_branch, id);

-- Convenience: the most recent row.
CREATE VIEW IF NOT EXISTS latest_run AS
    SELECT * FROM runs ORDER BY id DESC LIMIT 1;
