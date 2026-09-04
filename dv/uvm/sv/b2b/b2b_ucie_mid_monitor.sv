// -----------------------------------------------------------------------------
// b2b_ucie_mid_monitor — middle PIPE word stream + bridge B deframer health (H1).
//
// Captures each valid PIPE word on the A->B link and tracks bridge B's block lock
// / sync_error (mirrors the PyUVM _mon_mid). capture() is forked by the test.
// -----------------------------------------------------------------------------
class b2b_ucie_mid_monitor extends uvm_monitor;
  virtual b2b_ucie_if vif;
  uvm_analysis_port#(bit [PW-1:0]) ap;   // middle PIPE words
  int unsigned sync_errors = 0;
  bit          saw_lock    = 1'b0;
  `uvm_component_utils(b2b_ucie_mid_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.pclk); #0.1;
      if (vif.mid_tx_data_valid) ap.write(vif.mid_tx_data);
      if (vif.b_sync_error)      sync_errors++;
      if (vif.b_block_locked)    saw_lock = 1'b1;
    end
  endtask
endclass
