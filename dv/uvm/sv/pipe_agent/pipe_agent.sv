// -----------------------------------------------------------------------------
// pipe_agent — PIPE MAC-facing agent (PLAN item 13).
//
// Assembles the TX monitor + PHY loopback. Mirrors the PyUVM pipe agent. The
// timing tasks are forked by the test (proven order) so the per-cycle trace
// stays byte-identical.
// -----------------------------------------------------------------------------
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
