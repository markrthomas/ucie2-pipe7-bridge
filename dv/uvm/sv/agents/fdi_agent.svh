// -----------------------------------------------------------------------------
// fdi_agent — FDI controller-facing agent (PLAN item 13).
//
// Sequencer + driver (bring-up + directed flit drive on the proven fixed
// schedule) + RX monitor (recovers pl_data) + stall-ack responder. Mirrors
// dv/pyuvm/agents/fdi_agent.py. The timing tasks (drive/stall_ack/capture) are
// forked by the test in the proven order so the per-cycle trace stays
// byte-identical; get_next_item/item_done are zero sim-time, so routing the
// payloads through the sequencer does not perturb the cycle schedule.
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
