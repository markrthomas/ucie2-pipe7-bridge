// -----------------------------------------------------------------------------
// b2b_pcie_fd_monitor — sided far-PIPE-TX recovery + deframer health (Phase I I8b).
//
// One class, two instances, one per direction:
//   `fwd`=1 : recovers the FORWARD output at bridge B (b_tx_data_valid) and tracks
//             the FORWARD deframer -- bridge A -- health (a_block_locked/a_sync_error);
//   `fwd`=0 : recovers the REVERSE output at bridge A (a_tx_data_valid) and tracks
//             the REVERSE deframer -- bridge B -- health (b_block_locked/b_sync_error).
// (In this PCIe config each direction's input bridge is the one that deframes.)
// #0.1 post-edge pclk sampling matches the driver + the PyUVM TB. capture() is
// forked. Mirrors the PyUVM _mon.
// -----------------------------------------------------------------------------
class b2b_pcie_fd_monitor extends uvm_monitor;
  virtual b2b_pcie_fd_if vif;
  bit                    fwd;   // 1 = forward (out at B), 0 = reverse (out at A)
  uvm_analysis_port#(bit [PW-1:0]) ap;   // far-end re-framed output words
  int unsigned sync_errors = 0;
  bit          saw_lock    = 1'b0;
  `uvm_component_utils(b2b_pcie_fd_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.pclk); #0.1;
      if (fwd) begin
        if (vif.b_tx_data_valid) ap.write(vif.b_tx_data);
        if (vif.a_sync_error)    sync_errors++;
        if (vif.a_block_locked)  saw_lock = 1'b1;
      end else begin
        if (vif.a_tx_data_valid) ap.write(vif.a_tx_data);
        if (vif.b_sync_error)    sync_errors++;
        if (vif.b_block_locked)  saw_lock = 1'b1;
      end
    end
  endtask
endclass
