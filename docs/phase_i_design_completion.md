# Phase I — design completion (spec-fidelity + verification depth)

**Status:** planned (2026-09-16). Work queue and live status: **`docs/AI_RESTART.md`**.
Summary in **`PLAN.md` §7 → Phase I**.

Phases A–H delivered a complete, green environment and a working Gen5 datapath
verified by two cycle-accurate TBs plus B2B integration. Phase I closes the
remaining **design-correctness** gaps: the four deliberately-deferred FLAGGED
contract items, the untested error/recovery paths, the un-exercised Gen6 path,
and the last B2B item (H3b). It subsumes the open `PLAN.md` items **G21+** and
**H3b**.

## Ground rules (every Phase I item obeys these)

1. **The green gate stays green** every commit: `make lint`, `make pyuvm`,
   `make lint-uvm` (see `CLAUDE.md`).
2. **The byte-identical PyUVM↔SV-UVM per-cycle trace is sacred.** Any RTL change
   that alters timing must be mirrored in **both** TBs and re-verified with
   `make uvm` + `make trace-compare` (CI/Railway). Never restructure
   `dv/uvm/sv/test/ucie2_roundtrip_test.sv`'s `run_phase`.
3. **`rtl/ucie2_pipe7_pkg.sv` encodings are frozen** except where a Phase I item
   explicitly un-FLAGs one — and then `docs/ucie2_pipe71_spec_crosscheck.md` is
   updated in the same change (move the row out of "FLAGGED", cite the source).
4. **No OSS CAD Suite.** New DV runs on the existing tiers/toolchain.
5. One PR per item (or per coherent group); branch off `main`; a human merges.

---

## Tier 1 — resolve the FLAGGED contract items (highest design risk)

These are frozen-but-unconfirmed encodings that downstream RTL already builds on
(`docs/ucie2_pipe71_spec_crosscheck.md` → "FLAGGED items"). Each is a place the
design may silently diverge from UCIe 2.0.

### I1. FDI link-state FSM + `fdi_state_e` encoding  ⟵ recommended first
- **Why:** the biggest functional gap. Today `ucie2_fdi_link_fsm.sv` is a
  simplified ACTIVE handshake; real FDI/LPIF **bring-up + retrain sequencing** is
  future work, and the 4-bit `fdi_state_e` encodings are unpinned.
- **Files:** `rtl/ucie2_fdi_link_fsm.sv`, `rtl/ucie2_pipe7_pkg.sv` (§C encodings),
  `lp_state_req`/`pl_state_sts` handling in `rtl/ucie2_pipe7_bridge.sv`; the
  state-driving logic in **both** TBs (`dv/pyuvm/agents/fdi_agent.py`,
  `dv/uvm/sv/fdi_agent/fdi_driver.sv`); `docs/ucie2_pipe71_spec_crosscheck.md` §C.
- **Approach:** pin the encoding to a cited UCIe-2.0/LPIF source (or keep FLAGGED
  with the chosen default explicit); implement RESET→bring-up→ACTIVE→(retrain)→
  ACTIVE with the FDI state-request/status handshake; keep the ACTIVE-steady-state
  timing identical so the existing round-trip trace is unperturbed (new states are
  entered only during bring-up before the sacred trace window).
- **Accept:** both TBs drive/observe the new states; `make pyuvm` + `make uvm` +
  `make trace-compare` green; a directed bring-up/retrain test added; the §C row
  moves out of FLAGGED (or its default is documented as intentional).

### I2. `is_os` derivation + forwarding
- **Why:** ordered-set vs data indication is derived from a placeholder and the
  recovered `is_os` is **not forwarded** to FDI RX
  (`rtl/ucie2_pipe7_bridge.sv:283`).
- **Files:** `rtl/ucie2_fdi_ingress.sv:36`, `rtl/ucie2_pipe7_pkg.sv:56`,
  `rtl/ucie2_pipe7_bridge.sv:283`; both TB monitors + the golden model
  (`dv/common/models/`).
- **Approach:** derive `is_os` from the FDI flit type at ingress; carry it through
  the datapath; forward the recovered bit to FDI RX. Extend the golden model +
  scoreboard to check it. Un-FLAG §B.1.
- **Accept:** OS and data flits interleaved in the stimulus round-trip with `is_os`
  checked end-to-end; trace-compare green; §B.1 un-FLAGged.

### I3. `pl_flit_cancel` semantics
- **Why:** adapter flit-retraction path is unmodelled (`rtl/ucie2_fdi_egress.sv:34`).
- **Files:** `rtl/ucie2_fdi_egress.sv`, `rtl/ucie2_pipe7_pkg.sv`; both TBs
  (a cancel-injecting sequence) + golden model.
- **Approach:** model the cancel handshake on egress (retract an in-flight flit
  before it commits downstream); define the exact cycle semantics and mirror them
  in both TBs. Un-FLAG §B.
- **Accept:** a directed cancel test in both tiers shows the flit is dropped
  cleanly with no downstream corruption; trace-compare green.

### I4. Management/sideband register mapping (UCIe 2.0) — DONE
- **Why:** regfile ↔ UCIe-2.0 management/sideband transport mapping was FLAGGED (§F).
- **Files:** `rtl/ucie2_mgmt_sideband.sv` (new transport), `rtl/ucie2_pipe7_bridge.sv`
  (address demux + management regfile), `rtl/ucie2_pipe7_pkg.sv` (§F opcodes/space),
  `dv/pyuvm/test_mgmt.py` (`make mgmt`), CI + docs.
- **What landed:** `ucie2_mgmt_sideband` is a UCIe-2.0-style management/sideband
  register-access transport — a requester + completer wired back-to-back over an
  on-die serial sideband bus. A controller register request is serialised into a
  sideband packet (`{op, Addr[11:8]}, Addr[7:0], [Data]`; idle = 0x00), the completer
  drives a management register file and returns a completion (`{SB_MGMT_CPL, status},
  [Data]`); a response watchdog bounds the wait. The bridge routes the shared
  `mb_req_*` register-access port by address: the management window
  (`REG_MGMT_BASE` 0x010, decode span 0x010..0x01F) → the sideband transport;
  everything else → the PIPE 7.1 M2P/P2M message bus, **unchanged**. The Gen5
  round-trip issues no register requests, so the sacred trace is byte-identical.
- **Accept (met):** `make mgmt` verifies write/read-back across the 8 backing
  registers, a status-ERR completion for an in-space-but-unbacked address, and a
  PHY-space regression (still routed to the PIPE msgbus). §F un-FLAGged — the last
  of the four FLAGGED contract items. Verified locally: lint / pyuvm / mgmt /
  lint-uvm / formal green.

---

## Tier 2 — verification depth

### I5. Active error-injection DV (subsumes the item-12 "RX-inject wrapper" FLAG and part of G21+)
- **Why:** error handling today is only *passively asserted* ("sync_error never
  fires, deframer locks" — `dv/pyuvm/env.py`, `test_b2b_ucie.py`). The recovery
  logic itself is unverified.
- **Files:** a new RX-inject/error harness under `dv/harness/` (harness-only, not
  `rtl/`, so `make lint` is untouched) + directed error tests in both tiers;
  extend `dv/common/models/` for expected recovery.
- **Scope:** `rx_overflow`, deframer loss-of-lock **and recovery**, RX burst-FIFO
  overflow, sustained backpressure saturation, illegal/mis-aligned sync headers.
- **Accept:** each error is injected, the DUT reacts per spec (flag raised,
  recovers, no silent corruption), and a clean run still passes; error tests are
  gated in CI.

### I6. Gen6 PAM4 end-to-end
- **Why:** item B4 proved only a **Gen5** round-trip; `pipe7_gen6_datapath` is
  present but not driven through the bridge end-to-end.
- **Files:** rate/config plumbing in the TBs (`dv/pyuvm/`, `dv/uvm/sv/`) + golden
  model; possibly a Gen6 vector profile in `dv/common/vectors/gen_vectors.py`.
- **Scope:** a Gen6 round-trip in both TBs, plus a **Gen5↔Gen6 rate switch** test.
- **Accept:** Gen6 round-trip scoreboard-clean in both tiers; rate-switch test
  passes; trace-compare green for the Gen6 path.

### I7. Constrained-random expansion + functional-coverage closure (rest of G21+)
- **Why:** stimulus varies only in length today; coverage bins aren't closed.
- **Files:** `dv/pyuvm/seq_lib/`, `dv/common/models/coverage_model.py`,
  `dv/common/vectors/gen_vectors.py`.
- **Scope:** interleave OS/data, randomized backpressure patterns, state-transition
  sequences; drive toward closing the `cocotb_coverage` bins; keep the shared
  vector byte-identical between tiers.
- **Accept:** `make fcov` coverage rises to the agreed target; new random profiles
  reproducible from a seed and consumed identically by both TBs.

---

## Tier 3 — B2B completion

### I8. H3b — full-duplex SV UVM tier + credit-based FDI seam + B2B trace gate
- **Why:** the last open Phase H item.
- **Files:** `dv/uvm/sv/b2b/` (full-duplex tops/tests mirroring the PyUVM
  `*_fd` variants), FDI-seam credit flow control in the harness/RTL as needed, and
  a byte-identical PyUVM↔SV-UVM per-cycle trace cross-check for the B2B configs.
- **Accept:** full-duplex B2B green in **both** tiers; credit flow control holds
  for long bursts; a B2B trace-compare gate passes.

---

## Tier 4 — housekeeping (landed with this plan)

### I9. Sync status to reality
- `PLAN.md` Phase D/E checkboxes marked done (the SV UVM tier, `trace_compare`,
  Railway image, CI, Codespaces all work); item 20 noted as superseded by the
  Phase F4 metrics/dashboard.
- `README.md` "Status" line updated from "Phase A scaffold" to the real state.
- This is done as part of the plan-landing PR; the deeper Tiers 1–3 follow.

---

## Suggested order

`I9` (housekeeping, in this PR) → **`I1`** (FDI FSM, highest leverage) →
`I2` → `I5` (error injection — pairs naturally with the FSM's new error states) →
`I6` → `I3` → `I4` → `I7` → `I8`. Adjust as findings dictate; keep
`docs/AI_RESTART.md` current as items complete.
