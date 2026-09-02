// -----------------------------------------------------------------------------
// phy_loopback — PIPE PHY loopback: rx <- tx via a 1-cycle shadow (item 13).
//
// Net 2-cycle delay, matching cocotb's VPI write latency so the Gen5 128b/130b
// deframer recovers what the framer sent. Mirrors the PyUVM loopback. Its run()
// task is forked by the test (proven order) so trace_compare stays byte-identical.
// -----------------------------------------------------------------------------
class phy_loopback extends uvm_component;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(phy_loopback)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  // Drive the PREVIOUS cycle's capture at each edge (1-cycle shadow register) so
  // rx = tx from N-1 lands at N+1 = a net 2-cycle delay. Covers every cycle (no
  // skipped slots), preserving block alignment for the deframer.
  virtual task run();
    logic [PW-1:0] cap_data  = '0;
    logic          cap_valid = 1'b0;
    forever begin
      @(posedge vif.pclk); #0.1;
      vif.rx_data  = cap_data;
      vif.rx_valid = cap_valid;
      cap_data  = vif.tx_data;
      cap_valid = vif.tx_data_valid;
    end
  endtask
endclass
