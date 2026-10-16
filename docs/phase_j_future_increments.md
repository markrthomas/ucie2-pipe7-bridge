# Phase J — future increments (uncommitted backlog)

**Status:** tracked backlog (2026-10-16). Summary in **`PLAN.md` §7 → Phase J**;
live work queue + handoff: **`docs/AI_RESTART.md`**.

Phases A–I delivered a complete, green environment with a Gen5 + Gen6 datapath
verified by two cycle-accurate TBs plus B2B integration, and resolved all four
FLAGGED contract items. Phase J is the **tracked backlog** of work that was
deliberately deferred during A–I and previously lived only as scattered inline
notes. **None of it has committed scope** — each item is picked up in its own
separately-approved increment. This doc records, per item, the current state, the
exact files a future session would touch, the acceptance criterion, a rough effort,
and whether it risks the two frozen invariants.

## Ground rules (every Phase J item obeys these)

1. **The green gate stays green** every commit: `make lint`, `make pyuvm`,
   `make lint-uvm` (see `CLAUDE.md`).
2. **The byte-identical PyUVM↔SV-UVM per-cycle trace is sacred.** Never
   restructure `dv/uvm/sv/test/ucie2_roundtrip_test.sv`'s `run_phase`. Any RTL
   timing change must be mirrored in both TBs and re-verified with `make uvm` +
   `make trace-compare` (CI/Railway).
3. **`rtl/ucie2_pipe7_pkg.sv` encodings are frozen.** Only J3 carries any risk of
   touching them, and only if implemented by adding new `fdi_state_e` values —
   prefer the counter-based path that avoids this.
4. New DV runs on the existing tiers/toolchain (except J.B, which is toolchain-gated).
5. One PR per item (or per coherent group); branch off `main`; the repo's auto SOP
   (branch → PR → merge) applies.

---

## J.A — in-env actionable

The local/CI toolchain is sufficient; these can be done and proven from here.

### J1. B2B seam `is_os` threading  ⟵ recommended first
- **Why:** the single-bridge `is_os` path is live (I2: `lp_is_os` → framer →
  deframer → `pl_is_os`), but across the two-bridge seam the flit-type is dropped —
  so OS flits cannot traverse a B2B config.
- **Current state:** all four harnesses tie bridge-A `lp_is_os(1'b0)` and leave
  `pl_is_os()` open; only `seam_pl_data`/`seam_pl_valid` cross A→B. No
  `mid_pl_is_os` observation point. The four `dv/pyuvm/test_b2b_*.py` drive all-data
  stimulus (no `is_os` references). (`dv/harness/b2b_pcie_ucie_pcie.sv:62,67,133,138`
  and the three siblings `b2b_ucie_pcie_ucie.sv`, `b2b_{pcie_ucie_pcie,ucie_pcie_ucie}_fd.sv`.)
- **Files:** `dv/harness/b2b_*.sv` (add `seam_pl_is_os`: A `pl_is_os` → B `lp_is_os`;
  expose `mid_pl_is_os`); `dv/uvm/sv/b2b/b2b_pcie_seam_monitor.sv`,
  `b2b_ucie_mid_monitor.sv`; `dv/common/models/{b2b_trace_format,framing_model}.py`;
  `dv/pyuvm/test_b2b_*.py` (interleaved OS/data stimulus + per-flit flit-type check).
- **Reuse:** the single-bridge `dv/pyuvm/test_is_os.py` + `make is-os` pattern as the
  per-bridge reference.
- **Acceptance:** interleaved OS/data round-trips through both bridges with the
  recovered flit-type matching end to end; existing all-data B2B tests unchanged.
- **Effort:** small-medium. **No frozen-pkg / no sacred-trace impact** (harnesses are
  outside `rtl/`; B2B has no byte-identical trace gate on the PyUVM side).

### J2. Directed msgbus transaction test (new)
- **Why:** `rtl/pipe7_msgbus_master.sv` (7-state M2P master, watchdog
  `TIMEOUT_CYCLES=1024`) is only incidentally exercised — a PHY-space read in
  `dv/pyuvm/test_mgmt.py` and a sweep in `test_fcov.py`. Write-uncommitted,
  write-committed+ack, and the watchdog-timeout/`rsp_error` path are never directly
  driven.
- **Files:** a new `dv/pyuvm/test_msgbus.py` + `make msgbus` target; a reusable P2M
  responder (promote the inline responders in `test_mgmt`/`test_fcov` into
  `dv/common/models/ctrl_plane_model.py`).
- **Acceptance:** each transaction kind drives correct M2P framing bytes and the
  expected `rsp_valid/rsp_is_read/rsp_rdata/rsp_error`, including the timeout path.
- **Effort:** small. **Control-plane only — no frozen-pkg / no sacred-trace impact.**

### J3. Cold multi-phase link-training bring-up
- **Why:** `rtl/ucie2_fdi_link_fsm.sv` is today a fast RESET→ACTIVE handshake that
  assumes the PHY is already trained (header comment); the sacred round-trip only
  ever requests ACTIVE, so training phases are never exercised.
- **Current state:** all 8 `fdi_state_e` states are reachable and RETRAIN is already
  real multi-cycle (`RETRAIN_CYCLES`, auto-return to ACTIVE); what's missing is the
  intermediate RESET→(training phases)→ACTIVE sequencing and PHY-training handshake
  modeling (`lp_clk_ack` is observed-only).
- **Files:** `rtl/ucie2_fdi_link_fsm.sv` (training sub-states or a training-phase
  counter analogous to the RETRAIN counter); `dv/pyuvm/test_link_fsm.py` (extend the
  control-plane coverage); `formal/ucie2_fdi_link_fsm_formal.sv` if new properties.
- **Acceptance:** a cold bring-up walks the training phases to ACTIVE; the existing
  fast-ACTIVE path and RETRAIN auto-return still pass; round-trip stays byte-identical.
- **Effort:** medium. **No sacred-trace impact** (control-plane; fast path preserved).
  ⚠ **Frozen-pkg risk only if new `fdi_state_e` encodings are added** — prefer a
  counter-based approach reusing existing states; if encodings must change, un-FLAG
  the `docs/ucie2_pipe71_spec_crosscheck.md` §C row in the same PR.

### J4. Line-coverage floor gate
- **Why:** the advisory `[COV] line=NN.N%` tier has no enforced floor (noted at
  `docs/phase_f_env_enhancements.md:54-55`, pending an agreed baseline).
- **Files:** the coverage driver/target invoked by `make coverage` + its CI step.
- **Acceptance:** CI fails if line coverage drops below the agreed `NN%`; the tier
  stays **post-gate** (never folded into the green gate).
- **Effort:** small. No frozen-pkg / no sacred-trace impact.

---

## J.B — toolchain-gated

These need an environment this host and the light CI job lack; they build/prove only
where the from-source UVM Verilator (or a commercial sim) lives.

### J5. `make waves-uvm` / `wave-uvm`
- **Why:** the PyUVM wave path (`make wave`/`wave-web`, off-gate) exists, but the SV
  UVM env has no wave target — its `--binary` build needs a from-source UVM-capable
  Verilator ≥5.050, absent here and in light CI (`README.md:408-412`,
  `docs/phase_g_env_enhancements.md:575-584`).
- **Files:** an `` `ifdef WAVES `` `$dumpfile` hook in the SV UVM TB keyed off the
  already-reserved `-DWAVES` Verilator define; new `waves-uvm`/`wave-uvm` targets.
- **Acceptance:** an FST/VCD dump is produced and viewed where the UVM Verilator
  lives (Railway/Docker heavy image); off-gate, never compiled into the sacred build.
- **Effort:** medium — gated on toolchain availability, not logic.

### J6. VCS/Xcelium mirror actual run
- **Why:** `dv/uvm/vcs` is authored + review-validated but never executed here (no
  commercial simulator) — `PLAN.md` item 16 (`[~]`), `docs/verification_plan.md:14`.
- **Acceptance:** the mirror compiles and runs on a licensed VCS/Xcelium; stays `[~]`
  until then.
- **Effort:** gated on tool access.

---

## J.C — SV-tier parity follow-ups

Non-blocking parity gaps noted in `docs/phase_d_swarm.md:154-158`.

### J7. SV `mgmt_agent` (ctrl/msgbus)
- **Why:** control/msgbus sweep tests are PyUVM-only today; the SV UVM env has no
  ctrl/msgbus agent.
- **Acceptance:** SV-UVM ctrl-sweep tests reach parity with the PyUVM control-plane
  coverage. **Effort:** medium.

### J8. SV framing model
- **Why:** PyUVM already does a 3-way scoreboard; the SV side relies on
  `trace_compare` for the framing cross-check. A native SV framing model would give
  true 3-way SV scoreboard parity.
- **Acceptance:** the SV scoreboard checks framing directly (not only via
  `trace_compare`). **Effort:** medium.

---

## J.D — uncommitted stretch

### J9. Deeper/unbounded formal — k-induction on the gearbox
- **Why:** `formal/pipe7_gearbox.sby` is `mode bmc depth 12` (deliberately shallow —
  the deframer's ~470-bit accumulator makes deep BMC expensive). An unbounded proof
  would close the accumulator invariant for all time, not just a bounded horizon.
- **Files:** `formal/pipe7_gearbox_formal.sv` (strengthen the T3 accumulator
  invariant to be inductive), `formal/pipe7_gearbox.sby` (`mode prove`/k-induction);
  `rtl/` untouched (formal reads a transformed copy via `tools/formal_prep.py`).
- **Acceptance:** an unbounded `prove`/k-induction passes on the gearbox accumulator
  invariant. **Effort:** medium-large (real proof-engineering on a 470-bit state).
  Off-gate, additive; no frozen-pkg / no sacred-trace impact.
