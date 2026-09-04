// -----------------------------------------------------------------------------
// b2b_ucie_rx_monitor — recovers FDI flits out of bridge B (PLAN H1).
//
// Mirrors fdi_rx_monitor / the PyUVM B2B UCIe rx monitor. capture() is forked by
// the test; #0.1 post-edge sampling matches the other TB.
// -----------------------------------------------------------------------------
class b2b_ucie_rx_monitor extends uvm_monitor;
  virtual b2b_ucie_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) ap;
  `uvm_component_utils(b2b_ucie_rx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.lclk); #0.1;
      if (vif.b_pl_valid) ap.write(vif.b_pl_data);
    end
  endtask
endclass
