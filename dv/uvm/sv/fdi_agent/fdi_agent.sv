// -----------------------------------------------------------------------------
// fdi_agent — FDI controller-facing agent (PLAN item 13).
//
// Assembles the sequencer + driver + RX monitor and connects the driver to the
// sequencer. Mirrors dv/pyuvm/agents/fdi_agent.py. The driver/monitor timing
// tasks are forked by the test (proven order) so the per-cycle trace stays
// byte-identical.
// -----------------------------------------------------------------------------
class fdi_agent extends uvm_agent;
  fdi_sequencer  seqr;
  fdi_driver     driver;
  fdi_rx_monitor rx_mon;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(fdi_agent)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "fdi_agent: vif not set")
    seqr   = fdi_sequencer::type_id::create("seqr", this);
    driver = fdi_driver::type_id::create("driver", this);
    rx_mon = fdi_rx_monitor::type_id::create("rx_mon", this);
    driver.vif = vif;
    rx_mon.vif = vif;
  endfunction
  virtual function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass
