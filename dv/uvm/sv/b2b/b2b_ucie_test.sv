// -----------------------------------------------------------------------------
// b2b_ucie_test — B2B "external UCIe" round-trip test (PLAN H1).
//
// UCIe -> [bridge A] -> PCIe == PCIe -> [bridge B] -> UCIe. Drives the shared FDI
// flit vector into bridge A (via +VEC/+N_FLITS, same as the single-bridge test),
// recovers flits out of bridge B, and cross-checks (recovered==driven, bridge B
// locks, no sync_error). Mirrors dv/pyuvm/test_b2b_ucie.py. Scoreboard-only: no
// per-cycle trace (the byte-identical B2B gate is deferred, PLAN H3). The timing
// tasks are forked here (like the single-bridge test) after reset deassert.
// Run length: +RUN_PCLK (default RUN_PCLK localparam).
// -----------------------------------------------------------------------------
class b2b_ucie_test extends uvm_test;
  `uvm_component_utils(b2b_ucie_test)

  virtual b2b_ucie_if   vif;
  fdi_sequencer         seqr;
  b2b_ucie_driver       driver;
  b2b_ucie_rx_monitor   rx_mon;
  b2b_ucie_mid_monitor  mid_mon;
  b2b_ucie_scoreboard   sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual b2b_ucie_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "b2b_ucie_test: vif not set");
    seqr    = fdi_sequencer::type_id::create("seqr", this);
    driver  = b2b_ucie_driver::type_id::create("driver", this);
    rx_mon  = b2b_ucie_rx_monitor::type_id::create("rx_mon", this);
    mid_mon = b2b_ucie_mid_monitor::type_id::create("mid_mon", this);
    sb      = b2b_ucie_scoreboard::type_id::create("sb", this);
    driver.vif  = vif;
    rx_mon.vif  = vif;
    mid_mon.vif = vif;
    sb.mid      = mid_mon;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(seqr.seq_item_export);
    driver.drv_ap.connect(sb.exp_ap);
    rx_mon.ap.connect(sb.rx_ap);
    mid_mon.ap.connect(sb.mid_ap);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned run_pclk;
    fdi_flit_seq seq;
    phase.raise_objection(this);
    if (!$value$plusargs("RUN_PCLK=%d", run_pclk)) run_pclk = RUN_PCLK;

    wait (vif.pclk_rst_n === 1'b1 && vif.lclk_rst_n === 1'b1);

    seq = fdi_flit_seq::type_id::create("seq");
    fork
      driver.drive();
      driver.stall_ack();
      rx_mon.capture();
      mid_mon.capture();
      seq.start(seqr);
    join_none

    repeat (run_pclk) @(posedge vif.pclk);
    phase.drop_objection(this);
  endtask
endclass
