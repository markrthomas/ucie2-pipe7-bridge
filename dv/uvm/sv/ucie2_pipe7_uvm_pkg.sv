// -----------------------------------------------------------------------------
// ucie2_pipe7_uvm_pkg — SV UVM environment (SCAFFOLD, PLAN Item 13 seed).
//
// Today this holds one smoke test that resets the DUT, samples the boundary for
// N PCLK cycles, and writes the canonical per-cycle trace (same column order as
// dv/common/models/trace_format.py) so tools/trace_compare.py can prove the SV
// UVM and PyUVM environments track cycle-for-cycle. Phase D replaces the body
// with real agents/sequencer/monitor/scoreboard.
//
// The trace column order below MUST match trace_format.TRACE_COLUMNS.
// -----------------------------------------------------------------------------
package ucie2_pipe7_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Number of PCLK cycles the smoke traces (keep == PyUVM smoke N_CYCLES).
  localparam int unsigned SMOKE_CYCLES = 64;

  class ucie2_smoke_test extends uvm_test;
    `uvm_component_utils(ucie2_smoke_test)

    virtual ucie2_pipe7_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface 'vif' not set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      int fd;
      string path;
      phase.raise_objection(this);

      if (!$value$plusargs("TRACE=%s", path)) path = "bridge.trace";
      fd = $fopen(path, "w");
      if (fd == 0) `uvm_fatal("TRACE", $sformatf("cannot open %s", path));

      // Drive FDI/PIPE/management inputs to a defined idle and pulse both resets.
      vif.lp_data = '0; vif.lp_valid = 0; vif.lp_irdy = 0;
      vif.lp_state_req = '0; vif.lp_linkerror = 0; vif.lp_stallack = 0;
      vif.lp_rx_active_req = 0; vif.lp_clk_ack = 0; vif.lp_wake_req = 0;
      vif.req_valid = 0; vif.req_kind = '0; vif.req_power_down = '0;
      vif.req_rate = '0; vif.req_width = '0; vif.req_rxwidth = '0;
      vif.mb_req_valid = 0; vif.mb_req_write = 0; vif.mb_req_committed = 0;
      vif.mb_req_addr = '0; vif.mb_req_wdata = '0;
      vif.rx_data = '0; vif.rx_valid = 0; vif.phy_status = 0;
      vif.rx_status = '0; vif.rx_elec_idle = 0; vif.p2m_message_bus = '0;

      // Header — must match trace_format.TRACE_HEADER.
      $fwrite(fd,
        "cycle,pl_state_sts,pl_valid,pl_trdy,pl_stallreq,pl_flit_cancel,tx_data_valid,tx_data,rate,power_down\n");

      // Wait for reset deassert (driven by the tb), then trace SMOKE_CYCLES.
      // %h auto-zero-pads tx_data to its vector width (PW/4 nibbles), matching
      // trace_format.format_row's PIPE_WIDTH//4 padding.
      wait (vif.pclk_rst_n === 1'b1);
      for (int cyc = 0; cyc < SMOKE_CYCLES; cyc++) begin
        @(posedge vif.pclk);
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
          cyc, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
          vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);
      end
      $fclose(fd);
      `uvm_info("SMOKE", $sformatf("wrote %0d-cycle trace to %s", SMOKE_CYCLES, path),
                UVM_LOW)

      phase.drop_objection(this);
    endtask
  endclass
endpackage : ucie2_pipe7_uvm_pkg
