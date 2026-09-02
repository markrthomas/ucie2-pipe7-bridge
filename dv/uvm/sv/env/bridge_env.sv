// -----------------------------------------------------------------------------
// bridge_env — FDI agent + PIPE agent + scoreboard, analysis wiring (item 13).
//
// Mirrors dv/pyuvm/env.py. The test forks the components' timing tasks (loopback,
// stall_ack, tx/rx capture, drive) in the proven order and emits the per-cycle
// trace itself, so the byte-identical trace_compare gate is preserved.
// -----------------------------------------------------------------------------
class bridge_env extends uvm_env;
  fdi_agent         agent;
  pipe_agent        pipe;
  bridge_scoreboard sb;
  virtual ucie2_pipe7_if vif;

  `uvm_component_utils(bridge_env)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "bridge_env: vif not set")
    agent = fdi_agent::type_id::create("agent", this);
    pipe  = pipe_agent::type_id::create("pipe", this);
    sb    = bridge_scoreboard::type_id::create("sb", this);
    sb.vif = vif;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agent.driver.drv_ap.connect(sb.exp_ap);
    agent.rx_mon.ap.connect(sb.rx_ap);
    pipe.tx_mon.ap.connect(sb.tx_ap);
  endfunction
endclass
