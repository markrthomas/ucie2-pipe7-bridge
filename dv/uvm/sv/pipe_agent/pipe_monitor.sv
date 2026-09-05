// -----------------------------------------------------------------------------
// pipe_monitor — PIPE MAC-facing TX monitor: captures tx_data words (item 13).
//
// Mirrors the PyUVM PipeTxMonitor. Its capture() task is forked by the test
// (proven order); #0.1 post-edge sampling keeps trace_compare byte-identical.
// -----------------------------------------------------------------------------
class pipe_tx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [PW-1:0]) ap;
  int unsigned w_i;                               // TX-word index (PKT track)
  `uvm_component_utils(pipe_tx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    bit pkt_track;
    bit locked_prev;
    pkt_track = $test$plusargs("PKT_TRACK");      // opt-in; zero sim-time logging only
    forever begin
      @(posedge vif.pclk); #0.1;
      if (vif.tx_data_valid) begin
        ap.write(vif.tx_data);
        if (pkt_track)
          `uvm_info("PKT", $sformatf("TXWORD  pipe word #%0d data=%h @%0t",
                                     w_i, vif.tx_data, $realtime), UVM_LOW)
        w_i++;
      end
      if (pkt_track && vif.block_locked && !locked_prev)
        `uvm_info("PKT", $sformatf("LOCK    deframer reached block_locked @%0t",
                                   $realtime), UVM_LOW)
      locked_prev = vif.block_locked;
      if (pkt_track && vif.sync_error)
        `uvm_info("PKT", $sformatf("SYNCERR deframer sync_error @%0t", $realtime), UVM_LOW)
    end
  endtask
endclass
