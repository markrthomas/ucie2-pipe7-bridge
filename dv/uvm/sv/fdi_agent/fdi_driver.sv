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
    int unsigned n_flits;
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    vif.lp_state_req = FDI_ACTIVE;
    repeat (BRINGUP_LCLK) @(posedge vif.lclk);
    for (int i = 0; i < n_flits; i++) begin
      seq_item_port.get_next_item(req);          // zero sim time
      #0.1;
      vif.lp_data  = req.data;
      vif.lp_valid = 1'b1;
      vif.lp_irdy  = 1'b1;
      // FDI flow control: a flit transfers only when lp_valid & lp_irdy & pl_trdy.
      // Hold it (signals stay asserted) until pl_trdy so a burst longer than the
      // internal FIFO never drops flits; for short bursts pl_trdy stays high and
      // the schedule is unchanged. Mirrors the PyUVM driver's pl_trdy gate.
      do begin @(posedge vif.lclk); #0.1; end while (!vif.pl_trdy);
      drv_ap.write(req.data);                     // accepted this cycle
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
