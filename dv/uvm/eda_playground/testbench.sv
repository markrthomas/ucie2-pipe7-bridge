// ============================================================================
// GENERATED FILE — DO NOT EDIT.
//   Source of truth: rtl/*.sv + dv/uvm/sv/*.  Regenerate: make eda-playground
//   EDA Playground: Testbench pane (paste here)
//   Settings: top = tb_ucie2_pipe7; pick a UVM-capable tool + a UVM version;
//             run-option +UVM_NO_RELNOTES. Assertions need the tool's SVA
//             support enabled (the bound ucie2_pipe7_sva checker).
//   This is a PORTABILITY/DEMO bundle: NOT part of the sacred gate and it
//   cannot run tools/trace_compare.py. Verify by running it in EDA Playground.
// ============================================================================
`timescale 1ns/1ps

// ==== dv/uvm/sv/ucie2_pipe7_sva.sv ====
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

// ==== dv/uvm/sv/ucie2_pipe7_if.sv ====
// -----------------------------------------------------------------------------
// ucie2_pipe7_if — DUT boundary bundle for the SV UVM environment.
//
// SCAFFOLD (PLAN Item 13 seed). Carries the FROZEN (Item 0) FDI controller-facing
// and PIPE 7.1 MAC-facing signal set. Agents/drivers/scoreboard are added in
// Phase D; today only the smoke test samples this for the per-cycle trace.
// Signal set: docs/ucie2_pipe71_spec_crosscheck.md section B.
// -----------------------------------------------------------------------------
interface ucie2_pipe7_if #(
  parameter int unsigned FDI_W = 128,
  parameter int unsigned PW    = 80,
  parameter int unsigned MBW   = 8
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // FDI transmit (Protocol Layer -> bridge)
  logic [FDI_W-1:0] lp_data       = '0;
  logic             lp_valid       = 1'b0;
  logic             lp_irdy        = 1'b0;
  logic             pl_trdy;
  // FDI receive (bridge -> Protocol Layer)
  logic [FDI_W-1:0] pl_data;
  logic             pl_valid;
  logic             pl_flit_cancel;
  // FDI link state machine
  // lp_state_req MUST be initialised to FDI_RESET (0): if it is x at reset
  // deassert the link FSM sees a mismatch and immediately asserts pl_stallreq,
  // diverging from the PyUVM trace at cycle 0.
  logic [3:0]       lp_state_req   = 4'h0;   // FDI_RESET
  logic [3:0]       pl_state_sts;
  logic             lp_linkerror   = 1'b0;
  logic             pl_stallreq;
  logic             lp_stallack    = 1'b0;
  // FDI rx-active / clock / wake
  logic             lp_rx_active_req = 1'b0;
  logic             pl_rx_active_sts;
  logic             pl_clk_req;
  logic             lp_clk_ack     = 1'b0;
  logic             lp_wake_req    = 1'b0;
  logic             pl_wake_ack;

  // Management: PIPE control request
  logic             req_valid      = 1'b0;
  logic [1:0]       req_kind       = 2'b0;
  logic [3:0]       req_power_down = 4'h0;
  logic [3:0]       req_rate       = 4'h0;
  logic [2:0]       req_width      = 3'h0;
  logic [2:0]       req_rxwidth    = 3'h0;
  logic             busy;
  logic             done;
  logic             req_error;
  // Management: message-bus request
  logic             mb_req_valid   = 1'b0;
  logic             mb_req_write   = 1'b0;
  logic             mb_req_committed = 1'b0;
  logic [11:0]      mb_req_addr    = 12'h0;
  logic [7:0]       mb_req_wdata   = 8'h0;
  logic             mb_req_ready;
  logic             mb_busy;
  logic             mb_rsp_valid;
  logic             mb_rsp_is_read;
  logic [7:0]       mb_rsp_rdata;
  logic             mb_rsp_error;

  // PIPE PHY -> MAC stimulus inputs (loopback / PHY model driven by TB)
  logic [PW-1:0]    rx_data        = '0;
  logic             rx_valid       = 1'b0;
  logic             phy_status     = 1'b0;
  logic [2:0]       rx_status      = 3'h0;
  logic             rx_elec_idle   = 1'b0;
  logic [MBW-1:0]   p2m_message_bus = '0;
  // PIPE MAC -> PHY (DUT outputs)
  logic [PW-1:0]    tx_data;
  logic             tx_data_valid;
  logic [3:0]       rate;
  logic [3:0]       power_down;
  logic [2:0]       width;
  logic [2:0]       rx_width;
  logic             tx_detect_rx;
  logic [3:0]       tx_elec_idle;
  // PIPE message bus (DUT output)
  logic [MBW-1:0]   m2p_message_bus;
  // Bridge status (DUT outputs)
  logic             block_locked;
  logic             sync_error;
  logic             in_data_phase;
  logic             rx_overflow;
endinterface : ucie2_pipe7_if

// ==== dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv ====
// -----------------------------------------------------------------------------
// ucie2_pipe7_uvm_pkg — SV UVM environment (PLAN item 13).
//
// A real multi-agent UVM env laid out UVM-Cookbook style — one class per file,
// pulled into this single package via ordered `include (the Cookbook's own
// idiom). The tree under dv/uvm/sv/:
//   fdi_agent/  fdi_flit_item, fdi_sequencer, fdi_seq_lib, fdi_driver,
//               fdi_monitor, fdi_agent  (controller-facing agent + stall_ack)
//   pipe_agent/ pipe_monitor (tx), phy_loopback, pipe_agent  (MAC/PHY-facing)
//   env/        bridge_scoreboard, bridge_env
//   test/       ucie2_roundtrip_test
// mirroring the PyUVM tier (dv/pyuvm/{agents,seq_lib,env}.py).
//
// ONE package keeps every shared type (fdi_flit_item, the localparams below, the
// virtual interface) in one compilation unit, so the split is a pure textual
// reorganization: same tokens, same order, same compilation unit -> the emitted
// per-cycle trace is byte-identical and tools/trace_compare.py stays green. The
// component timing tasks are forked by ucie2_roundtrip_test (not via auto
// run_phases) precisely to preserve that fork order.
//
// Include order respects type dependencies: item -> sequencer -> sequence ->
// driver/monitor -> agent, both agents before env, env before test.
// -----------------------------------------------------------------------------
package ucie2_pipe7_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;

  localparam int unsigned N_FLITS      = 8;
  localparam int unsigned BRINGUP_LCLK = 8;
  localparam int unsigned RUN_PCLK     = 200;
  localparam int unsigned PW           = PIPE_WIDTH_DEFAULT;
  localparam int unsigned FDIW         = FDI_DW;

  // FDI controller-facing agent
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_flit_item.sv ----
// -----------------------------------------------------------------------------
// fdi_flit_item — FDI stimulus transaction (PLAN item 13).
//
// One class per file, UVM-Cookbook style. `include`d at package scope by
// ucie2_pipe7_uvm_pkg.sv, so it sees the package localparams (FDIW). Mirrors
// dv/pyuvm/seq_lib/fdi_seq_lib.py's item. Payload is filled by fdi_flit_seq.
// -----------------------------------------------------------------------------
class fdi_flit_item extends uvm_sequence_item;
  rand bit [FDIW-1:0] data;
  bit                 is_os;
  `uvm_object_utils(fdi_flit_item)
  function new(string name = "fdi_flit_item");
    super.new(name);
  endfunction
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_sequencer.sv ----
// -----------------------------------------------------------------------------
// fdi_sequencer — sequencer for fdi_flit_item (PLAN item 13).
//
// A plain uvm_sequencer specialization (UVM-Cookbook style: the sequencer gets
// its own file even when it is a simple typedef). `include`d after
// fdi_flit_item.sv by ucie2_pipe7_uvm_pkg.sv.
// -----------------------------------------------------------------------------
typedef uvm_sequencer#(fdi_flit_item) fdi_sequencer;
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_seq_lib.sv ----
// -----------------------------------------------------------------------------
// fdi_seq_lib — FDI directed ramp sequence (PLAN item 13).
//
// Mirrors dv/pyuvm/seq_lib/fdi_seq_lib.py. The payload formula is byte-identical
// to the proven directed round-trip, so the emitted per-cycle trace and the
// recovered-flit check are unchanged (trace_compare stays green). `include`d at
// package scope by ucie2_pipe7_uvm_pkg.sv (sees its localparams N_FLITS).
// -----------------------------------------------------------------------------
class fdi_flit_seq extends uvm_sequence#(fdi_flit_item);
  int unsigned n_flits = N_FLITS;
  `uvm_object_utils(fdi_flit_seq)
  function new(string name = "fdi_flit_seq");
    super.new(name);
  endfunction
  virtual task body();
    for (int i = 0; i < n_flits; i++) begin
      fdi_flit_item it;
      it = fdi_flit_item::type_id::create($sformatf("flit%0d", i));
      it.data  = (128'(16'h1000 + i) << 64) | 128'(32'hABCD0000 + i);
      it.is_os = 1'b0;
      start_item(it);
      finish_item(it);
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_driver.sv ----
// -----------------------------------------------------------------------------
// fdi_driver — FDI controller-facing driver + stall-ack responder (PLAN item 13).
//
// Bring-up + directed flit drive on the proven fixed schedule, plus the FDI
// stall handshake. Mirrors dv/pyuvm/agents/fdi_agent.py. The timing tasks
// (drive/stall_ack) are forked by the test in the proven order so the per-cycle
// trace stays byte-identical; get_next_item/item_done are zero sim-time, so
// routing payloads through the sequencer does not perturb the cycle schedule.
// -----------------------------------------------------------------------------
class fdi_driver extends uvm_driver#(fdi_flit_item);
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) drv_ap;   // driven flits -> scoreboard
  `uvm_component_utils(fdi_driver)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    drv_ap = new("drv_ap", this);
  endfunction

  // Forked by the test after cycle 0 is recorded. Identical schedule to the
  // proven stimulus(): request ACTIVE, BRINGUP_LCLK bubbles, then one flit per
  // lclk honoring #0.1 post-edge writes, then deassert.
  virtual task drive();
    vif.lp_state_req = FDI_ACTIVE;
    repeat (BRINGUP_LCLK) @(posedge vif.lclk);
    for (int i = 0; i < N_FLITS; i++) begin
      seq_item_port.get_next_item(req);          // zero sim time
      #0.1;
      vif.lp_data  = req.data;
      vif.lp_valid = 1'b1;
      vif.lp_irdy  = 1'b1;
      drv_ap.write(req.data);
      @(posedge vif.lclk);
      seq_item_port.item_done();                 // zero sim time
    end
    #0.1;
    vif.lp_valid = 1'b0;
    vif.lp_irdy  = 1'b0;
  endtask

  // Auto-complete the FDI stall handshake: sample at N, drive at N+1 -> visible
  // to the RTL at N+2, matching cocotb's VPI write latency.
  virtual task stall_ack();
    logic captured;
    forever begin
      @(posedge vif.lclk); #0.1;   // cycle N: sample
      captured = vif.pl_stallreq;
      @(posedge vif.lclk); #0.1;   // cycle N+1: drive -> visible at N+2
      vif.lp_stallack = captured;
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_monitor.sv ----
// -----------------------------------------------------------------------------
// fdi_monitor — FDI RX monitor: recovers pl_data flits (PLAN item 13).
//
// Mirrors dv/pyuvm/agents/fdi_agent.py's RX monitor. Its capture() task is forked
// by the test in the proven order; #0.1 post-edge sampling keeps the recovered
// stream (and trace_compare) byte-identical.
// -----------------------------------------------------------------------------
class fdi_rx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) ap;
  `uvm_component_utils(fdi_rx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.lclk); #0.1;
      if (vif.pl_valid) ap.write(vif.pl_data);
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_agent.sv ----
// -----------------------------------------------------------------------------
// fdi_agent — FDI controller-facing agent (PLAN item 13).
//
// Assembles the sequencer + driver + RX monitor and connects the driver to the
// sequencer. Mirrors dv/pyuvm/agents/fdi_agent.py. The driver/monitor timing
// tasks are forked by the test (proven order) so the per-cycle trace stays
// byte-identical.
// -----------------------------------------------------------------------------
class fdi_agent extends uvm_agent;
  fdi_sequencer  seqr;
  fdi_driver     driver;
  fdi_rx_monitor rx_mon;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(fdi_agent)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "fdi_agent: vif not set")
    seqr   = fdi_sequencer::type_id::create("seqr", this);
    driver = fdi_driver::type_id::create("driver", this);
    rx_mon = fdi_rx_monitor::type_id::create("rx_mon", this);
    driver.vif = vif;
    rx_mon.vif = vif;
  endfunction
  virtual function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass
  // PIPE MAC/PHY-facing agent
// ---- inlined from dv/uvm/sv/pipe_agent/pipe_monitor.sv ----
// -----------------------------------------------------------------------------
// pipe_monitor — PIPE MAC-facing TX monitor: captures tx_data words (item 13).
//
// Mirrors the PyUVM PipeTxMonitor. Its capture() task is forked by the test
// (proven order); #0.1 post-edge sampling keeps trace_compare byte-identical.
// -----------------------------------------------------------------------------
class pipe_tx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [PW-1:0]) ap;
  `uvm_component_utils(pipe_tx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.pclk); #0.1;
      if (vif.tx_data_valid) ap.write(vif.tx_data);
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/pipe_agent/phy_loopback.sv ----
// -----------------------------------------------------------------------------
// phy_loopback — PIPE PHY loopback: rx <- tx via a 1-cycle shadow (item 13).
//
// Net 2-cycle delay, matching cocotb's VPI write latency so the Gen5 128b/130b
// deframer recovers what the framer sent. Mirrors the PyUVM loopback. Its run()
// task is forked by the test (proven order) so trace_compare stays byte-identical.
// -----------------------------------------------------------------------------
class phy_loopback extends uvm_component;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(phy_loopback)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  // Drive the PREVIOUS cycle's capture at each edge (1-cycle shadow register) so
  // rx = tx from N-1 lands at N+1 = a net 2-cycle delay. Covers every cycle (no
  // skipped slots), preserving block alignment for the deframer.
  virtual task run();
    logic [PW-1:0] cap_data  = '0;
    logic          cap_valid = 1'b0;
    forever begin
      @(posedge vif.pclk); #0.1;
      vif.rx_data  = cap_data;
      vif.rx_valid = cap_valid;
      cap_data  = vif.tx_data;
      cap_valid = vif.tx_data_valid;
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/pipe_agent/pipe_agent.sv ----
// -----------------------------------------------------------------------------
// pipe_agent — PIPE MAC-facing agent (PLAN item 13).
//
// Assembles the TX monitor + PHY loopback. Mirrors the PyUVM pipe agent. The
// timing tasks are forked by the test (proven order) so the per-cycle trace
// stays byte-identical.
// -----------------------------------------------------------------------------
class pipe_agent extends uvm_agent;
  pipe_tx_monitor tx_mon;
  phy_loopback    loopback;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(pipe_agent)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pipe_agent: vif not set")
    tx_mon   = pipe_tx_monitor::type_id::create("tx_mon", this);
    loopback = phy_loopback::type_id::create("loopback", this);
    tx_mon.vif   = vif;
    loopback.vif = vif;
  endfunction
endclass
  // Environment
// ---- inlined from dv/uvm/sv/env/bridge_scoreboard.sv ----
// -----------------------------------------------------------------------------
// bridge_scoreboard — round-trip identity + datapath invariants (PLAN item 13).
//
// Mirrors the PyUVM BridgeScoreboard: recovered FDI flits (rx_mon) must equal the
// driven flits (driver.drv_ap), the deframer must reach block_locked with no
// sync_error, and at least N_FLITS must be recovered. TX word count is tracked
// for the report. These are exactly the proven directed test's self-checks.
// The `uvm_analysis_imp_decl macros must precede the class (they define the
// _exp/_rx/_tx analysis-imp specializations it uses).
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_tx)

class bridge_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_exp#(bit [FDIW-1:0], bridge_scoreboard) exp_ap;
  uvm_analysis_imp_rx #(bit [FDIW-1:0], bridge_scoreboard) rx_ap;
  uvm_analysis_imp_tx #(bit [PW-1:0],   bridge_scoreboard) tx_ap;

  bit [FDIW-1:0] exp_q[$];
  bit [FDIW-1:0] rx_q[$];
  int unsigned   tx_count;
  virtual ucie2_pipe7_if vif;

  `uvm_component_utils(bridge_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_ap = new("exp_ap", this);
    rx_ap  = new("rx_ap",  this);
    tx_ap  = new("tx_ap",  this);
  endfunction

  function void write_exp(bit [FDIW-1:0] d); exp_q.push_back(d); endfunction
  function void write_rx (bit [FDIW-1:0] d); rx_q.push_back(d);  endfunction
  function void write_tx (bit [PW-1:0]   d); tx_count++;         endfunction

  virtual function void check_phase(uvm_phase phase);
    if (vif.sync_error !== 1'b0)
      `uvm_error("SB", "deframer raised sync_error")
    if (vif.block_locked !== 1'b1)
      `uvm_error("SB", "deframer never reached block_locked")
    if (rx_q.size() < N_FLITS)
      `uvm_error("SB", $sformatf("only %0d flits recovered (< %0d)",
                                 rx_q.size(), N_FLITS))
    else
      for (int i = 0; i < N_FLITS; i++)
        if (rx_q[i] !== exp_q[i])
          `uvm_error("SB", $sformatf("round-trip mismatch [%0d]: got %h exp %h",
                                     i, rx_q[i], exp_q[i]))
    `uvm_info("SB", $sformatf("roundtrip: %0d driven, tx %0d words, recovered %0d",
              exp_q.size(), tx_count, rx_q.size()), UVM_LOW)
  endfunction
endclass
// ---- inlined from dv/uvm/sv/env/bridge_env.sv ----
// -----------------------------------------------------------------------------
// bridge_env — FDI agent + PIPE agent + scoreboard, analysis wiring (item 13).
//
// Mirrors dv/pyuvm/env.py. The test forks the components' timing tasks (loopback,
// stall_ack, tx/rx capture, drive) in the proven order and emits the per-cycle
// trace itself, so the byte-identical trace_compare gate is preserved.
// -----------------------------------------------------------------------------
class bridge_env extends uvm_env;
  fdi_agent         agent;
  pipe_agent        pipe;
  bridge_scoreboard sb;
  virtual ucie2_pipe7_if vif;

  `uvm_component_utils(bridge_env)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "bridge_env: vif not set")
    agent = fdi_agent::type_id::create("agent", this);
    pipe  = pipe_agent::type_id::create("pipe", this);
    sb    = bridge_scoreboard::type_id::create("sb", this);
    sb.vif = vif;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agent.driver.drv_ap.connect(sb.exp_ap);
    agent.rx_mon.ap.connect(sb.rx_ap);
    pipe.tx_mon.ap.connect(sb.tx_ap);
  endfunction
endclass
  // Test (the sacred per-cycle trace emitter)
// ---- inlined from dv/uvm/sv/test/ucie2_roundtrip_test.sv ----
// -----------------------------------------------------------------------------
// ucie2_roundtrip_test — the round-trip UVM test (PLAN item 13).
//
// SACRED TRACE EMITTER. Keeps the EXACT proven orchestration of the prior flat
// test: single 2 ns clocking, reset-deassert wait, cycle 0 sampled BEFORE the
// fork (matches cocotb start_soon), the same fork order, #0.1 post-edge sampling,
// and the same trace columns/payloads. So the emitted per-cycle trace is
// byte-identical and tools/trace_compare.py stays green. The component tasks are
// forked here (not via auto run_phases) precisely to preserve that fork order.
//
// Trace column order MUST match trace_format.TRACE_COLUMNS. Do not edit the
// run_phase body: the byte-identical cross-check depends on it verbatim.
// `include`d LAST at package scope by ucie2_pipe7_uvm_pkg.sv (after env).
// -----------------------------------------------------------------------------
class ucie2_roundtrip_test extends uvm_test;
  `uvm_component_utils(ucie2_roundtrip_test)

  bridge_env             env;
  virtual ucie2_pipe7_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' not set in config_db")
    env = bridge_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    int          fd;
    string       path;
    fdi_flit_seq seq;
    phase.raise_objection(this);

    // Idle all inputs during reset (identical to the proven directed test).
    vif.lp_data = '0; vif.lp_valid = 0; vif.lp_irdy = 0;
    vif.lp_state_req = '0; vif.lp_linkerror = 0; vif.lp_stallack = 0;
    vif.lp_rx_active_req = 0; vif.lp_clk_ack = 0; vif.lp_wake_req = 0;
    vif.req_valid = 0; vif.req_kind = '0; vif.req_power_down = '0;
    vif.req_rate = '0; vif.req_width = '0; vif.req_rxwidth = '0;
    vif.mb_req_valid = 0; vif.mb_req_write = 0; vif.mb_req_committed = 0;
    vif.mb_req_addr = '0; vif.mb_req_wdata = '0;
    vif.rx_data = '0; vif.rx_valid = 0; vif.phy_status = 0;
    vif.rx_status = '0; vif.rx_elec_idle = 0; vif.p2m_message_bus = '0;

    if (!$value$plusargs("TRACE=%s", path)) path = "bridge.trace";
    fd = $fopen(path, "w");
    if (fd == 0) `uvm_fatal("TRACE", $sformatf("cannot open %s", path));
    $fwrite(fd,
      "cycle,pl_state_sts,pl_valid,pl_trdy,pl_stallreq,pl_flit_cancel,tx_data_valid,tx_data,rate,power_down\n");

    wait (vif.pclk_rst_n === 1'b1);

    // Cycle 0 sampled BEFORE the forked tasks start (matches cocotb start_soon:
    // cycle 0 sees reset-state inputs -> pl_stallreq==0).
    @(posedge vif.pclk); #0.1;
    $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
      0, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
      vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);

    seq = fdi_flit_seq::type_id::create("seq");

    // Fork the component timing tasks in the SAME order as the proven directed
    // test (loopback, stall_ack, tx capture, rx capture, drive), then start the
    // sequence that feeds the driver.
    fork
      env.pipe.loopback.run();
      env.agent.driver.stall_ack();
      env.pipe.tx_mon.capture();
      env.agent.rx_mon.capture();
      env.agent.driver.drive();
      seq.start(env.agent.seqr);
    join_none

    for (int cyc = 1; cyc < RUN_PCLK; cyc++) begin
      @(posedge vif.pclk); #0.1;
      $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
        cyc, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
        vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);
    end
    $fclose(fd);

    phase.drop_objection(this);
  endtask
endclass

endpackage : ucie2_pipe7_uvm_pkg

// ==== dv/uvm/sv/tb_ucie2_pipe7.sv ====
// -----------------------------------------------------------------------------
// tb_ucie2_pipe7 — SV UVM top (SCAFFOLD, PLAN Item 13 seed).
//
// Generates the two independent clocks (PIPE PCLK, FDI lclk), sequences the
// resets, instantiates the DUT + boundary interface (FROZEN Item-0 signal set),
// hands the vif to UVM, and runs the smoke test.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_ucie2_pipe7;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import ucie2_pipe7_uvm_pkg::*;

  localparam int unsigned FDI_W = FDI_DW;
  localparam int unsigned PW    = PIPE_WIDTH_DEFAULT;
  localparam int unsigned MBW   = MB_BUS_WIDTH;

  logic lclk = 0, pclk = 0;
  logic lclk_rst_n = 0, pclk_rst_n = 0;

  // One 2 ns period on both domains (coincident edges) so the bridge is fully
  // synchronous and the directed round-trip is deterministic / cross-sim stable,
  // matching the PyUVM TB (dv/pyuvm/test_roundtrip.py).
  always #1.0 lclk = ~lclk;
  always #1.0 pclk = ~pclk;

  // Reset deasserts at 11 ns — a non-edge time (edges are at even ns) so both
  // simulators agree on the first post-reset cycle.
  initial begin
    lclk_rst_n = 0; pclk_rst_n = 0;
    #11;
    lclk_rst_n = 1; pclk_rst_n = 1;
  end

  ucie2_pipe7_if #(.FDI_W(FDI_W), .PW(PW), .MBW(MBW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  ucie2_pipe7_bridge #(.FDI_W(FDI_W), .PW(PW)) dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    // FDI TX
    .lp_data(vif.lp_data), .lp_valid(vif.lp_valid), .lp_irdy(vif.lp_irdy),
    .pl_trdy(vif.pl_trdy),
    // FDI RX
    .pl_data(vif.pl_data), .pl_valid(vif.pl_valid), .pl_flit_cancel(vif.pl_flit_cancel),
    // FDI state machine
    .lp_state_req(vif.lp_state_req), .pl_state_sts(vif.pl_state_sts),
    .lp_linkerror(vif.lp_linkerror), .pl_stallreq(vif.pl_stallreq),
    .lp_stallack(vif.lp_stallack),
    // FDI rx-active / clock / wake
    .lp_rx_active_req(vif.lp_rx_active_req), .pl_rx_active_sts(vif.pl_rx_active_sts),
    .pl_clk_req(vif.pl_clk_req), .lp_clk_ack(vif.lp_clk_ack),
    .lp_wake_req(vif.lp_wake_req), .pl_wake_ack(vif.pl_wake_ack),
    // Management: PIPE control request
    .req_valid(vif.req_valid), .req_kind(vif.req_kind),
    .req_power_down(vif.req_power_down), .req_rate(vif.req_rate),
    .req_width(vif.req_width), .req_rxwidth(vif.req_rxwidth),
    .busy(vif.busy), .done(vif.done), .req_error(vif.req_error),
    // Management: message-bus request
    .mb_req_valid(vif.mb_req_valid), .mb_req_write(vif.mb_req_write),
    .mb_req_committed(vif.mb_req_committed), .mb_req_addr(vif.mb_req_addr),
    .mb_req_wdata(vif.mb_req_wdata), .mb_req_ready(vif.mb_req_ready),
    .mb_busy(vif.mb_busy), .mb_rsp_valid(vif.mb_rsp_valid),
    .mb_rsp_is_read(vif.mb_rsp_is_read), .mb_rsp_rdata(vif.mb_rsp_rdata),
    .mb_rsp_error(vif.mb_rsp_error),
    // PIPE MAC -> PHY
    .tx_data(vif.tx_data), .tx_data_valid(vif.tx_data_valid),
    .rate(vif.rate), .power_down(vif.power_down), .width(vif.width),
    .rx_width(vif.rx_width), .tx_detect_rx(vif.tx_detect_rx),
    .tx_elec_idle(vif.tx_elec_idle),
    // PIPE PHY -> MAC
    .rx_data(vif.rx_data), .rx_valid(vif.rx_valid), .phy_status(vif.phy_status),
    .rx_status(vif.rx_status), .rx_elec_idle(vif.rx_elec_idle),
    // PIPE message bus
    .m2p_message_bus(vif.m2p_message_bus), .p2m_message_bus(vif.p2m_message_bus),
    // Bridge status
    .block_locked(vif.block_locked), .sync_error(vif.sync_error),
    .in_data_phase(vif.in_data_phase), .rx_overflow(vif.rx_overflow)
  );

  initial begin
    uvm_config_db#(virtual ucie2_pipe7_if)::set(null, "*", "vif", vif);
    run_test("ucie2_roundtrip_test");
  end
endmodule : tb_ucie2_pipe7
