// -----------------------------------------------------------------------------
// b2b_ucie_fd_test — FULL-DUPLEX B2B "external UCIe" round-trip (Phase I I8).
//
// Both directions run at once over the joined PIPE link (see b2b_ucie_fd_if):
//   forward driver -> A, recovered at B;  reverse driver -> B, recovered at A.
// Each direction drives the shared FDI flit vector (+VEC/+N_FLITS) and both
// recovered streams must equal it, with both bridges locked and no sync_error.
// Mirrors dv/pyuvm/test_b2b_ucie_fd.py. Scoreboard-only (byte-identical B2B trace
// gate is a later I8 increment). Timing tasks are forked after reset deassert.
// Run length: +RUN_PCLK (default RUN_PCLK localparam).
// -----------------------------------------------------------------------------
class b2b_ucie_fd_test extends uvm_test;
  `uvm_component_utils(b2b_ucie_fd_test)

  virtual b2b_ucie_fd_if    vif;
  fdi_sequencer             seqr_a, seqr_b;
  b2b_ucie_fd_driver        drv_a, drv_b;       // A=forward, B=reverse
  b2b_ucie_fd_monitor       mon_b, mon_a;       // at B=forward, at A=reverse
  b2b_ucie_fd_scoreboard    sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual b2b_ucie_fd_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "b2b_ucie_fd_test: vif not set");
    seqr_a = fdi_sequencer::type_id::create("seqr_a", this);
    seqr_b = fdi_sequencer::type_id::create("seqr_b", this);
    drv_a  = b2b_ucie_fd_driver::type_id::create("drv_a", this);
    drv_b  = b2b_ucie_fd_driver::type_id::create("drv_b", this);
    mon_b  = b2b_ucie_fd_monitor::type_id::create("mon_b", this);
    mon_a  = b2b_ucie_fd_monitor::type_id::create("mon_a", this);
    sb     = b2b_ucie_fd_scoreboard::type_id::create("sb", this);
    drv_a.vif = vif; drv_a.is_b = 1'b0;
    drv_b.vif = vif; drv_b.is_b = 1'b1;
    mon_b.vif = vif; mon_b.at_b = 1'b1;      // forward recovers at B
    mon_a.vif = vif; mon_a.at_b = 1'b0;      // reverse recovers at A
    sb.fwd_mon = mon_b;
    sb.rev_mon = mon_a;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    drv_a.seq_item_port.connect(seqr_a.seq_item_export);
    drv_b.seq_item_port.connect(seqr_b.seq_item_export);
    drv_a.drv_ap.connect(sb.exp_fwd_ap);
    drv_b.drv_ap.connect(sb.exp_rev_ap);
    mon_b.ap.connect(sb.rx_fwd_ap);
    mon_a.ap.connect(sb.rx_rev_ap);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned run_pclk;
    fdi_flit_seq seq_a, seq_b;
    phase.raise_objection(this);
    if (!$value$plusargs("RUN_PCLK=%d", run_pclk)) run_pclk = RUN_PCLK;

    wait (vif.pclk_rst_n === 1'b1 && vif.lclk_rst_n === 1'b1);

    seq_a = fdi_flit_seq::type_id::create("seq_a");
    seq_b = fdi_flit_seq::type_id::create("seq_b");
    fork
      drv_a.drive();     drv_a.stall_ack();
      drv_b.drive();     drv_b.stall_ack();
      mon_b.capture();   mon_a.capture();
      seq_a.start(seqr_a);
      seq_b.start(seqr_b);
    join_none

    repeat (run_pclk) @(posedge vif.pclk);
    phase.drop_objection(this);
  endtask
endclass
