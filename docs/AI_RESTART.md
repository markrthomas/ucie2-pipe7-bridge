# AI restart — resume here (Phase I done; Phase J backlog)

**Purpose:** the one file to read when (re)starting an AI session. It is the live
handoff: current state, the ordered work queue with status, where everything
lives, and the exact commands + rules. **Phases A–I are complete; the live work is
the Phase J backlog below.** Keep it current — tick items and move the ▶ marker as
work lands.

> If you are a fresh session: read in this order — **`CLAUDE.md`** (constraints) →
> **`PLAN.md` §7 Phase J** (backlog summary) → **this file** (live status) →
> **`docs/phase_j_future_increments.md`** (per-item detail; `docs/phase_i_design_completion.md`
> for the now-complete Phase I). Then `make help`.

---

## Current state (as of 2026-10-16)

- Env is complete and **green**: RTL datapath (Gen5 proven end-to-end), two
  cycle-accurate TBs (PyUVM + SV UVM), `trace_compare`, coverage, formal,
  metrics/dashboard, waves, CI, Railway + Codespaces remote runners.
- `make uvm` is the single canonical SV UVM gate (CI + the container run it); you
  can offload it from a laptop with `make uvm-remote [RUNNER=railway|codespace]`.
- **Phase I COMPLETE. I1–I9 all landed — all four FLAGGED items resolved; I8/H3b closed.**
  I7: `make fcov` closed to honest 100% (39→53 bins) — seeded CRV + injected error paths.
  I4: UCIe-2.0 management/sideband register-access transport (`ucie2_mgmt_sideband`,
  `make mgmt`; §F un-FLAGged). I1: FDI link FSM (RETRAIN +
  managed states, encoding pinned, `make link-fsm`). I2: FDI `lp_is_os`/`pl_is_os`
  flit-type, `make is-os`. I5 (core): RX error-injection `make err-inject` (sync_error
  + loss-of-lock + re-lock). I6: Gen6 end-to-end + Gen5→Gen6 rate switch `make gen6`
  (bridge routes the FDI block into the Gen6 raw path, gated by rate; built at PW=160).
  I3: `pl_flit_cancel` retracts flits recovered through an RX FIFO overflow
  (`make flit-cancel`, PW=160; also delivered the deferred rx_overflow injection).
  Each byte-identical in Gen5, verified locally (lint/pyuvm/link-fsm/is-os/err-inject/
  gen6/flit-cancel/mgmt/lint-uvm/formal); full `make uvm`+trace-compare confirmed by CI.
  I7: `make fcov` closed to honest 100% (39→53 bins) with seeded CRV + error injection.
  **I8 DONE — Phase I complete (I1–I9 all landed).** I8a+I8b: full-duplex SV UVM UCIe
  (`tb_b2b_ucie_fd`) and PCIe (`tb_b2b_pcie_fd`) tiers, mirroring PyUVM `test_b2b_ucie_fd`
  / `test_b2b_pcie_fd`; both in `uvm-b2b`+CI. I8c: byte-identical B2B trace-compare gate —
  both fd TBs emit the shared `b2b_trace_format` per-cycle boundary trace and
  `make trace-compare-b2b` diffs PyUVM vs SV-UVM per tier (CI-gating). I8d: the conditional
  credit FDI seam is **not needed** — the seam is rate-matched and RX-no-backpressure is a
  frozen crosscheck-B decision, so credits would contradict the contract; `make b2b-longburst`
  (32×-default burst through both fd tiers, full recovery + no sync_error) is the standing
  CI guard. All four FLAGGED contract items resolved; `ucie2_pipe7_pkg.sv` stays frozen.

## Work queue — Phase J backlog (tick as you go; ▶ = do next)

**Phase I is complete** (I1–I9 all landed; detail in
`docs/phase_i_design_completion.md`). The live queue below is **Phase J — future
increments**, the tracked backlog of deliberately-deferred work. **None has
committed scope.** Per-item detail (current state, files, acceptance, risk) is in
**`docs/phase_j_future_increments.md`**; summary in `PLAN.md` §7 → Phase J.

*J.A — in-env actionable:*
- [ ] ▶ **J1. B2B seam `is_os` threading** — thread the recovered `pl_is_os` across
  the two-bridge seam (A→B `lp_is_os`, currently tied `1'b0`), expose `mid_pl_is_os`,
  carry the flit-type in the B2B monitors + Python models, drive interleaved OS/data.
  Small-medium; no frozen-pkg / no sacred-trace impact. **Recommended first.**
- [ ] **J2. Directed msgbus transaction test** (new) — `make msgbus` covering
  `pipe7_msgbus_master` write-uncommitted / write-committed+ack / watchdog-timeout.
  Small, control-plane only.
- [ ] **J3. Cold multi-phase link-training bring-up** — cold RESET→(training)→ACTIVE
  in `ucie2_fdi_link_fsm` (prefer counter-based to avoid touching frozen `fdi_state_e`);
  extend `test_link_fsm.py`. Medium.
- [ ] **J4. Line-coverage floor gate** — enforce `>= NN%` in the post-gate `[COV]`
  tier once a baseline is agreed. Small.

*J.B — toolchain-gated (needs an env this host / light CI lacks):*
- [ ] **J5. `make waves-uvm` / `wave-uvm`** — `` `ifdef WAVES `` `$dumpfile` hook in
  the SV UVM TB (reserved `-DWAVES`); build/prove where the UVM Verilator lives.
- [~] **J6. VCS/Xcelium mirror actual run** — run the authored `dv/uvm/vcs` on a
  licensed simulator; stays `[~]` until one is available.

*J.C — SV-tier parity follow-ups (non-blocking):*
- [ ] **J7. SV `mgmt_agent` (ctrl/msgbus)** — SV parity for the PyUVM-only ctrl sweeps.
- [ ] **J8. SV framing model** — native SV framing for true 3-way scoreboard parity.

*J.D — uncommitted stretch:*
- [ ] **J9. Deeper/unbounded formal — k-induction on the gearbox** — strengthen the
  T3 accumulator invariant to close an unbounded proof beyond the shallow bounded BMC.

*(Update the ▶ marker and check boxes here in the same PR that lands each item.)*

## FLAGGED contract items → where they live

Source of truth: `docs/ucie2_pipe71_spec_crosscheck.md` → "FLAGGED items". Un-FLAG
a row in the same change that resolves it.

| Item | Spec § | Phase I item | Status |
|------|--------|--------------|--------|
| `fdi_state_e` encoding | §C | I1 | ✅ resolved |
| `is_os` derivation/forwarding | §B.1 | I2 | ✅ resolved |
| `pl_flit_cancel` | §B | I3 | ✅ resolved |
| mgmt/sideband reg map (`ucie2_mgmt_sideband`, `pipe7_regfile`) | §F | I4 | ✅ resolved (last one) |

**All four FLAGGED contract items are resolved.** `rtl/ucie2_pipe7_pkg.sv` stays frozen.

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
- **Local box** lint/elaborates the UVM tier only; full `--binary`
  runs in CI/Railway/Codespaces.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## When you finish an item

1. Update the queue above (check the box, move ▶) and any un-FLAGged spec rows.
2. Note anything non-obvious for the next session directly in this file.
3. Keep `PLAN.md` §7 Phase I in sync if scope shifts.
