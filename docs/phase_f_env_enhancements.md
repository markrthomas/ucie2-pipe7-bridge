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
  a from-source SymbiYosys/yosys, not oss-cad-suite.
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

## Increment 3 — formal (SymbiYosys)

`make formal` — SymbiYosys (from-source yosys+sby, NOT oss-cad-suite) BMC on a
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
