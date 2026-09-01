// -----------------------------------------------------------------------------
// pipe_agent — PIPE MAC-facing agent (PLAN item 13).
//
// TX monitor (captures tx_data words) + PHY loopback (rx <- tx via a 1-cycle
// shadow register -> net 2-cycle delay, matching cocotb's VPI write latency so
// the Gen5 128b/130b deframer recovers what the framer sent). Mirrors the PyUVM
// PipeTxMonitor + loopback. Timing tasks forked by the test (proven order).
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

class pipe_agent extends uvm_agent;
  pipe_tx_monitor tx_mon;
  phy_loopback    loopback;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(pipe_agent)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pipe_agent: vif not set")
    tx_mon   = pipe_tx_monitor::type_id::create("tx_mon", this);
    loopback = phy_loopback::type_id::create("loopback", this);
    tx_mon.vif   = vif;
    loopback.vif = vif;
  endfunction
endclass
