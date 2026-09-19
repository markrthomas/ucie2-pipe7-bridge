// -----------------------------------------------------------------------------
// b2b_pcie_fd_test — FULL-DUPLEX B2B "external PCIe" end-to-end (Phase I I8b).
//
// Both directions run at once over the joined FDI seam (see b2b_pcie_fd_if):
//   forward driver -> A.rx, re-framed out at B.tx;
//   reverse driver -> B.rx, re-framed out at A.tx.
// Each direction injects the shared pre-framed PIPE word stream (+VEC_WORDS) and
// both re-framed outputs must equal it, with both deframers locked and no
// sync_error. Mirrors dv/pyuvm/test_b2b_pcie_fd.py. Timing tasks are forked after
// reset deassert. Run length: +RUN_PCLK (default RUN_PCLK localparam).
//
// Phase I I8c: emits the canonical per-cycle B2B trace (+B2B_TRACE=<path>) of both
// bridges' PIPE TX outputs + lock/error, sampled #0.1 post-edge on the coincident
// pclk. Columns/format mirror b2b_trace_format.PCIE_FD_COLUMNS so
// tools/trace_compare.py (make trace-compare-b2b) holds this env cycle-for-cycle
// against the PyUVM full-duplex TB.
// -----------------------------------------------------------------------------
class b2b_pcie_fd_test extends uvm_test;
  `uvm_component_utils(b2b_pcie_fd_test)

  virtual b2b_pcie_fd_if    vif;
  b2b_pcie_fd_driver        drv_a, drv_b;       // A=forward inject, B=reverse inject
  b2b_pcie_fd_monitor       mon_fwd, mon_rev;   // fwd=out at B, rev=out at A
  b2b_pcie_fd_scoreboard    sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual b2b_pcie_fd_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "b2b_pcie_fd_test: vif not set");
    drv_a   = b2b_pcie_fd_driver::type_id::create("drv_a", this);
    drv_b   = b2b_pcie_fd_driver::type_id::create("drv_b", this);
    mon_fwd = b2b_pcie_fd_monitor::type_id::create("mon_fwd", this);
    mon_rev = b2b_pcie_fd_monitor::type_id::create("mon_rev", this);
    sb      = b2b_pcie_fd_scoreboard::type_id::create("sb", this);
    drv_a.vif = vif; drv_a.is_b = 1'b0;
    drv_b.vif = vif; drv_b.is_b = 1'b1;
    mon_fwd.vif = vif; mon_fwd.fwd = 1'b1;      // forward re-frames out at B
    mon_rev.vif = vif; mon_rev.fwd = 1'b0;      // reverse re-frames out at A
    sb.fwd_mon = mon_fwd;
    sb.rev_mon = mon_rev;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    drv_a.ref_ap.connect(sb.exp_fwd_ap);
    drv_b.ref_ap.connect(sb.exp_rev_ap);
    mon_fwd.ap.connect(sb.rx_fwd_ap);
    mon_rev.ap.connect(sb.rx_rev_ap);
  endfunction

  task run_phase(uvm_phase phase);
    int unsigned run_pclk;
    int          fd;
    string       path;
    phase.raise_objection(this);
    if (!$value$plusargs("RUN_PCLK=%d", run_pclk)) run_pclk = RUN_PCLK;
    if (!$value$plusargs("B2B_TRACE=%s", path))    path = "b2b_pcie_fd.trace";
    fd = $fopen(path, "w");
    if (fd == 0) `uvm_fatal("B2BPFD", $sformatf("cannot open %s", path));
    $fwrite(fd, "cycle,a_tx_data_valid,a_tx_data,a_block_locked,a_sync_error,b_tx_data_valid,b_tx_data,b_block_locked,b_sync_error\n");

    wait (vif.pclk_rst_n === 1'b1 && vif.lclk_rst_n === 1'b1);

    fork
      drv_a.inject();
      drv_b.inject();
      mon_fwd.capture();
      mon_rev.capture();
    join_none

    for (int cyc = 0; cyc < run_pclk; cyc++) begin
      @(posedge vif.pclk); #0.1;
      $fwrite(fd, "%0d,%0d,%h,%0d,%0d,%0d,%h,%0d,%0d\n",
        cyc, vif.a_tx_data_valid, vif.a_tx_data, vif.a_block_locked, vif.a_sync_error,
             vif.b_tx_data_valid, vif.b_tx_data, vif.b_block_locked, vif.b_sync_error);
    end
    $fclose(fd);
    phase.drop_objection(this);
  endtask
endclass
