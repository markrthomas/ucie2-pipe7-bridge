# AI restart — resume Phase I here

**Purpose:** the one file to read when (re)starting an AI session working on
**Phase I — design completion**. It is the live handoff: current state, the
ordered work queue with status, where everything lives, and the exact commands +
rules. Keep it current — tick items and move the ▶ marker as work lands.

> If you are a fresh session: read in this order — **`CLAUDE.md`** (constraints) →
> **`PLAN.md` §7 Phase I** (summary) → **this file** (live status) →
> **`docs/phase_i_design_completion.md`** (per-item detail). Then `make help`.

---

## Current state (as of 2026-09-16)

- Env is complete and **green**: RTL datapath (Gen5 proven end-to-end), two
  cycle-accurate TBs (PyUVM + SV UVM), `trace_compare`, coverage, formal,
  metrics/dashboard, waves, CI, Railway + Codespaces remote runners.
- `make uvm` is the single canonical SV UVM gate (CI + the container run it); you
  can offload it from a laptop with `make uvm-remote [RUNNER=railway|codespace]`.
- **Phase I in progress. I1 + I2 + I5 + I6 DONE.** I1: FDI link FSM (RETRAIN +
  managed states, encoding pinned, `make link-fsm`). I2: FDI `lp_is_os`/`pl_is_os`
  flit-type, `make is-os`. I5 (core): RX error-injection `make err-inject` (sync_error
  + loss-of-lock + re-lock). I6: Gen6 end-to-end + Gen5→Gen6 rate switch `make gen6`
  (bridge routes the FDI block into the Gen6 raw path, gated by rate; built at PW=160).
  I3: `pl_flit_cancel` retracts flits recovered through an RX FIFO overflow
  (`make flit-cancel`, PW=160; also delivered the deferred rx_overflow injection).
  Each byte-identical in Gen5, verified locally (lint/pyuvm/link-fsm/is-os/err-inject/
  gen6/flit-cancel/lint-uvm/b2b/formal); full `make uvm`+trace-compare confirmed by CI.
  **I4 is next** — the LAST FLAGGED item; then I7/I8.

## Work queue (tick as you go; ▶ = do next)

Detail for each is in `docs/phase_i_design_completion.md`.

- [x] **I9. Housekeeping** — sync PLAN/README status (landed with the plan PR).
- [x] **I1. FDI link-state FSM + `fdi_state_e` encoding** — done.
- [x] **I2. `is_os` derivation + forwarding** — done (`make is-os`; §B.1 un-FLAGGED).
- [x] **I5. Active error-injection DV (core)** — done (`make err-inject`; sync_error +
  loss-of-lock + re-lock). `rx_overflow`/backpressure active-injection deferred → I7.
- [x] **I6. Gen6 PAM4 end-to-end + Gen5→Gen6 rate switch** — done (`make gen6`, PW=160).
- [x] **I3. `pl_flit_cancel` semantics** — done (`make flit-cancel`, PW=160; retract flits
  recovered through an RX FIFO overflow — also delivered the deferred rx_overflow injection).
- [ ] ▶ **I4. Management/sideband register mapping** (`pipe7_regfile`/`pipe7_msgbus_master`;
  un-FLAG §F — the last FLAGGED item).
- [ ] **I7. Constrained-random + coverage closure** (backpressure still deferred here).
- [ ] **I8. H3b** — full-duplex SV UVM + credit FDI seam + B2B trace gate.

*(Update the ▶ marker and check boxes here in the same PR that lands each item.)*

## FLAGGED contract items → where they live

Source of truth: `docs/ucie2_pipe71_spec_crosscheck.md` → "FLAGGED items". Un-FLAG
a row in the same change that resolves it.

| Item | Spec § | Phase I item | Status |
|------|--------|--------------|--------|
| `fdi_state_e` encoding | §C | I1 | ✅ resolved |
| `is_os` derivation/forwarding | §B.1 | I2 | ✅ resolved |
| `pl_flit_cancel` | §B | I3 | ✅ resolved |
| mgmt/sideband reg map (`pkg.sv:132`, `pipe7_regfile`, `pipe7_msgbus_master`) | §F | I4 | ▶ open (last one) |

## Commands

```bash
# Green gate (run every commit; must stay green)
make lint && make pyuvm && make lint-uvm

# Reproduce a change end-to-end (RTL timing touch => re-verify the sacred trace)
make uvm && make trace-compare          # CI/Railway toolchain; locally use uvm-remote:
APPLY=1 make uvm-remote                  # Railway (or RUNNER=codespace)

# Stimulus knobs + debug
make pyuvm LEN=64 SEED=random PKT_TRACK=1
make wave LEN=64                         # focused-window FST + GTKWave

# Post-gate (never fold into the gate)
make coverage && make formal && make metrics && make dashboard
```

## Binding rules (condensed — full text in CLAUDE.md)

- **Never commit on `main`;** branch off `main`, one PR per item, a human merges.
- **Push over HTTPS:** `git push https://github.com/markrthomas/ucie2-pipe7-bridge.git <branch>`
  (SSH auth fails in this env). Remote branch *deletes* are user-run.
- **The byte-identical PyUVM↔SV-UVM per-cycle trace is sacred.** Do not restructure
  `dv/uvm/sv/test/ucie2_roundtrip_test.sv` `run_phase`. RTL timing changes must be
  mirrored in **both** TBs and re-verified with `trace_compare`.
- **`rtl/ucie2_pipe7_pkg.sv` encodings are frozen** unless a Phase I item un-FLAGs
  one (and updates the spec cross-check in the same change).
- **No OSS CAD Suite.** Local box lint/elaborates the UVM tier only; full `--binary`
  runs in CI/Railway/Codespaces.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## When you finish an item

1. Update the queue above (check the box, move ▶) and any un-FLAGged spec rows.
2. Note anything non-obvious for the next session directly in this file.
3. Keep `PLAN.md` §7 Phase I in sync if scope shifts.
