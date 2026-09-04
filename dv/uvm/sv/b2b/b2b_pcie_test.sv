// -----------------------------------------------------------------------------
// b2b_pcie_test — B2B "external PCIe" end-to-end test (PLAN H2).
//
// PCIe -> [bridge A] -> UCIe == UCIe -> [bridge B] -> PCIe. Injects the shared
// pre-framed PIPE word stream (+VEC_WORDS) into bridge A, checks the flits
// recovered at the UCIe seam against +VEC, and checks bridge B's re-framed output
// against the injected words. Mirrors dv/pyuvm/test_b2b_pcie.py. Scoreboard-only:
// no per-cycle trace (deferred, PLAN H3). Run length: +RUN_PCLK.
// -----------------------------------------------------------------------------
class b2b_pcie_test extends uvm_test;
  `uvm_component_utils(b2b_pcie_test)

  virtual b2b_pcie_if     vif;
  b2b_pcie_driver         driver;
  b2b_pcie_seam_monitor   seam_mon;
  b2b_pcie_btx_monitor    btx_mon;
  b2b_pcie_scoreboard     sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual b2b_pcie_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "b2b_pcie_test: vif not set");
    driver   = b2b_pcie_driver::type_id::create("driver", this);
    seam_mon = b2b_pcie_seam_monitor::type_id::create("seam_mon", this);
    btx_mon  = b2b_pcie_btx_monitor::type_id::create("btx_mon", this);
    sb       = b2b_pcie_scoreboard::type_id::create("sb", this);
    driver.vif   = vif;
    seam_mon.vif = vif;
    btx_mon.vif  = vif;
    sb.btx       = btx_mon;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    driver.ref_ap.connect(sb.ref_ap);
    seam_mon.ap.connect(sb.seam_ap);
    btx_mon.ap.connect(sb.btx_ap);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned run_pclk;
    phase.raise_objection(this);
    if (!$value$plusargs("RUN_PCLK=%d", run_pclk)) run_pclk = RUN_PCLK;

    wait (vif.pclk_rst_n === 1'b1 && vif.lclk_rst_n === 1'b1);

    fork
      driver.inject();
      seam_mon.capture();
      btx_mon.capture();
    join_none

    repeat (run_pclk) @(posedge vif.pclk);
    phase.drop_objection(this);
  endtask
endclass
