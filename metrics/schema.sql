-- =============================================================================
-- ucie2-pipe7-bridge — DV metrics store (Phase F increment 4).
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
-- =============================================================================

PRAGMA user_version = 1;

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
    formal_jobs_total   INTEGER
);

CREATE INDEX IF NOT EXISTS runs_ts_idx  ON runs (ts_utc);
CREATE INDEX IF NOT EXISTS runs_sha_idx ON runs (git_sha);

-- Convenience: the most recent row.
CREATE VIEW IF NOT EXISTS latest_run AS
    SELECT * FROM runs ORDER BY id DESC LIMIT 1;
