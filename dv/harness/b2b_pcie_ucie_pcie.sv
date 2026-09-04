// -----------------------------------------------------------------------------
// b2b_pcie_ucie_pcie — two ucie2_pipe7_bridge instances joined at their FDI
// (UCIe) ports:   PCIe -> [bridge A] -> UCIe == UCIe -> [bridge B] -> PCIe
//
// A PCIe/PIPE word stream driven into bridge A's PIPE RX is deframed to a
// UCIe/FDI flit, crosses a REAL FDI seam (A.pl_data -> B.lp_data) instead of a
// protocol-layer, and is re-framed by bridge B into a PCIe/PIPE word stream on
// B.tx_data. The external interfaces are PCIe/PIPE on both ends; the UCIe link
// lives in the middle. This is the forward B2B config (join at UCIe).
//
// UNIDIRECTIONAL to start (A->B): bridge A's FDI TX and bridge B's PIPE RX are
// tied idle; the return path (B->A) is future work. BOTH bridges' FDI links are
// brought to ACTIVE internally (lp_state_req=FDI_ACTIVE, lp_stallack=pl_stallreq)
// since neither FDI port is external here. The FDI RX seam has no backpressure
// by spec (crosscheck B), so B.lp_irdy is tied high and A presents each recovered
// flit for one cycle; for the modest default lengths B's TX ingress keeps up.
// All management / msgbus ports are tied idle -> the Gen5 default framing.
// Harness only: NOT part of rtl/, so `make lint` is untouched.
// -----------------------------------------------------------------------------
`default_nettype none

module b2b_pcie_ucie_pcie
  import ucie2_pipe7_pkg::*;
(
  input  wire                          lclk,
  input  wire                          lclk_rst_n,
  input  wire                          pclk,
  input  wire                          pclk_rst_n,

  // ---- Left external: PCIe/PIPE RX word stream into bridge A -----------------
  input  wire [PIPE_WIDTH_DEFAULT-1:0] a_rx_data,
  input  wire                          a_rx_valid,
  output wire                          a_block_locked,
  output wire                          a_sync_error,

  // ---- Middle observation: UCIe flits recovered at the A->B FDI seam --------
  output wire [FDI_DW-1:0]             mid_pl_data,
  output wire                          mid_pl_valid,

  // ---- Right external: PCIe/PIPE TX word stream out of bridge B --------------
  output wire [PIPE_WIDTH_DEFAULT-1:0] b_tx_data,
  output wire                          b_tx_data_valid
);
  localparam int unsigned PW = PIPE_WIDTH_DEFAULT;

  // A->B FDI seam (the recovered flit handed across the UCIe link).
  wire [FDI_DW-1:0] seam_pl_data;
  wire              seam_pl_valid;
  assign mid_pl_data  = seam_pl_data;
  assign mid_pl_valid = seam_pl_valid;

  // Each bridge's FDI stall handshake, looped to self-bring-up its link.
  wire a_pl_stallreq, b_pl_stallreq;

  // ---- Bridge A: PIPE RX in (external left) -> FDI RX out (to seam) ----------
  ucie2_pipe7_bridge u_a (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    // FDI TX (unused on A)
    .lp_data          ('0),
    .lp_valid         (1'b0),
    .lp_irdy          (1'b0),
    .pl_trdy          (),
    // FDI RX (to seam)
    .pl_data          (seam_pl_data),
    .pl_valid         (seam_pl_valid),
    .pl_flit_cancel   (),
    // FDI link: self-bring-up to ACTIVE
    .lp_state_req     (FDI_ACTIVE),
    .pl_state_sts     (),
    .lp_linkerror     (1'b0),
    .pl_stallreq      (a_pl_stallreq),
    .lp_stallack      (a_pl_stallreq),
    .lp_rx_active_req (1'b0),
    .pl_rx_active_sts (),
    .pl_clk_req       (),
    .lp_clk_ack       (1'b0),
    .lp_wake_req      (1'b0),
    .pl_wake_ack      (),
    // Management (idle -> Gen5 default)
    .req_valid        (1'b0),
    .req_kind         (2'b0),
    .req_power_down   (4'b0),
    .req_rate         (4'b0),
    .req_width        (3'b0),
    .req_rxwidth      (3'b0),
    .busy             (),
    .done             (),
    .req_error        (),
    .mb_req_valid     (1'b0),
    .mb_req_write     (1'b0),
    .mb_req_committed (1'b0),
    .mb_req_addr      ('0),
    .mb_req_wdata     ('0),
    .mb_req_ready     (),
    .mb_busy          (),
    .mb_rsp_valid     (),
    .mb_rsp_is_read   (),
    .mb_rsp_rdata     (),
    .mb_rsp_error     (),
    // PIPE TX (unused on A)
    .tx_data          (),
    .tx_data_valid    (),
    .rate             (),
    .power_down       (),
    .width            (),
    .rx_width         (),
    .tx_detect_rx     (),
    .tx_elec_idle     (),
    // PIPE RX (external left)
    .rx_data          (a_rx_data),
    .rx_valid         (a_rx_valid),
    .phy_status       (1'b0),
    .rx_status        (3'b0),
    .rx_elec_idle     (1'b0),
    .m2p_message_bus  (),
    .p2m_message_bus  ('0),
    // Status (observed on A: deframer health)
    .block_locked     (a_block_locked),
    .sync_error       (a_sync_error),
    .in_data_phase    (),
    .rx_overflow      ()
  );

  // ---- Bridge B: FDI TX in (from seam) -> PIPE TX out (external right) -------
  ucie2_pipe7_bridge u_b (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    // FDI TX (from seam; FDI RX has no backpressure so irdy is always high)
    .lp_data          (seam_pl_data),
    .lp_valid         (seam_pl_valid),
    .lp_irdy          (1'b1),
    .pl_trdy          (),
    // FDI RX (unused on B)
    .pl_data          (),
    .pl_valid         (),
    .pl_flit_cancel   (),
    // FDI link: self-bring-up to ACTIVE
    .lp_state_req     (FDI_ACTIVE),
    .pl_state_sts     (),
    .lp_linkerror     (1'b0),
    .pl_stallreq      (b_pl_stallreq),
    .lp_stallack      (b_pl_stallreq),
    .lp_rx_active_req (1'b0),
    .pl_rx_active_sts (),
    .pl_clk_req       (),
    .lp_clk_ack       (1'b0),
    .lp_wake_req      (1'b0),
    .pl_wake_ack      (),
    // Management (idle -> Gen5 default)
    .req_valid        (1'b0),
    .req_kind         (2'b0),
    .req_power_down   (4'b0),
    .req_rate         (4'b0),
    .req_width        (3'b0),
    .req_rxwidth      (3'b0),
    .busy             (),
    .done             (),
    .req_error        (),
    .mb_req_valid     (1'b0),
    .mb_req_write     (1'b0),
    .mb_req_committed (1'b0),
    .mb_req_addr      ('0),
    .mb_req_wdata     ('0),
    .mb_req_ready     (),
    .mb_busy          (),
    .mb_rsp_valid     (),
    .mb_rsp_is_read   (),
    .mb_rsp_rdata     (),
    .mb_rsp_error     (),
    // PIPE TX (external right)
    .tx_data          (b_tx_data),
    .tx_data_valid    (b_tx_data_valid),
    .rate             (),
    .power_down       (),
    .width            (),
    .rx_width         (),
    .tx_detect_rx     (),
    .tx_elec_idle     (),
    // PIPE RX (unused on B)
    .rx_data          ('0),
    .rx_valid         (1'b0),
    .phy_status       (1'b0),
    .rx_status        (3'b0),
    .rx_elec_idle     (1'b0),
    .m2p_message_bus  (),
    .p2m_message_bus  ('0),
    // Status (unused on B)
    .block_locked     (),
    .sync_error       (),
    .in_data_phase    (),
    .rx_overflow      ()
  );

endmodule : b2b_pcie_ucie_pcie

`default_nettype wire
