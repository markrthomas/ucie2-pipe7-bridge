// -----------------------------------------------------------------------------
// b2b_pcie_btx_monitor — bridge B's re-framed PCIe output + bridge A deframer
// health (PLAN H2).
//
// Captures each valid PIPE word bridge B emits (b_tx_data_valid, on pclk) and
// tracks bridge A's block lock / sync_error. Mirrors the PyUVM _mon_btx.
// capture() is forked by the test.
// -----------------------------------------------------------------------------
class b2b_pcie_btx_monitor extends uvm_monitor;
  virtual b2b_pcie_if vif;
  uvm_analysis_port#(bit [PW-1:0]) ap;   // bridge B output words
  int unsigned sync_errors = 0;
  bit          saw_lock    = 1'b0;
  `uvm_component_utils(b2b_pcie_btx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.pclk); #0.1;
      if (vif.b_tx_data_valid) ap.write(vif.b_tx_data);
      if (vif.a_sync_error)    sync_errors++;
      if (vif.a_block_locked)  saw_lock = 1'b1;
    end
  endtask
endclass
