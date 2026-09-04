// -----------------------------------------------------------------------------
// b2b_pcie_ucie_pcie_fd — FULL-DUPLEX B2B "external PCIe" config (PLAN H3).
//
// Two ucie2_pipe7_bridge joined at FDI, both directions live:
//   forward : a_rx (PIPE into A) -> A.pl -> B.lp -> b_tx (PIPE out of B)
//   reverse : b_rx (PIPE into B) -> B.pl -> A.lp -> a_tx (PIPE out of A)
// Both FDI links self-bring-up to ACTIVE (neither FDI port is external). Superset
// of the unidirectional b2b_pcie_ucie_pcie (kept separate). Management tied idle.
// -----------------------------------------------------------------------------
`default_nettype none

module b2b_pcie_ucie_pcie_fd
  import ucie2_pipe7_pkg::*;
(
  input  wire                          lclk, lclk_rst_n, pclk, pclk_rst_n,
  // Left (bridge A) PCIe: PIPE RX in (forward) + PIPE TX out (reverse)
  input  wire [PIPE_WIDTH_DEFAULT-1:0] a_rx_data,
  input  wire                          a_rx_valid,
  output wire [PIPE_WIDTH_DEFAULT-1:0] a_tx_data,
  output wire                          a_tx_data_valid,
  output wire                          a_block_locked, a_sync_error,
  // Right (bridge B) PCIe: PIPE RX in (reverse) + PIPE TX out (forward)
  input  wire [PIPE_WIDTH_DEFAULT-1:0] b_rx_data,
  input  wire                          b_rx_valid,
  output wire [PIPE_WIDTH_DEFAULT-1:0] b_tx_data,
  output wire                          b_tx_data_valid,
  output wire                          b_block_locked, b_sync_error
);
  localparam int unsigned PW = PIPE_WIDTH_DEFAULT;
  wire [FDI_DW-1:0] a2b, b2a;        // A.pl->B.lp and B.pl->A.lp FDI seams
  wire              a2b_v, b2a_v;
  wire              a_stall, b_stall;

  ucie2_pipe7_bridge u_a (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    .lp_data(b2a), .lp_valid(b2a_v), .lp_irdy(1'b1), .pl_trdy(),
    .pl_data(a2b), .pl_valid(a2b_v), .pl_flit_cancel(),
    .lp_state_req(FDI_ACTIVE), .pl_state_sts(),
    .lp_linkerror(1'b0), .pl_stallreq(a_stall), .lp_stallack(a_stall),
    .lp_rx_active_req(1'b0), .pl_rx_active_sts(), .pl_clk_req(), .lp_clk_ack(1'b0),
    .lp_wake_req(1'b0), .pl_wake_ack(),
    .req_valid(1'b0), .req_kind(2'b0), .req_power_down(4'b0), .req_rate(4'b0),
    .req_width(3'b0), .req_rxwidth(3'b0), .busy(), .done(), .req_error(),
    .mb_req_valid(1'b0), .mb_req_write(1'b0), .mb_req_committed(1'b0),
    .mb_req_addr('0), .mb_req_wdata('0), .mb_req_ready(), .mb_busy(),
    .mb_rsp_valid(), .mb_rsp_is_read(), .mb_rsp_rdata(), .mb_rsp_error(),
    .tx_data(a_tx_data), .tx_data_valid(a_tx_data_valid), .rate(), .power_down(),
    .width(), .rx_width(), .tx_detect_rx(), .tx_elec_idle(),
    .rx_data(a_rx_data), .rx_valid(a_rx_valid), .phy_status(1'b0), .rx_status(3'b0),
    .rx_elec_idle(1'b0), .m2p_message_bus(), .p2m_message_bus('0),
    .block_locked(a_block_locked), .sync_error(a_sync_error),
    .in_data_phase(), .rx_overflow()
  );

  ucie2_pipe7_bridge u_b (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    .lp_data(a2b), .lp_valid(a2b_v), .lp_irdy(1'b1), .pl_trdy(),
    .pl_data(b2a), .pl_valid(b2a_v), .pl_flit_cancel(),
    .lp_state_req(FDI_ACTIVE), .pl_state_sts(),
    .lp_linkerror(1'b0), .pl_stallreq(b_stall), .lp_stallack(b_stall),
    .lp_rx_active_req(1'b0), .pl_rx_active_sts(), .pl_clk_req(), .lp_clk_ack(1'b0),
    .lp_wake_req(1'b0), .pl_wake_ack(),
    .req_valid(1'b0), .req_kind(2'b0), .req_power_down(4'b0), .req_rate(4'b0),
    .req_width(3'b0), .req_rxwidth(3'b0), .busy(), .done(), .req_error(),
    .mb_req_valid(1'b0), .mb_req_write(1'b0), .mb_req_committed(1'b0),
    .mb_req_addr('0), .mb_req_wdata('0), .mb_req_ready(), .mb_busy(),
    .mb_rsp_valid(), .mb_rsp_is_read(), .mb_rsp_rdata(), .mb_rsp_error(),
    .tx_data(b_tx_data), .tx_data_valid(b_tx_data_valid), .rate(), .power_down(),
    .width(), .rx_width(), .tx_detect_rx(), .tx_elec_idle(),
    .rx_data(b_rx_data), .rx_valid(b_rx_valid), .phy_status(1'b0), .rx_status(3'b0),
    .rx_elec_idle(1'b0), .m2p_message_bus(), .p2m_message_bus('0),
    .block_locked(b_block_locked), .sync_error(b_sync_error),
    .in_data_phase(), .rx_overflow()
  );
endmodule : b2b_pcie_ucie_pcie_fd

`default_nettype wire
