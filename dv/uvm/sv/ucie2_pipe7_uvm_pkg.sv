// -----------------------------------------------------------------------------
// ucie2_pipe7_uvm_pkg — SV UVM environment (PLAN B4).
//
// ucie2_roundtrip_test mirrors dv/pyuvm/test_roundtrip.py EXACTLY (same fixed
// cycle schedule, same 2 ns single-period clocking, same PHY loopback) so the two
// independently-authored TBs track cycle-for-cycle: it emits the canonical
// per-cycle trace (tools/trace_compare.py checks it against the PyUVM trace) and
// self-checks the round-trip (recovered FDI flits == driven, block_locked, no
// sync_error). Signals are sampled #0.1 ns after each edge to read post-edge
// (flop-updated) values, matching cocotb's RisingEdge semantics.
//
// The trace column order MUST match trace_format.TRACE_COLUMNS.
// -----------------------------------------------------------------------------
package ucie2_pipe7_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;

  class ucie2_roundtrip_test extends uvm_test;
    `uvm_component_utils(ucie2_roundtrip_test)

    virtual ucie2_pipe7_if vif;

    localparam int unsigned N_FLITS      = 8;
    localparam int unsigned BRINGUP_LCLK = 8;
    localparam int unsigned RUN_PCLK     = 200;
    localparam int unsigned PW           = PIPE_WIDTH_DEFAULT;
    localparam int unsigned FDIW         = FDI_DW;

    logic [FDIW-1:0] payloads  [N_FLITS];
    logic [PW-1:0]   tx_words  [$];
    logic [FDIW-1:0] recovered [$];

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "virtual interface 'vif' not set in config_db")
    endfunction

    // PHY loopback: rx follows tx by two pclk (matching cocotb VPI write latency).
    // In SV a blocking write at posedge+#0.1 would be visible to the RTL at the
    // next posedge (1-cycle delay). Python VPI writes have ~1 extra cycle of
    // latency, making them visible 2 posedges after the write. Add one extra
    // pclk cycle between sampling and driving so both TBs have the same 2-cycle
    // loopback delay.
    task automatic loopback();
      logic [PW-1:0] cap_data;
      logic          cap_valid;
      forever begin
        @(posedge vif.pclk); #0.1;    // cycle N: sample tx outputs
        cap_data  = vif.tx_data;
        cap_valid = vif.tx_data_valid;
        @(posedge vif.pclk); #0.1;    // cycle N+1: drive → visible to RTL at cycle N+2
        vif.rx_data  = cap_data;
        vif.rx_valid = cap_valid;
      end
    endtask

    // Auto-complete the FDI stall handshake.
    task automatic stall_ack();
      // cocotb's VPI signal writes have ~1-cycle latency relative to the
      // clock edge (the write is queued and applied at the next simulator
      // eval), so lp_stallack driven at cycle N in Python is visible to the
      // RTL only at cycle N+2.  In SV a blocking assignment at #0.1 after
      // posedge would be visible at cycle N+1.  Add one extra lclk+#0.1 wait
      // between sampling and driving so the write lands one cycle later,
      // matching the cocotb effective latency.
      logic captured;
      forever begin
        @(posedge vif.lclk); #0.1;    // cycle N: sample
        captured = vif.pl_stallreq;
        @(posedge vif.lclk); #0.1;    // cycle N+1: drive → visible to RTL at cycle N+2
        vif.lp_stallack = captured;
      end
    endtask

    task automatic cap_tx();
      forever begin
        @(posedge vif.pclk); #0.1;
        if (vif.tx_data_valid) tx_words.push_back(vif.tx_data);
      end
    endtask

    task automatic cap_rx();
      forever begin
        @(posedge vif.lclk); #0.1;
        if (vif.pl_valid) recovered.push_back(vif.pl_data);
      end
    endtask

    // Fixed-schedule stimulus (anchored to reset deassert), matching the PyUVM TB.
    task automatic stimulus();
      vif.lp_state_req = FDI_ACTIVE;
      repeat (BRINGUP_LCLK) @(posedge vif.lclk);
      for (int i = 0; i < N_FLITS; i++) begin
        #0.1;
        vif.lp_data  = payloads[i];
        vif.lp_valid = 1'b1;
        vif.lp_irdy  = 1'b1;
        @(posedge vif.lclk);
      end
      #0.1;
      vif.lp_valid = 1'b0;
      vif.lp_irdy  = 1'b0;
    endtask

    task run_phase(uvm_phase phase);
      int fd;
      string path;
      phase.raise_objection(this);

      // Idle all inputs during reset.
      vif.lp_data = '0; vif.lp_valid = 0; vif.lp_irdy = 0;
      vif.lp_state_req = '0; vif.lp_linkerror = 0; vif.lp_stallack = 0;
      vif.lp_rx_active_req = 0; vif.lp_clk_ack = 0; vif.lp_wake_req = 0;
      vif.req_valid = 0; vif.req_kind = '0; vif.req_power_down = '0;
      vif.req_rate = '0; vif.req_width = '0; vif.req_rxwidth = '0;
      vif.mb_req_valid = 0; vif.mb_req_write = 0; vif.mb_req_committed = 0;
      vif.mb_req_addr = '0; vif.mb_req_wdata = '0;
      vif.rx_data = '0; vif.rx_valid = 0; vif.phy_status = 0;
      vif.rx_status = '0; vif.rx_elec_idle = 0; vif.p2m_message_bus = '0;

      foreach (payloads[i])
        payloads[i] = (128'(16'h1000 + i) << 64) | 128'(32'hABCD0000 + i);

      if (!$value$plusargs("TRACE=%s", path)) path = "bridge.trace";
      fd = $fopen(path, "w");
      if (fd == 0) `uvm_fatal("TRACE", $sformatf("cannot open %s", path));

      // Header — must match trace_format.TRACE_HEADER. %h auto-widths tx_data to
      // PW/4 nibbles (== trace_format's PIPE_WIDTH//4 padding).
      $fwrite(fd,
        "cycle,pl_state_sts,pl_valid,pl_trdy,pl_stallreq,pl_flit_cancel,tx_data_valid,tx_data,rate,power_down\n");

      // Everything starts at reset deassert, like the PyUVM coroutines.
      wait (vif.pclk_rst_n === 1'b1);

      // Cycle 0 is sampled BEFORE the forked tasks start.  This matches
      // cocotb start_soon semantics: cocotb does not run a start_soon task
      // until the current coroutine's first await has fired, so PyUVM's
      // cycle 0 always sees reset-state inputs (lp_state_req==FDI_RESET →
      // pl_stallreq==0).  In SV, forked tasks run in the same delta cycle
      // as the fork statement — stimulus() would immediately drive
      // lp_state_req=FDI_ACTIVE, making pl_stallreq==1 at cycle 0 before
      // the trace loop samples.  Recording cycle 0 here (before the fork)
      // guarantees the same reset-state snapshot in both TBs.
      @(posedge vif.pclk); #0.1;
      $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
        0, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
        vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);

      fork
        loopback();
        stall_ack();
        cap_tx();
        cap_rx();
        stimulus();
      join_none

      for (int cyc = 1; cyc < RUN_PCLK; cyc++) begin
        @(posedge vif.pclk); #0.1;
        $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
          cyc, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
          vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);
      end
      $fclose(fd);

      // ---- Self-checks: round-trip proves data flows ----
      if (vif.sync_error !== 1'b0)
        `uvm_error("RT", "deframer raised sync_error")
      if (vif.block_locked !== 1'b1)
        `uvm_error("RT", "deframer never reached block_locked")
      if (recovered.size() < N_FLITS)
        `uvm_error("RT", $sformatf("only %0d flits recovered (< %0d)",
                                   recovered.size(), N_FLITS))
      else
        for (int i = 0; i < N_FLITS; i++)
          if (recovered[i] !== payloads[i])
            `uvm_error("RT", $sformatf("round-trip mismatch [%0d]: got %h exp %h",
                                       i, recovered[i], payloads[i]))

      `uvm_info("RT", $sformatf("roundtrip: %0d flits, tx %0d words, recovered %0d",
                N_FLITS, tx_words.size(), recovered.size()), UVM_LOW)

      phase.drop_objection(this);
    endtask
  endclass
endpackage : ucie2_pipe7_uvm_pkg
