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
- **Phase I in progress. I1 DONE** (FDI link FSM enriched — real RETRAIN training +
  full managed state set; `fdi_state_e` encoding pinned/un-FLAGGED; new control test
  `make link-fsm`; round-trip byte-identical, verified locally: lint/pyuvm/link-fsm/
  lint-uvm all green; full `make uvm`+trace-compare confirmed by CI). **I2 is next.**

## Work queue (tick as you go; ▶ = do next)

Detail for each is in `docs/phase_i_design_completion.md`.

- [x] **I9. Housekeeping** — sync PLAN/README status (landed with the plan PR).
- [x] **I1. FDI link-state FSM + `fdi_state_e` encoding** — done (see above).
- [ ] ▶ **I2. `is_os` derivation + forwarding.**
- [ ] **I5. Active error-injection DV** (RX-inject harness; pairs with I1/I2).
- [ ] **I6. Gen6 PAM4 end-to-end + Gen5↔Gen6 rate switch.**
- [ ] **I3. `pl_flit_cancel` semantics.**
- [ ] **I4. Management/sideband register mapping (UCIe 2.0).**
- [ ] **I7. Constrained-random expansion + functional-coverage closure.**
- [ ] **I8. H3b — full-duplex SV UVM + credit FDI seam + B2B trace gate.**

*(Update the ▶ marker and check boxes here in the same PR that lands each item.)*

## FLAGGED contract items → where they live

Source of truth: `docs/ucie2_pipe71_spec_crosscheck.md` → "FLAGGED items". Un-FLAG
a row in the same change that resolves it.

| Item | FLAGGED at (RTL) | Spec § | Phase I item |
|------|------------------|--------|--------------|
| `fdi_state_e` encoding | `pkg.sv:29`, `ucie2_fdi_link_fsm.sv:10` | §C | I1 |
| `is_os` derivation/forwarding | `ucie2_fdi_ingress.sv:36`, `pkg.sv:56`, `ucie2_pipe7_bridge.sv:283` | §B.1 | I2 |
| `pl_flit_cancel` | `ucie2_fdi_egress.sv:34` | §B | I3 |
| mgmt/sideband reg map | `pkg.sv:132` | §F | I4 |

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
