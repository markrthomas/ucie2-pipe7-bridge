// -----------------------------------------------------------------------------
// b2b_ucie_driver — FDI TX driver + stall-ack responder for bridge A (PLAN H1).
//
// Mirrors fdi_driver / the PyUVM B2B UCIe driver: request FDI_ACTIVE, BRINGUP_LCLK
// bubbles, then one flit per lclk honoring a_pl_trdy backpressure, then deassert.
// Publishes each driven flit for the scoreboard. drive()/stall_ack() are forked by
// the test. get_next_item/item_done are zero sim-time.
// -----------------------------------------------------------------------------
class b2b_ucie_driver extends uvm_driver#(fdi_flit_item);
  virtual b2b_ucie_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) drv_ap;
  `uvm_component_utils(b2b_ucie_driver)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    drv_ap = new("drv_ap", this);
  endfunction

  virtual task drive();
    int unsigned n_flits;
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    vif.a_lp_state_req = FDI_ACTIVE;
    repeat (BRINGUP_LCLK) @(posedge vif.lclk);
    for (int i = 0; i < n_flits; i++) begin
      seq_item_port.get_next_item(req);
      #0.1;
      vif.a_lp_data  = req.data;
      vif.a_lp_valid = 1'b1;
      vif.a_lp_irdy  = 1'b1;
      do begin @(posedge vif.lclk); #0.1; end while (!vif.a_pl_trdy);
      drv_ap.write(req.data);
      seq_item_port.item_done();
    end
    #0.1;
    vif.a_lp_valid = 1'b0;
    vif.a_lp_irdy  = 1'b0;
  endtask

  // Auto-complete bridge A's FDI stall handshake (sample N, drive N+1).
  virtual task stall_ack();
    logic captured;
    forever begin
      @(posedge vif.lclk); #0.1;
      captured = vif.a_pl_stallreq;
      @(posedge vif.lclk); #0.1;
      vif.a_lp_stallack = captured;
    end
  endtask
endclass
