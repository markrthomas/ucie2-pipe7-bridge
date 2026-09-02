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
