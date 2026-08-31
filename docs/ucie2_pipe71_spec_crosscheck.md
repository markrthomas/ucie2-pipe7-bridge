# UCIe 2.0 (FDI) ↔ PCIe PIPE 7.1 spec cross-check — ERRATA (PLAN Item 0)

> **Status: STUB / NOT STARTED.** This is the Item-0 deliverable. Until it is
> filled in and signed off, **no encoding in `rtl/ucie2_pipe7_pkg.sv` is frozen**
> — every literal there is provisional and marked as such.

## Purpose

Reconcile the scaffold's interface, register map, and encodings against the
controlled specifications, record each verdict (confirmed / corrected), and fold
corrections back into `rtl/ucie2_pipe7_pkg.sv` and the DV models.

## Controlled sources to cross-check against

- **UCIe 2.0** specification — FDI (Flit-Aware Die-to-Die Interface) signal list,
  flit formats, flow control, state machine (lp_state_req / pl_state_sts,
  stallreq/ack), and the UCIe 2.0 management / sideband transport + register model.
- **PIPE 7.1** — Intel PHY Interface for the PCI Express Architecture, Ref 643108
  (MAC-facing signal set, PowerDown/Rate/Width, PhyStatus, RxStatus encodings).
- **PCIe 6.x base** — Gen5 128b/130b block framing and Gen6 PAM4 FLIT framing.

## Cross-check table (to complete)

| # | Item | Scaffold assumption | Spec verdict | Action |
|---|------|---------------------|--------------|--------|
| 0.1 | FDI signal list | representative subset in `ucie2_pipe7_if` | _tbd_ | _tbd_ |
| 0.2 | `FDI_FLIT_W` | 256 | _tbd_ | _tbd_ |
| 0.3 | `PIPE_WIDTH` | 64 | _tbd_ | _tbd_ |
| 0.4 | `pcie_rate_e` Gen5/Gen6 | 3'd4 / 3'd5 (provisional) | _tbd_ | _tbd_ |
| 0.5 | `pipe_pwrdn_e` P0/P0s/P1/P2 | 2'b00..2'b11 | _tbd_ | _tbd_ |
| 0.6 | `fdi_state_e` | reset/active/L1/L2/linkreset/linkerror | _tbd_ | _tbd_ |
| 0.7 | mgmt/sideband register map | not yet defined | _tbd_ | _tbd_ |

## Sign-off

- [ ] All rows resolved; `rtl/ucie2_pipe7_pkg.sv` updated; encodings **frozen**.
