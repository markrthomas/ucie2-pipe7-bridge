// -----------------------------------------------------------------------------
// b2b_ucie_pcie_ucie — two ucie2_pipe7_bridge instances joined at their PIPE
// (PCIe) ports:   UCIe -> [bridge A] -> PCIe == PCIe -> [bridge B] -> UCIe
//
// A UCIe/FDI flit driven into bridge A is framed to a PIPE word stream, crosses
// a REAL PIPE link (A.tx_data -> B.rx_data) instead of the single-bridge PHY
// self-loopback, and is recovered by bridge B as a UCIe/FDI flit on B.pl_data.
// The external interfaces are UCIe/FDI on both ends; the PCIe link lives in the
// middle. This is the "reverse" B2B config (join at PCIe).
//
// UNIDIRECTIONAL to start (A->B): bridge B's FDI TX and bridge A's PIPE RX are
// tied idle; the return path (B->A) is future work. Bridge A's FDI link is
// TB-controlled (a_lp_state_req / a_lp_stallack) so the proven FDI driver
// bring-up is reused verbatim; bridge B's FDI link is brought to ACTIVE
// internally (lp_state_req=FDI_ACTIVE, lp_stallack=pl_stallreq) so its egress
// presents recovered flits without extra TB wiring. All management / msgbus
// ports are tied idle -> the Gen5 default framing, exactly as the single-bridge
// round-trip. Harness only: NOT part of rtl/, so `make lint` is untouched.
// -----------------------------------------------------------------------------
`default_nettype none

module b2b_ucie_pcie_ucie
  import ucie2_pipe7_pkg::*;
(
  input  wire                          lclk,
  input  wire                          lclk_rst_n,
  input  wire                          pclk,
  input  wire                          pclk_rst_n,

  // ---- Left external: UCIe/FDI TX into bridge A + A's link bring-up ----------
  input  wire [FDI_DW-1:0]             a_lp_data,
  input  wire                          a_lp_valid,
  input  wire                          a_lp_irdy,
  output wire                          a_pl_trdy,
  input  wire [3:0]                    a_lp_state_req,
  output wire [3:0]                    a_pl_state_sts,
  input  wire                          a_lp_stallack,
  output wire                          a_pl_stallreq,

  // ---- Middle observation: PIPE word stream on the A->B link ----------------
  output wire [PIPE_WIDTH_DEFAULT-1:0] mid_tx_data,
  output wire                          mid_tx_data_valid,

  // ---- Right external: UCIe/FDI RX recovered out of bridge B ----------------
  output wire [FDI_DW-1:0]             b_pl_data,
  output wire                          b_pl_valid,
  output wire                          b_pl_flit_cancel,
  output wire                          b_block_locked,
  output wire                          b_sync_error
);
  localparam int unsigned PW = PIPE_WIDTH_DEFAULT;

  // A->B PIPE seam (the "wire" between the two dies).
  wire [PW-1:0] seam_tx_data;
  wire          seam_tx_valid;
  assign mid_tx_data       = seam_tx_data;
  assign mid_tx_data_valid = seam_tx_valid;

  // Bridge B's FDI stall handshake, looped to self-bring-up the link to ACTIVE.
  wire b_pl_stallreq;

  // ---- Bridge A: FDI TX in (external left) -> PIPE TX out (to seam) ----------
  ucie2_pipe7_bridge u_a (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    // FDI TX (external left)
    .lp_data          (a_lp_data),
    .lp_valid         (a_lp_valid),
    .lp_irdy          (a_lp_irdy),
    .pl_trdy          (a_pl_trdy),
    // FDI RX (unused on A)
    .pl_data          (),
    .pl_valid         (),
    .pl_flit_cancel   (),
    // FDI link (external left, TB-controlled)
    .lp_state_req     (a_lp_state_req),
    .pl_state_sts     (a_pl_state_sts),
    .lp_linkerror     (1'b0),
    .pl_stallreq      (a_pl_stallreq),
    .lp_stallack      (a_lp_stallack),
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
    // PIPE TX (to seam)
    .tx_data          (seam_tx_data),
    .tx_data_valid    (seam_tx_valid),
    .rate             (),
    .power_down       (),
    .width            (),
    .rx_width         (),
    .tx_detect_rx     (),
    .tx_elec_idle     (),
    // PIPE RX (unused on A)
    .rx_data          ('0),
    .rx_valid         (1'b0),
    .phy_status       (1'b0),
    .rx_status        (3'b0),
    .rx_elec_idle     (1'b0),
    .m2p_message_bus  (),
    .p2m_message_bus  ('0),
    // Status (unused on A)
    .block_locked     (),
    .sync_error       (),
    .in_data_phase    (),
    .rx_overflow      ()
  );

  // ---- Bridge B: PIPE RX in (from seam) -> FDI RX out (external right) -------
  ucie2_pipe7_bridge u_b (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    // FDI TX (unused on B)
    .lp_data          ('0),
    .lp_valid         (1'b0),
    .lp_irdy          (1'b0),
    .pl_trdy          (),
    // FDI RX (external right)
    .pl_data          (b_pl_data),
    .pl_valid         (b_pl_valid),
    .pl_flit_cancel   (b_pl_flit_cancel),
    // FDI link: self-bring-up to ACTIVE (state_req=ACTIVE, stallack=stallreq)
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
    // PIPE TX (unused on B)
    .tx_data          (),
    .tx_data_valid    (),
    .rate             (),
    .power_down       (),
    .width            (),
    .rx_width         (),
    .tx_detect_rx     (),
    .tx_elec_idle     (),
    // PIPE RX (from seam)
    .rx_data          (seam_tx_data),
    .rx_valid         (seam_tx_valid),
    .phy_status       (1'b0),
    .rx_status        (3'b0),
    .rx_elec_idle     (1'b0),
    .m2p_message_bus  (),
    .p2m_message_bus  ('0),
    // Status (observed on B)
    .block_locked     (b_block_locked),
    .sync_error       (b_sync_error),
    .in_data_phase    (),
    .rx_overflow      ()
  );

endmodule : b2b_ucie_pcie_ucie

`default_nettype wire
