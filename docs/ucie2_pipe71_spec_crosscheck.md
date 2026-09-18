# UCIe 2.0 (FDI) ↔ PCIe PIPE 7.1 spec cross-check — ERRATA (PLAN Item 0)

> **Status: COMPLETE — encodings FROZEN (2026-08-31).** Every literal in
> `rtl/ucie2_pipe7_pkg.sv` is now either spec-cited below or carries a matching
> `// FLAGGED:` comment. Downstream RTL (Phase B) may build on these.

## Method

- **PIPE 7.1 MAC side (reuse):** the encodings are identical to the predecessor
  `~/proj/ucie_rdi_to_pcie6_pipe7`, whose Item 0 reconciled them against the
  controlled **Intel PIPE 7.1, Ref 643108, Rev 7.1 (Sep 2025)**. We re-cite its
  `docs/pipe71_spec_crosscheck.md` and `src/pipe7_pkg.sv` rather than re-derive.
- **UCIe 2.0 FDI side (new, public research):** sourced from public UCIe material —
  the UCIe consortium overview decks, the design-reuse/ChipInterfaces D2D-adapter
  deep-dive, and the open-source **`ucb-bar/uciedigital`** FDI implementation (a
  concrete signal-level reference). UCIe 2.0 is a superset of 1.1 on FDI; the FDI
  signal set and flit framing below are 1.1/2.0-common. Items not confirmable from
  public sources are implemented to a reasonable default and **FLAGGED**.
- **PCIe 6.x framing (reuse):** Gen5 128b/130b block and Gen6 PAM4 FLIT, as locked
  by the predecessor's PIPE cross-check (MAC-owned 128b/130b; Gen6 = wide data, no
  sync header).

## Sources

- UCIe overview / usage models (HotChips 2023 tutorial), UCIe Consortium.
- design-reuse / ChipInterfaces, "UCIe D2D Adapter Explained: Architecture, Flit
  Mapping, Reliability, and Protocol Multiplexing."
- `ucb-bar/uciedigital` FDI/RDI interface docs (DeepWiki) — concrete FDI signal
  names/widths and the 512-bit-flit / 128-bit-transfer mapping.
- Predecessor `docs/pipe71_spec_crosscheck.md` + `src/pipe7_pkg.sv` (PIPE 7.1,
  Intel Ref 643108).

---

## A. Scope (locked, PLAN §2 — not reopened here)

UCIe 2.0 **FDI** controller-facing · PIPE 7.1 **MAC-facing** · Gen5 (Rate=4,
128b/130b) + Gen6 (Rate=5, PAM4 FLIT) · MAC-facing only (no PHY internals).

## B. FDI signal list (controller-facing) — the bridge's UCIe-side boundary

`lp_*` = driven by the Protocol Layer (into the bridge). `pl_*` = driven by the
bridge (adapter side) toward the Protocol Layer. Confirmed against `uciedigital`
and the D2D-adapter deep-dive; state encodings and flit-type mapping are FLAGGED.

| Signal | Dir (bridge) | Width | Meaning | Verdict |
|--------|--------------|-------|---------|---------|
| `lp_data`      | in  | `FDI_DW` | flit/stream payload word | confirmed (`lpData.bits = 8×width`) |
| `lp_valid`     | in  | 1 | `lp_data` valid | confirmed |
| `lp_irdy`      | in  | 1 | protocol layer ready to transfer | confirmed |
| `lp_is_os`     | in  | 1 | TX flit-type: 1 = ordered-set block, 0 = data | added Phase I I2 (§B.1) |
| `pl_trdy`      | out | 1 | adapter ready to accept a transfer | confirmed |
| `pl_data`      | out | `FDI_DW` | received flit/stream payload | confirmed |
| `pl_valid`     | out | 1 | `pl_data` valid (RX has **no** backpressure) | confirmed |
| `pl_is_os`     | out | 1 | recovered RX flit-type, valid with `pl_valid` | added Phase I I2 (§B.1) |
| `pl_flit_cancel`| out | 1 | adapter retracts a flit in flight | RESOLVED (Phase I I3): asserted with `pl_valid` to retract a flit recovered through an RX error (FIFO overflow) |
| `lp_state_req` | in  | 4 | requested link state (`fdi_state_e`) | confirmed signal; **FLAGGED** encoding |
| `pl_state_sts` | out | 4 | current link state (`fdi_state_e`) | confirmed signal; **FLAGGED** encoding |
| `lp_linkerror` | in  | 1 | protocol layer flags link error | confirmed |
| `pl_stallreq`  | out | 1 | adapter requests protocol stall (for state change) | confirmed |
| `lp_stallack`  | in  | 1 | protocol layer acks stall | confirmed |
| `lp_rx_active_req` | in  | 1 | request Rx active | confirmed (rx_active handshake) |
| `pl_rx_active_sts` | out | 1 | Rx active status | confirmed |
| `pl_clk_req`   | out | 1 | adapter clock request | confirmed (`pl_clk_req`/`lp_clk_ack`) |
| `lp_clk_ack`   | in  | 1 | protocol layer clock ack | confirmed |
| `lp_wake_req`  | in  | 1 | wake request | confirmed |
| `pl_wake_ack`  | out | 1 | wake ack | confirmed |

Config/sideband (`lp_cfg`/`pl_cfg` credit) exists on FDI but the bridge routes
config over the UCIe 2.0 management/sideband + msgbus loop (§F); the FDI cfg
channel is **out of scope for Item 0** and not brought to the boundary.

### B.1 Flit ↔ internal block mapping (the key datapath contract)
- UCIe flits are transferred on FDI as `FDI_DW`-bit words. `uciedigital` uses
  **128-bit FDI transfers** (a 512-bit flit = 4 transfers). We adopt
  **`FDI_DW = 128`** so **one FDI transfer maps 1:1 onto the datapath's internal
  128-bit block** `{is_os, data128}` — the contract every downstream block already
  speaks (predecessor `pipe7_rdi_ingress`→framer). This is the "most logical path."
- **`FDI_FLIT_BYTES = 256`** (standard UCIe flit) ⇒ 16 transfers/flit at 128b.
- **`is_os` derivation — RESOLVED (Phase I I2):** the bridge takes a per-transfer
  FDI flit-type input `lp_is_os` (1 = ordered-set block, 0 = data), maps it 1:1 onto
  the block's `is_os` bit at ingress, and the framer turns it into the OS vs data
  sync header. On RX the deframer recovers the bit from the sync header and the
  bridge forwards it on a new FDI RX output `pl_is_os` (valid with `pl_valid`).
  Existing all-data stimulus drives `lp_is_os = 0`, so the round-trip is unchanged;
  `make is-os` drives interleaved OS/data and checks the recovered flit-type per
  flit. (The specific FDI-level indicator remains an implementation choice.)

## C. FDI link states — `fdi_state_e` (encoding RESOLVED, Phase I I1)

LPIF/FDI-style states. The state *set* is spec-aligned:

`RESET`, `ACTIVE`, `L1`, `L2`, `LINKRESET`, `LINKERROR`, `RETRAIN`, `DISABLED`.

LPIF defines the state set but leaves the wire **encoding** to the implementation,
so the 4-bit values in `ucie2_pipe7_pkg.sv` are **pinned as an implementation-
defined, stable (ABI) encoding** (`RESET=0, ACTIVE=1, L1=2, L2=3, LINKRESET=4,
LINKERROR=5, RETRAIN=6, DISABLED=7`): `RESET=0` so a reset lands in it, `ACTIVE=1`,
low-power next, management/error last. No longer FLAGGED — decided and documented.
The FSM (`ucie2_fdi_link_fsm`) implements bring-up (fast RESET→ACTIVE), a real
multi-cycle **RETRAIN** (auto-returns to ACTIVE), the low-power / LINKRESET /
DISABLED managed states, and sticky LINKERROR with request-driven recovery,
verified by `dv/pyuvm/test_link_fsm.py` (`make link-fsm`). A cold multi-phase
training bring-up remains a documented future increment.

## D. PowerDown / Rate / Width (PIPE 7.1 — reused, spec-cited)

Verbatim from predecessor `pipe7_pkg.sv` (Intel Ref 643108, Tables 6-5/6-16):

- `powerdown_e[3:0]`: P0=0, P0s=1, P1=2, P2=3 (4–15 PHY-specific L1 substates).
- `rate_e[3:0]`: 2.5=0, 5.0=1, 8.0=2, 16.0=3, **Gen5=4, Gen6=5**, 128=6.
- `width_e[2:0]` (Tx `Width` / Rx `RxWidth`): 10=0, 20=1, 40=2, 80=3, 160=4.
- Rate/Width change legal only in P0/P1 with TxElecIdle asserted; PhyStatus pulse
  completes a change; timeout is PHY-specific → parameterized.

## E. PIPE 7.1 MAC signal set (reused, spec-cited)

MAC-owned (bridge→PHY) and PHY-owned (PHY→bridge) lists per predecessor
`test/uvm/pipe7_mac_if.sv` and `docs/pipe71_spec_crosscheck.md`. The bridge shell
brings the load-bearing subset to its boundary (TxData/TxDataValid, PowerDown,
Rate, Width/RxWidth, TxElecIdle, TxDetectRx; RxData/RxValid, PhyStatus, RxStatus,
RxElecIdle, M2P/P2M msgbus). SerDes architecture ⇒ **no** discrete block-coding
pins (TxSyncHeader/TxStartBlock/TxDataK/RxDataValid/…); the 2-bit sync header is
embedded in TxData/RxData. Gen6 = wide data, no 128b/130b sync header.

## F. Message bus + register map (PIPE 7.1 — reused, spec-cited)

- `msgbus_cmd_e[3:0]`: NOP=0, WRITE_UNCOMMIT=1, WRITE_COMMIT=2, READ=3,
  READ_COMPLETION=4, WRITE_ACK=5.
- `MB_BUS_WIDTH=8`, `MB_ADDR_WIDTH=12`, `MB_DATA_WIDTH=8`; idle=0x00; one
  outstanding txn; committed write blocks until write_ack.
- `REG_PHY_TX_CTRL_BASE=0x400`..`0x40A`; `REG_PHY_PAM4_RESTRICTED_LEVELS=0x406`
  (sub-offset is a working value, not spec-pinned — same caveat as predecessor).
- **UCIe 2.0 management/sideband — RESOLVED (Phase I I4):** UCIe 2.0 standardizes a
  management transport + register access over sideband. The register file is now
  mapped onto that transport: `ucie2_mgmt_sideband` serialises a register access
  into a UCIe-2.0-style **sideband packet** (`{op, Addr[11:8]}, Addr[7:0], [Data]`;
  idle bus = 0x00, opcodes `SB_MGMT_RD/WR`, completion `{SB_MGMT_CPL, status}, [Data]`)
  and completes it against a local **management register window** (`REG_MGMT_BASE`
  0x010, 8 backing regs; a wider decode span 0x010..0x01F returns a well-formed
  status-ERR completion for unbacked addresses). The bridge routes the shared
  controller register-access port (`mb_req_*`) by address: management space →
  sideband transport, everything else → the PIPE 7.1 M2P/P2M message bus (the
  MAC↔PHY config plane, unchanged). Verified by `dv/pyuvm/test_mgmt.py`
  (`make mgmt`): write/read-back, the unbacked-address error, and a PHY-space
  regression. Exact UCIe-2.0 management address map / packet bit-positions are
  implementation-defined here (the SET of opcodes + the addr/data mapping is pinned).

## G. Gen5 128b/130b framing (PCIe 6.x — reused, spec-cited)

`SYNC_HDR_BITS=2`, `BLOCK_PAYLOAD=128`, `BLOCK_BITS=130`, `SYNC_HDR_DATA=2'b10`,
`SYNC_HDR_OS=2'b01`. MAC-owned in the SerDes architecture. Gen6 carries no sync
header (1b/1b wide data); PAM4 precoding is PHY-side; MAC's only knob is
`PAM4RestrictedLevels`.

---

## Cross-check resolution (was rows 0.1–0.7)

| # | Item | Frozen value | Basis |
|---|------|--------------|-------|
| 0.1 | FDI signal list | §B table | confirmed (uciedigital / D2D deep-dive) |
| 0.2 | `FDI_DW` / flit map | 128b transfer, 256B flit, 1:1 to block | §B.1 (uciedigital) + design choice |
| 0.3 | PIPE geometry | widths 10/20/40/80/160; shell `PIPE_WIDTH` default 80 | §D/§E (Ref 643108) |
| 0.4 | `rate_e` Gen5/Gen6 | 4 / 5 | §D (Ref 643108) |
| 0.5 | `powerdown_e` | P0..P2 = 0..3 | §D (Ref 643108) |
| 0.6 | `fdi_state_e` | 8-state set; encoding pinned (impl-defined, Phase I I1) | §C |
| 0.7 | register map | PIPE msgbus loop + UCIe-2.0 mgmt/sideband transport (Phase I I4) | §F |

## FLAGGED items (implemented, not spec-confirmed — revisit)
1. ~~`fdi_state_e` numeric encodings (§C).~~ **RESOLVED (Phase I I1)** — pinned as an
   implementation-defined stable encoding; LPIF leaves the wire encoding to the
   implementation. See §C.
2. ~~`is_os` derivation from FDI flit type (§B.1).~~ **RESOLVED (Phase I I2)** — FDI
   `lp_is_os` input drives it at ingress; recovered bit forwarded on `pl_is_os`. See §B.1.
3. ~~`pl_flit_cancel` semantics/handling (§B).~~ **RESOLVED (Phase I I3)** — the adapter
   asserts it with `pl_valid` to retract a flit recovered through an RX FIFO overflow
   (per-block error carried on the RX CDC error channel). See §B.
4. ~~Register file ↔ UCIe 2.0 management/sideband transport mapping (§F).~~
   **RESOLVED (Phase I I4)** — the register file is mapped onto a UCIe-2.0-style
   management/sideband packet transport (`ucie2_mgmt_sideband`) with its own
   management register window; the bridge routes `mb_req_*` by address space. See §F.

**All four FLAGGED contract items are now resolved.** The `rtl/ucie2_pipe7_pkg.sv`
encodings remain frozen (the I4 additions are new management-transport types/params,
not changes to existing encodings).

## Sign-off
- [x] All rows resolved; `rtl/ucie2_pipe7_pkg.sv` updated; encodings **frozen**;
      every literal cited or FLAGGED.
