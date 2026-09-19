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

### I7. Constrained-random expansion + functional-coverage closure — DONE
- **Why:** stimulus varied only in length; coverage bins (notably the error paths)
  were not closed.
- **Files:** `dv/pyuvm/test_fcov.py`, `dv/common/models/coverage_model.py`, CI + docs.
- **What landed:** the `make fcov` driver gained **seeded constrained-random**
  stimulus (reproducible via `FCOV_SEED`): random payloads (`gen_vectors` random
  profile), OS/data flit-type interleave, and randomised FDI backpressure bubbles.
  New coverage points close the two previously-FLAGGED error-status bins —
  `sync_error=1` (a run of illegal PIPE-RX sync headers → loss of block lock) and
  `rx_overflow=1` (re-feeding legal blocks while the FDI drain is stalled overflows
  the RX CDC + depth-4 burst FIFO) — and add `is_os` flit-type + the full 8-state
  `fdi_state_e` link space (a directed link-state sweep). This also delivers the
  `rx_overflow`/backpressure active-injection deferred from I5/I6.
- **Accept (met):** functional coverage rises **39 → 53 bins, honest 100%** (error
  paths included), reproducible across seeds (verified `FCOV_SEED=0xC0FFEE` and
  `0x1234`). `make fcov` gated in CI on the independent Icarus engine.

---

## Tier 3 — B2B completion

### I8. H3b — full-duplex SV UVM tier + credit-based FDI seam + B2B trace gate *(staged)*
- **Why:** the last open Phase H item.
- **Files:** `dv/uvm/sv/b2b/` (full-duplex tops/tests mirroring the PyUVM
  `*_fd` variants), FDI-seam credit flow control in the harness/RTL as needed, and
  a byte-identical PyUVM↔SV-UVM per-cycle trace cross-check for the B2B configs.
- **Accept:** full-duplex B2B green in **both** tiers; credit flow control holds
  for long bursts; a B2B trace-compare gate passes.
- **Staging (only local-lintable; the `--binary` SV UVM run is CI-only, so this
  large item lands in reviewable increments):**
  - **I8a — DONE.** Full-duplex SV UVM **UCIe** tier: new `b2b_ucie_fd_if`, a *sided*
    driver (`is_b`) + monitor (`at_b`) so one class serves both directions, a
    dual-direction scoreboard, `b2b_ucie_fd_uvm_pkg` + `tb_b2b_ucie_fd`, on the
    existing `b2b_ucie_pcie_ucie_fd` harness. Mirrors the green PyUVM
    `test_b2b_ucie_fd` (forward A→B + reverse B→A round-trip the shared vector; both
    bridges lock, no sync_error). Wired: `lint-b2b-ucie-fd` + `run-b2b-ucie-fd` in the
    vlt Makefile (fanned into `lint-b2b`/`run-b2b`, so `lint-b2b-uvm`/`uvm-b2b` + CI
    pick it up). Lint-elaborates locally; `--binary` run gated in CI.
  - **I8b — DONE.** Full-duplex SV UVM **PCIe** tier: new `b2b_pcie_fd_if`, a *sided*
    driver (`is_b`, injects A or B PIPE RX) + monitor (`fwd`, recovers the far PIPE TX
    and tracks that direction's deframer health), a dual-direction scoreboard,
    `b2b_pcie_fd_uvm_pkg` + `tb_b2b_pcie_fd`, on the existing `b2b_pcie_ucie_pcie_fd`
    harness. Mirrors the green PyUVM `test_b2b_pcie_fd` (forward A→B + reverse B→A each
    re-frame the shared pre-framed word vector; both bridges lock, no sync_error). Wired:
    `lint-b2b-pcie-fd` + `run-b2b-pcie-fd` in the vlt Makefile (fanned into
    `lint-b2b`/`run-b2b`, so `lint-b2b-uvm`/`uvm-b2b` + CI pick it up). Lint-elaborates
    locally; `--binary` run gated in CI.
  - **I8c — DONE.** Byte-identical **B2B trace-compare gate** (PyUVM↔SV-UVM per-cycle,
    both full-duplex tiers) — the deferred H3 byte-identical B2B trace. New shared column
    contract `dv/common/models/b2b_trace_format.py` (`PCIE_FD_COLUMNS`: both bridges'
    PIPE TX outputs + lock/error; `UCIE_FD_COLUMNS`: both bridges' recovered FDI RX
    outputs + FDI handshake/status). Both full-duplex TBs now emit one line per PCLK of
    **both** bridges' observable outputs, sampled on the coincident 2 ns edge (PyUVM
    post-edge reads == SV `#0.1`): PyUVM `test_b2b_{ucie,pcie}_fd.py` write
    `dv/pyuvm/build/b2b_*_fd.trace`; the SV UVM `b2b_{ucie,pcie}_fd_test.sv` write via
    `+B2B_TRACE=<path>` under `dv/uvm/vlt/obj/b2b_*_fd/`. `make trace-compare-b2b` runs
    `tools/trace_compare.py` per tier (added to CI after `make b2b`/`make uvm-b2b`,
    GATING; traces uploaded as artifacts). No RTL, no sacred single-bridge emitter, and
    no `bridge.trace` touched (distinct filenames). PyUVM traces well-formed + lint-clean
    locally; the byte-identical diff runs in CI (SV `--binary`).
  - **I8d — open.** Credit-based FDI seam, if long-burst flow control needs it (the
    current ready/valid FDI-TX backpressure holds for the vector-length bursts today).

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
