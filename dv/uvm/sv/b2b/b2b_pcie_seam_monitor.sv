// -----------------------------------------------------------------------------
// b2b_pcie_seam_monitor — flits recovered at the A->B UCIe seam (PLAN H2).
//
// Captures each recovered flit bridge A hands across the FDI seam (mid_pl_valid),
// on lclk. Mirrors the PyUVM _mon_seam. capture() is forked by the test.
// -----------------------------------------------------------------------------
class b2b_pcie_seam_monitor extends uvm_monitor;
  virtual b2b_pcie_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) ap;
  `uvm_component_utils(b2b_pcie_seam_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.lclk); #0.1;
      if (vif.mid_pl_valid) ap.write(vif.mid_pl_data);
    end
  endtask
endclass
