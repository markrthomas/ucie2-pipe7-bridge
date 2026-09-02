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

## Increment 4 — metrics + dashboard

Port the sibling's `docs/SWARM_PLAN.md` feature: committed SQLite
(`metrics/metrics.db`) + a self-contained `metrics/dashboard.html` (inlined
CSS/JS, no CDN), `make metrics` (collect a row) + `make dashboard` (regen), a
post-gate CI step. Measured vs estimated kept separate; never perturb the gate.

## Acceptance (every increment)

`make lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare` byte-identical green, unchanged
timings; the new target works and is documented (`README`/`PLAN.md`/`docs` +
`make help`); one PR, CI green, a human merges.
