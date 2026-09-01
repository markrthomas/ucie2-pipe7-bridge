// -----------------------------------------------------------------------------
// ucie2_pipe7_sva — bound SystemVerilog assertions on the bridge boundary
// (Phase F increment 1, deferred from PLAN item 9).
//
// A checker module bound into `ucie2_pipe7_bridge`.  It contains NO logic and
// drives nothing: it only observes the boundary ports and asserts properties
// that must hold for the directed Gen5 round-trip.  There are deliberately no
// RTL edits — the bind at the bottom of this file attaches it to every
// ucie2_pipe7_bridge instance.
//
// Where it runs:
//   * `make lint-uvm`  — elaborated (compiled) with the SV UVM env.
//   * `make uvm`       — the `--binary` build/run CHECKS the properties
//                        (dv/uvm/vlt/Makefile passes `--assert`).  CI/Railway.
// It is deliberately NOT added to `rtl/` — the root `make lint`, `make pyuvm`
// and `make fcov` source lists are `$(wildcard rtl/*.sv)`, so putting it there
// would silently pull SVA into the Icarus functional-coverage tier and perturb
// the existing (sacred, byte-identical) gate.  This file is additive: it is
// listed only in dv/uvm/vlt/Makefile.
//
// Two clock domains are observed: pclk (PIPE side) and lclk (FDI side).  Each
// property names its own clock and is disabled during that domain's reset.
//
// FLAGGED for a human (see the a_no_tx_while_elec_idle comment): the bridge's
// TxElecIdle mux makes the unqualified PIPE rule "TxDataValid low whenever
// TxElecIdle is asserted" false while the control FSM is `busy`.  The assertion
// below is qualified with `!busy` so it is a true invariant rather than a guess.
// -----------------------------------------------------------------------------
`default_nettype none

// SYNCASYNCNET: the `disable iff (!rst_n)` qualifiers read the same reset nets the
// RTL uses asynchronously. That is the standard way to reset-qualify an assertion
// and implies no synchronous reset flop, so suppress the (-Wall-only) warning here
// rather than weakening the RTL lint. Verified: with this off, RTL + this file
// pass `verilator --lint-only -Wall -sv --timing --assert`.
/* verilator lint_off SYNCASYNCNET */
module ucie2_pipe7_sva (
  // ---- Clocks / resets ----
  input wire        lclk,
  input wire        lclk_rst_n,
  input wire        pclk,
  input wire        pclk_rst_n,

  // ---- PIPE 7.1 Tx (pclk) ----
  input wire        tx_data_valid,
  input wire [3:0]  tx_elec_idle,
  input wire        busy,

  // ---- Bridge status (pclk) ----
  input wire        block_locked,
  input wire        sync_error,
  input wire        rx_overflow,

  // ---- FDI link-state handshake (lclk) ----
  input wire [3:0]  lp_state_req,
  input wire [3:0]  pl_state_sts,
  input wire        lp_linkerror,
  input wire        pl_stallreq,
  input wire        lp_stallack
);

  // ===========================================================================
  // P1 — TxDataValid is never high while TxElecIdle is asserted.
  //
  // pipe7_mac_datapath_ra's data-phase FSM owns TxElecIdle and only leaves the
  // data phase after TxDataValid has been low for the full drain, so
  // `dp_tx_elec_idle == 0` whenever TxDataValid is high.  At the bridge boundary
  // ucie2_pipe7_bridge.sv:214 muxes in `busy ? 4'hF : dp_tx_elec_idle`, which
  // forces EI asserted for an in-flight PowerDown/Rate/Width request regardless
  // of the datapath phase — so the rule is qualified with `!busy` here.  The
  // directed round-trip never raises req_valid, so `busy` is 0 throughout and
  // the qualifier costs no coverage.  Whether the bridge should instead hold off
  // a control request until the datapath has drained is an RTL question, left
  // FLAGGED for a human rather than guessed at.
  // ===========================================================================
  a_no_tx_while_elec_idle: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n)
      (!busy && tx_data_valid) |-> (tx_elec_idle == 4'h0)
  ) else $error("[SVA] tx_data_valid high while tx_elec_idle=%h asserted", tx_elec_idle);

  // ===========================================================================
  // P2 — block lock / sync_error.
  //
  // (a) Structural: the deframer only clears block_locked in the same cycle it
  //     raises sync_error, so lock is sticky while sync_error stays low.  True
  //     for any stimulus.
  // (b) Steady state: once locked, the directed round-trip's clean PHY loopback
  //     never loses alignment, so sync_error stays low.  This is the per-cycle
  //     form of the end-of-test check already in both scoreboards.
  // ===========================================================================
  a_lock_is_sticky: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n)
      (block_locked && !sync_error) |=> block_locked
  ) else $error("[SVA] block_locked dropped without sync_error");

  a_no_sync_error_once_locked: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n)
      block_locked |-> !sync_error
  ) else $error("[SVA] sync_error raised after block_locked");

  // ===========================================================================
  // P3 — the FDI pl_stallreq handshake is well formed (ucie2_fdi_link_fsm).
  //
  // (a) Once requested, the stall is held until the Protocol Layer acks it (or a
  //     link error tears the handshake down).
  // (b) pl_state_sts only ever changes as the result of a completed
  //     stallreq/stallack handshake, or of lp_linkerror.
  // ===========================================================================
  a_stallreq_held_until_ack: assert property (
    @(posedge lclk) disable iff (!lclk_rst_n)
      (pl_stallreq && !lp_stallack && !lp_linkerror) |=> pl_stallreq
  ) else $error("[SVA] pl_stallreq dropped without lp_stallack");

  a_state_change_handshaked: assert property (
    @(posedge lclk) disable iff (!lclk_rst_n)
      (pl_state_sts != $past(pl_state_sts)) |->
        ($past(lp_linkerror) || ($past(pl_stallreq) && $past(lp_stallack)))
  ) else $error("[SVA] pl_state_sts changed to %h outside the stall handshake",
                pl_state_sts);

  // lp_state_req is observed for context only (it is the request the handshake
  // above commits); keep it referenced so strict lint sees no unused port.
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_sva = |lp_state_req;
  /* verilator lint_on UNUSEDSIGNAL */

  // ===========================================================================
  // P4 — the RX burst FIFO never overflows in the directed round-trip.
  // rx_overflow is a sticky flag cleared only by reset, so this also proves it
  // never fired earlier in the run.
  // ===========================================================================
  a_no_rx_overflow: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n) !rx_overflow
  ) else $error("[SVA] rx_overflow asserted (RX burst FIFO overran)");

endmodule : ucie2_pipe7_sva
/* verilator lint_on SYNCASYNCNET */

// Bind one checker into every bridge instance.  Connections are by explicit
// name to the bridge's own boundary ports — no RTL hierarchy is reached into.
bind ucie2_pipe7_bridge ucie2_pipe7_sva u_sva (
  .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
  .tx_data_valid(tx_data_valid), .tx_elec_idle(tx_elec_idle), .busy(busy),
  .block_locked(block_locked), .sync_error(sync_error), .rx_overflow(rx_overflow),
  .lp_state_req(lp_state_req), .pl_state_sts(pl_state_sts),
  .lp_linkerror(lp_linkerror), .pl_stallreq(pl_stallreq), .lp_stallack(lp_stallack)
);

`default_nettype wire
