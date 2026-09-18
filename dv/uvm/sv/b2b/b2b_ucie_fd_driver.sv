// -----------------------------------------------------------------------------
// b2b_ucie_fd_driver — sided FDI TX driver + stall-ack responder (Phase I I8).
//
// One class, two instances: `is_b`=0 drives bridge A's FDI TX (the forward
// direction), `is_b`=1 drives bridge B's FDI TX (the reverse direction). Same
// recipe as the half-duplex b2b_ucie_driver -- request FDI_ACTIVE, BRINGUP_LCLK
// bubbles, one flit per lclk honoring `pl_trdy` backpressure -- but the signal set
// is selected by `is_b` (SV has no dynamic field access, so the two sides branch).
// drive()/stall_ack() are forked by the test; get_next_item/item_done are 0-time.
// Publishes each driven flit on drv_ap for the scoreboard.
// -----------------------------------------------------------------------------
class b2b_ucie_fd_driver extends uvm_driver#(fdi_flit_item);
  virtual b2b_ucie_fd_if vif;
  bit                    is_b;   // 0 = drive A (forward), 1 = drive B (reverse)
  uvm_analysis_port#(bit [FDIW-1:0]) drv_ap;
  `uvm_component_utils(b2b_ucie_fd_driver)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    drv_ap = new("drv_ap", this);
  endfunction

  virtual task drive();
    int unsigned n_flits;
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    if (is_b) vif.b_lp_state_req = FDI_ACTIVE;
    else      vif.a_lp_state_req = FDI_ACTIVE;
    repeat (BRINGUP_LCLK) @(posedge vif.lclk);
    for (int i = 0; i < n_flits; i++) begin
      seq_item_port.get_next_item(req);
      #0.1;
      if (is_b) begin
        vif.b_lp_data = req.data; vif.b_lp_valid = 1'b1; vif.b_lp_irdy = 1'b1;
        do begin @(posedge vif.lclk); #0.1; end while (!vif.b_pl_trdy);
      end else begin
        vif.a_lp_data = req.data; vif.a_lp_valid = 1'b1; vif.a_lp_irdy = 1'b1;
        do begin @(posedge vif.lclk); #0.1; end while (!vif.a_pl_trdy);
      end
      drv_ap.write(req.data);
      seq_item_port.item_done();
    end
    #0.1;
    if (is_b) begin vif.b_lp_valid = 1'b0; vif.b_lp_irdy = 1'b0; end
    else      begin vif.a_lp_valid = 1'b0; vif.a_lp_irdy = 1'b0; end
  endtask

  // Auto-complete this side's FDI stall handshake (sample N, drive N+1).
  virtual task stall_ack();
    logic captured;
    forever begin
      @(posedge vif.lclk); #0.1;
      captured = is_b ? vif.b_pl_stallreq : vif.a_pl_stallreq;
      @(posedge vif.lclk); #0.1;
      if (is_b) vif.b_lp_stallack = captured;
      else      vif.a_lp_stallack = captured;
    end
  endtask
endclass
