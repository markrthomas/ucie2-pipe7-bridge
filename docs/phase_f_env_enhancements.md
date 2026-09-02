# Phase F — DV env enhancements (swarm plan)

Task plan for the DV swarm (`make swarm` / the `DV swarm` workflow). Bring this
repo's DV env toward the `axi-on-ucie-to-mem` sibling's richness. **Land one
increment per PR** (a human merges); do them in order. Read the whole file, then
implement **only the increment named in your task** (default: increment 1).

## Hard invariants (do not violate)

- **The cycle-accurate cross-check is sacred.** `make lint`/`pyuvm`/`fcov`/`uvm`
  and the per-cycle trace stay **byte-identical** and equally fast. Every new tier
  is **additive**, behind its own `make` target, and **outside** the existing
  gate — never fold it into `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare` or change
  the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`, `dv/pyuvm/test_roundtrip.py`)
  or the fixed clock/reset/stimulus schedule.
- **No OSS CAD Suite** in the reproducible envs (`.devcontainer`, `Dockerfile*`,
  CI). Use apt verilator/iverilog + the from-source UVM Verilator; for formal use
  apt yosys + SymbiYosys from YosysHQ/sby (pure-Python scripts, not a source
  compile) + z3, not oss-cad-suite. (Original "from-source yosys" was relaxed to
  apt yosys 2026-09-02 — the source compile blew the swarm's timed budget; apt
  yosys is a distro package, still NOT oss-cad-suite.)
- Pinned-tool paths, `[BANNER]` style, one clean commit per logical step, the
  `Co-Authored-By` + `Claude-Session` trailers. **Never commit on `main`** —
  branch `swarm/phaseF-<slug>`, push incrementally, open a PR (draft early), mark
  "PARTIAL — resume needed" on cutoff. CI validates on the PR.

## Increment 1 — bound SVA (deferred from item 9)

A bind-based SystemVerilog assertions module on the bridge boundary, bound to
`ucie2_pipe7_bridge` (no RTL edits). Assert the safe, always-true properties:
- `tx_data_valid` never high while `tx_elec_idle` is asserted;
- no `sync_error` in steady state once `block_locked`;
- `pl_stallreq` handshake well-formed; `rx_overflow` never asserts in the directed
  round-trip.
Wire it so `make lint-uvm` (elaborate) and the `--binary` UVM run pick it up via
the existing bind path; add `rtl/ucie2_pipe7_sva.sv` (or `dv/uvm/sv/…_sva.svh`) +
the bind. Gate: `make lint` + `make lint-uvm` clean; the `--binary` UVM run on the
PR shows 0 assertion failures; trace stays byte-identical.

## Increment 2 — line-coverage gate

`make coverage` — a Verilator `--coverage` build of the directed round-trip that
emits a coverage report + an overall line-coverage %. Print `[COV] line=NN.N%`.
Start the floor **advisory** (report only), then set a threshold (e.g. ≥ 80%) once
the baseline is known. Additive target + a CI step **after** the gate; never
inside a timed DV run. Docs + `make help`.

**LANDED.** `make coverage` (root `Makefile`) runs the directed round-trip in a
separate `RTL_COVERAGE=1` build dir (`dv/pyuvm/cov_build`, `--coverage-line`) and
scores it with `tools/coverage_report.py` → `build/coverage/`. Measured baseline
on this RTL: **`[COV] line=63.3%` (38/60 rtl/ lines)**; branch points 34/45 =
75.6% (informational). The floor stays **advisory** — `tools/coverage_report.py`
exits 0 unless `--min` is given, and the target only passes it when `COV_MIN` is
set (`make coverage COV_MIN=NN`). **A `>= NN%` gate is set in a follow-up once
the baseline is agreed**; the sensible next step is coverage *closure* (the
uncovered lines are the msgbus master and the PIPE MAC control FSM, which the
loopback round-trip never drives), not just raising a number. CI: a post-gate,
`continue-on-error` step at the end of `.github/workflows/uvm-verilator.yml`,
after `trace-compare` and its artifact upload.

## Increment 3 — formal (SymbiYosys)

`make formal` — SymbiYosys (apt yosys + YosysHQ/sby + z3, NOT oss-cad-suite) BMC on a
tractable block or two (the Gen5 framer/deframer gearbox, the msgbus/ctrl FSM):
prove the FLAGGED-safe properties (no illegal FSM state, gearbox sync legality).
CI/Railway-only if heavy; document the tool install. `[FORMAL] … PASSED`.

**LANDED.** `make formal` (root `Makefile` → `tools/formal_run.sh`) runs three
**bounded** model checks (BMC — *not* an unbounded proof) with apt `yosys` 0.33 +
SymbiYosys + `z3` 4.8.12. Measured on this host (~25 s total):

```
[FORMAL] pipe7_gearbox: BMC depth 12 PASSED
[FORMAL] pipe7_mac_ctrl_fsm: BMC depth 24 PASSED
[FORMAL] ucie2_fdi_link_fsm: BMC depth 24 PASSED
[FORMAL] 3 job(s) PASSED (bounded model check -- not an unbounded proof)
```

Blocks and properties (all stated on the **port boundary** in `formal/*_formal.sv`
wrappers — **no RTL edits**, and no hierarchical references, which the yosys
frontend does not resolve):

- **`ucie2_fdi_link_fsm`** — *no illegal FSM state*: `pl_state_sts` is always a
  legal `fdi_state_e` (the FLAGGED encoding, cross-check §C) given legal
  `lp_state_req`; `link_active ⇔ FDI_ACTIVE`; the state only moves on
  `lp_linkerror` or a completed `pl_stallreq`/`lp_stallack` handshake;
  `pl_stallreq` only rises on a genuinely different request; rx-active/wake/clk
  mirrors are exact.
- **`pipe7_mac_ctrl_fsm`** — *PIPE 7.1 §8.4.1 rate/width legality*: Rate / Width /
  RxWidth only ever change out of a cycle that was busy, with TxElecIdle asserted
  and PowerDown in P0/P1; PowerDown only moves out of an idle `REQ_POWER`;
  `done`/`req_error` mutually exclusive; `done ⇒ !busy`; `busy` only rises on
  `req_valid`; `PclkChangeAck` low unless `PCLK_IS_PHY_INPUT`, and then only after
  `PclkChangeOk`. Both PCLK parameterizations proved at once.
- **`pipe7_gearbox`** (`pipe7_tx_framer_gb` + `pipe7_rx_deframer_gb`) — *gearbox
  sync legality*: the framer never over-accepts (`pl_acc ≤ pl_cnt`) and its
  accumulator occupancy, re-derived from the observable interface, stays within
  `[0, ACC_W]` (no overflow, no dropped bits); the deframer never reports an
  illegal `pl_cnt`, **never passes a block with an illegal sync header upstream**
  (`sync_error ⇒ pl_cnt == 0`), only errors from a locked state, always drops lock
  on an error and always gains it on a delivered block.

Each job was mutation-checked (a deliberately false variant of one property makes
the job FAIL), so the assertions are live, not vacuous.

Two implementation notes worth keeping:

- `tools/formal_prep.py` writes a mechanically transformed **copy** of the RTL into
  `build/formal/src/`: the apt yosys 0.33 Verilog frontend cannot parse
  `import ucie2_pipe7_pkg::*;`, `return` inside a function, or an `int'()` cast, so
  package identifiers are explicitly scoped and those two constructs rewritten.
  `rtl/` is never touched, and nothing in the gate reads the copy.
- The `.sby` engine is `smtbmc --unroll z3`. yosys-smtbmc's default non-unrolled
  (uninterpreted-function) encoding is pathological for z3 4.8.12 — it does not
  finish even at depth 2 — while the unrolled pure-bitvector encoding solves the
  same query in seconds.

Additive and outside the gate: `make formal` is a new target, reads no testbench,
and writes only under `build/formal/`. The `Dockerfile` runtime stage carries apt
`yosys` + `z3` + SymbiYosys (shallow clone, pure-Python `make install`) + `click`,
and its fail-fast healthcheck now asserts all three. On a host without `sby` the
target prints `[FORMAL] SKIP: …` and exits 0.

### CI step — APPLIED (maintainer follow-up, 2026-09-02)

The swarm's GitHub App token could not write `.github/workflows/**`
(`refusing to allow a GitHub App to create or update workflow … without
'workflows' permission`), so the post-gate CI step below was authored and
verified in the increment-3 PR but **applied separately by the maintainer** (who
pushes over HTTPS with `workflows` scope). It now lives in
`.github/workflows/uvm-verilator.yml`, **after** the "Upload traces + UVM log"
step (i.e. after `trace-compare` and its artifact upload) and **before** the
advisory "RTL line coverage" step:

```yaml
      # Additive formal tier (Phase F increment 3, SymbiYosys BMC). Strictly
      # POST-GATE: placed after trace-compare and its artifact upload so it can
      # never perturb lint/pyuvm/fcov/uvm/trace-compare. Reads no testbench and
      # touches no rtl/dv file. z3 is already installed above; add yosys + the
      # click module + SymbiYosys itself (shallow git clone, `make install` is
      # a pure-Python copy -- no compile). NOT OSS CAD Suite. This must PASS.
      - name: Install SymbiYosys formal tools (yosys, sby, click)
        run: |
          set -euo pipefail
          sudo apt-get update && sudo apt-get install -y yosys
          pip install --break-system-packages click
          git clone --depth 1 https://github.com/YosysHQ/sby /tmp/sby
          sudo make -C /tmp/sby install
          rm -rf /tmp/sby

      - name: Formal BMC (SymbiYosys, post-gate)
        run: make formal
```

It must PASS, so it is deliberately **not** `continue-on-error` (unlike the
advisory `make coverage` step) — but it stays strictly after the sacred gate.

## Increment 4 — metrics + dashboard

Port the sibling's `docs/SWARM_PLAN.md` feature: committed SQLite
(`metrics/metrics.db`) + a self-contained `metrics/dashboard.html` (inlined
CSS/JS, no CDN), `make metrics` (collect a row) + `make dashboard` (regen), a
post-gate CI step. Measured vs estimated kept separate; never perturb the gate.

**LANDED.** Four new files plus two `Makefile` targets, all **stdlib Python**
(the `sqlite3` *module*; no `sqlite3` CLI, no pip package, no CDN anywhere):

| File | What |
|------|------|
| `metrics/schema.sql` | one `runs` table: ISO-8601 UTC timestamp, git short-sha / branch / dirty flag, env, row-level `source`, and per tier (`lint`, `pyuvm`, `fcov`, `uvm`, `trace_compare`, `coverage`, `formal`) a `*_status` / `*_secs` / `*_source` triple plus its headline number (`fcov_bins_hit/total`, `coverage_line_pct`, `formal_jobs_passed/total`, `trace_cycles`) |
| `metrics/metrics.db` | the committed store, initialized from that schema with a real measured row from the swarm host |
| `tools/metrics_collect.py` | runs the existing tier targets **unmodified** (or reads the log the gate already wrote) and parses their banners into one appended row |
| `tools/metrics_dashboard.py` | regenerates `metrics/dashboard.html` — one self-contained file |

Measured on the swarm host (GitHub runner: apt Verilator 5.020, Icarus 12,
yosys 0.33 + sby 0.68 + z3 4.8.12), `make metrics` then `make dashboard`:

```
[METRICS] running: make lint
[METRICS] running: make pyuvm
[METRICS] running: make fcov
[METRICS] running: make coverage
[METRICS] running: make formal
[METRICS] lint=pass  pyuvm=pass  fcov=pass  uvm=not-run  trace-compare=not-run  coverage=pass  formal=pass
[METRICS] row #1 appended to metrics/metrics.db (1 row(s), source=measured, sha=ac6af48, 2026-09-02T15:06:43Z)
[DASH] wrote metrics/dashboard.html (9913 bytes, 1 of 1 row(s), self-contained: no CDN/JS/external fetch)
```

with the gate itself unchanged in the same environment:

```
[lint] RTL OK
** test_roundtrip.RoundtripTest   PASS         410.00           0.04       9878.56  **
** TESTS=1 PASS=1 FAIL=0 SKIP=0                410.00           0.07       5691.59  **
[SB] integrated-bridge cross-check PASS (3-way agreement)
[FCOV] bins=39/39 = 100.0%  tool=cocotb_coverage
[COV] line=63.3% (38/60 RTL lines)
[FORMAL] 3 job(s) PASSED (bounded model check -- not an unbounded proof)
```

**Measured vs estimated, honestly.** Every tier carries its own `*_source`:

- `measured` — the tier ran during that invocation (or its banner came from the
  log the gate had just written, e.g. `dv/uvm/vlt/obj/run.log` for `uvm`, which
  is deliberately *never* rebuilt by the collector). Recorded in `notes`.
- `estimated` — carried forward from the newest previously-measured row by
  `make metrics METRICS_ARGS=--carry-forward`. **Off by default.** Such values
  are starred in the banner, badged in the dashboard, and flip the row-level
  `source` to `mixed`/`estimated`; they are never presented as a measurement of
  the current commit.
- `none` — the tier did not run and nothing was carried forward; status is
  `not-run`.

A tier that cannot run (tool absent, or the `--binary` UVM flow that needs the
from-source Verilator) is classified **`not-run`, never `fail`**, and no number
is invented for it — the classifier only records `fail` on positive evidence (a
`FAIL`/`FAILED` banner, cocotb `FAIL=n>0`, `[COV] FAIL`) or a non-zero exit with
no tool-absence marker in the output. That is why the seed row honestly shows
`uvm=not-run` and `trace-compare=not-run`: this host has neither the UVM
Verilator nor a UVM trace to diff. `trace-compare` is skipped outright unless
**both** TB traces are on disk.

The dashboard is a **single self-contained HTML file**: all CSS inlined in a
`<style>` block, trend charts drawn as hand-written inline `<svg>` polylines (no
chart library), **no `<script src>`, no CDN, no external fetch of any kind** —
verified with a grep for `http`/`src=`/`@import`/`url(` over the output (zero
hits). It renders offline by double-clicking.

Additive and outside the gate: `make metrics` / `make dashboard` are new targets,
are not invoked by `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`/
`formal`, touch no RTL, no testbench, neither trace emitter and no part of the
fixed clock/reset/stimulus schedule — the collector only shells out to the
existing targets and reads their stdout. Per-tier logs are tee'd to
`build/metrics/<tier>.log` (git-ignored); only `metrics/metrics.db` and
`metrics/dashboard.html` are committed.

> Host note, unrelated to this change: on a box where `/usr/bin/python3` (which
> Verilator's `verilated.mk` hardcodes) is a different version from the Python
> cocotb runs on, the Verilator build dies with `ModuleNotFoundError: No module
> named 'encodings'`. The documented workaround applies to the collector too —
> `make metrics METRICS_ARGS="--make-arg PYTHON3=$(command -v python3)"`.

### CI step — APPLIED (maintainer follow-up, 2026-09-02)

Same constraint as increment 3: the swarm's GitHub App token cannot write
`.github/workflows/**`, so this step was authored here and **applied separately
by the maintainer** (who pushes over HTTPS with `workflows` scope). It now lives
at the **end** of `.github/workflows/uvm-verilator.yml` — after the "Upload
coverage report" step, i.e. after everything else in the job — so it is strictly
post-gate and can never sit inside a timed DV run:

```yaml
      # Additive DV metrics + dashboard (Phase F increment 4). LAST step in the
      # job: strictly POST-GATE, after the --binary UVM run, trace-compare and
      # the coverage steps, so it can never perturb the byte-identical
      # cross-check. ADVISORY (continue-on-error) — a metrics hiccup must never
      # red the job that guards the gate. The collector re-runs only the cheap
      # tiers; `uvm` is NOT rebuilt, its result is read from the run.log the
      # gate already wrote, and `trace-compare` re-diffs the traces on disk.
      # Tiers whose tools are absent are recorded 'not-run', never 'fail'.
      - name: DV metrics row (advisory, post-gate)
        continue-on-error: true
        run: |
          make metrics \
            METRICS_TIERS=lint,pyuvm,fcov,coverage,formal,trace-compare \
            METRICS_ARGS="--env ci \
              --make-arg VERILATOR=$VERILATOR_PREFIX/bin/verilator \
              --make-arg VERILATOR_COVERAGE=$VERILATOR_PREFIX/bin/verilator_coverage"
          make dashboard

      - name: Upload metrics dashboard
        if: always()
        continue-on-error: true
        uses: actions/upload-artifact@v4
        with:
          name: dv-metrics-dashboard
          path: |
            metrics/dashboard.html
            metrics/metrics.db
          retention-days: 7
          if-no-files-found: ignore
```

Note what this step does **not** do: it does not commit the row back to the repo.
The CI run's `metrics.db`/`dashboard.html` are published as an **artifact**; the
committed store grows when a maintainer runs `make metrics && make dashboard`
locally and commits the result. (Auto-committing from CI would need a push token
and would race the PR branch — deliberately out of scope.)

## Acceptance (every increment)

`make lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare` byte-identical green, unchanged
timings; the new target works and is documented (`README`/`PLAN.md`/`docs` +
`make help`); one PR, CI green, a human merges.
