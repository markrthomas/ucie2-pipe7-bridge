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
