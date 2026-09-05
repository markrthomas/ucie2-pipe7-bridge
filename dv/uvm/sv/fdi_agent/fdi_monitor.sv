// -----------------------------------------------------------------------------
// fdi_monitor — FDI RX monitor: recovers pl_data flits (PLAN item 13).
//
// Mirrors dv/pyuvm/agents/fdi_agent.py's RX monitor. Its capture() task is forked
// by the test in the proven order; #0.1 post-edge sampling keeps the recovered
// stream (and trace_compare) byte-identical.
// -----------------------------------------------------------------------------
class fdi_rx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) ap;
  int unsigned rx_i;                              // recovered-flit index (PKT track)
  `uvm_component_utils(fdi_rx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    bit pkt_track;
    pkt_track = $test$plusargs("PKT_TRACK");      // opt-in; zero sim-time logging only
    forever begin
      @(posedge vif.lclk); #0.1;
      if (vif.pl_valid) begin
        ap.write(vif.pl_data);
        if (pkt_track)
          `uvm_info("PKT", $sformatf("RECOVER fdi flit #%0d data=%h @%0t",
                                     rx_i, vif.pl_data, $realtime), UVM_LOW)
        rx_i++;
      end
    end
  endtask
endclass
