// -----------------------------------------------------------------------------
// pipe_monitor — PIPE MAC-facing TX monitor: captures tx_data words (item 13).
//
// Mirrors the PyUVM PipeTxMonitor. Its capture() task is forked by the test
// (proven order); #0.1 post-edge sampling keeps trace_compare byte-identical.
// -----------------------------------------------------------------------------
class pipe_tx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [PW-1:0]) ap;
  `uvm_component_utils(pipe_tx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.pclk); #0.1;
      if (vif.tx_data_valid) ap.write(vif.tx_data);
    end
  endtask
endclass
