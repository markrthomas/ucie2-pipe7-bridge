// -----------------------------------------------------------------------------
// b2b_ucie_fd_monitor — sided FDI RX recovery monitor + link health (Phase I I8).
//
// One class, two instances: `at_b`=1 recovers the FORWARD stream out of bridge B
// (b_pl_*), `at_b`=0 recovers the REVERSE stream out of bridge A (a_pl_*). Also
// tracks that side's block lock / sync_error (from the harness status outputs).
// #0.1 post-edge sampling matches the driver + the PyUVM TB. capture() is forked.
// -----------------------------------------------------------------------------
class b2b_ucie_fd_monitor extends uvm_monitor;
  virtual b2b_ucie_fd_if vif;
  bit                    at_b;   // 1 = recover at B (forward), 0 = recover at A (reverse)
  uvm_analysis_port#(bit [FDIW-1:0]) ap;
  int unsigned sync_errors = 0;
  bit          saw_lock    = 1'b0;
  `uvm_component_utils(b2b_ucie_fd_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.lclk); #0.1;
      if (at_b) begin
        if (vif.b_pl_valid)    ap.write(vif.b_pl_data);
        if (vif.b_sync_error)  sync_errors++;
        if (vif.b_block_locked) saw_lock = 1'b1;
      end else begin
        if (vif.a_pl_valid)    ap.write(vif.a_pl_data);
        if (vif.a_sync_error)  sync_errors++;
        if (vif.a_block_locked) saw_lock = 1'b1;
      end
    end
  endtask
endclass
