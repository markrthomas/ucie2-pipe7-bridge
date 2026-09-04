// -----------------------------------------------------------------------------
// b2b_ucie_pcie_ucie_fd — FULL-DUPLEX B2B "external UCIe" config (PLAN H3).
//
// Two ucie2_pipe7_bridge joined at PIPE, both directions live:
//   forward : a_lp (FDI into A) -> A.tx -> B.rx -> b_pl (FDI out of B)
//   reverse : b_lp (FDI into B) -> B.tx -> A.rx -> a_pl (FDI out of A)
// Both FDI links are TB-controlled (each end drives + recovers). Superset of the
// unidirectional b2b_ucie_pcie_ucie (kept separate so that top / the SV UVM tb
// are untouched). Management/msgbus tied idle -> Gen5 default.
// -----------------------------------------------------------------------------
`default_nettype none

module b2b_ucie_pcie_ucie_fd
  import ucie2_pipe7_pkg::*;
(
  input  wire                          lclk, lclk_rst_n, pclk, pclk_rst_n,
  // Left (bridge A) UCIe: FDI TX in + link + FDI RX out (reverse recovery)
  input  wire [FDI_DW-1:0]             a_lp_data,
  input  wire                          a_lp_valid, a_lp_irdy,
  output wire                          a_pl_trdy,
  input  wire [3:0]                    a_lp_state_req,
  output wire [3:0]                    a_pl_state_sts,
  input  wire                          a_lp_stallack,
  output wire                          a_pl_stallreq,
  output wire [FDI_DW-1:0]             a_pl_data,
  output wire                          a_pl_valid,
  output wire                          a_block_locked, a_sync_error,
  // Right (bridge B) UCIe: FDI TX in + link + FDI RX out (forward recovery)
  input  wire [FDI_DW-1:0]             b_lp_data,
  input  wire                          b_lp_valid, b_lp_irdy,
  output wire                          b_pl_trdy,
  input  wire [3:0]                    b_lp_state_req,
  output wire [3:0]                    b_pl_state_sts,
  input  wire                          b_lp_stallack,
  output wire                          b_pl_stallreq,
  output wire [FDI_DW-1:0]             b_pl_data,
  output wire                          b_pl_valid,
  output wire                          b_block_locked, b_sync_error
);
  localparam int unsigned PW = PIPE_WIDTH_DEFAULT;
  wire [PW-1:0] a_tx, b_tx;          // A->B and B->A PIPE seams
  wire          a_tx_v, b_tx_v;

  ucie2_pipe7_bridge u_a (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    .lp_data(a_lp_data), .lp_valid(a_lp_valid), .lp_irdy(a_lp_irdy), .pl_trdy(a_pl_trdy),
    .pl_data(a_pl_data), .pl_valid(a_pl_valid), .pl_flit_cancel(),
    .lp_state_req(a_lp_state_req), .pl_state_sts(a_pl_state_sts),
    .lp_linkerror(1'b0), .pl_stallreq(a_pl_stallreq), .lp_stallack(a_lp_stallack),
    .lp_rx_active_req(1'b0), .pl_rx_active_sts(), .pl_clk_req(), .lp_clk_ack(1'b0),
    .lp_wake_req(1'b0), .pl_wake_ack(),
    .req_valid(1'b0), .req_kind(2'b0), .req_power_down(4'b0), .req_rate(4'b0),
    .req_width(3'b0), .req_rxwidth(3'b0), .busy(), .done(), .req_error(),
    .mb_req_valid(1'b0), .mb_req_write(1'b0), .mb_req_committed(1'b0),
    .mb_req_addr('0), .mb_req_wdata('0), .mb_req_ready(), .mb_busy(),
    .mb_rsp_valid(), .mb_rsp_is_read(), .mb_rsp_rdata(), .mb_rsp_error(),
    .tx_data(a_tx), .tx_data_valid(a_tx_v), .rate(), .power_down(), .width(),
    .rx_width(), .tx_detect_rx(), .tx_elec_idle(),
    .rx_data(b_tx), .rx_valid(b_tx_v), .phy_status(1'b0), .rx_status(3'b0),
    .rx_elec_idle(1'b0), .m2p_message_bus(), .p2m_message_bus('0),
    .block_locked(a_block_locked), .sync_error(a_sync_error),
    .in_data_phase(), .rx_overflow()
  );

  ucie2_pipe7_bridge u_b (
    .lclk, .lclk_rst_n, .pclk, .pclk_rst_n,
    .lp_data(b_lp_data), .lp_valid(b_lp_valid), .lp_irdy(b_lp_irdy), .pl_trdy(b_pl_trdy),
    .pl_data(b_pl_data), .pl_valid(b_pl_valid), .pl_flit_cancel(),
    .lp_state_req(b_lp_state_req), .pl_state_sts(b_pl_state_sts),
    .lp_linkerror(1'b0), .pl_stallreq(b_pl_stallreq), .lp_stallack(b_lp_stallack),
    .lp_rx_active_req(1'b0), .pl_rx_active_sts(), .pl_clk_req(), .lp_clk_ack(1'b0),
    .lp_wake_req(1'b0), .pl_wake_ack(),
    .req_valid(1'b0), .req_kind(2'b0), .req_power_down(4'b0), .req_rate(4'b0),
    .req_width(3'b0), .req_rxwidth(3'b0), .busy(), .done(), .req_error(),
    .mb_req_valid(1'b0), .mb_req_write(1'b0), .mb_req_committed(1'b0),
    .mb_req_addr('0), .mb_req_wdata('0), .mb_req_ready(), .mb_busy(),
    .mb_rsp_valid(), .mb_rsp_is_read(), .mb_rsp_rdata(), .mb_rsp_error(),
    .tx_data(b_tx), .tx_data_valid(b_tx_v), .rate(), .power_down(), .width(),
    .rx_width(), .tx_detect_rx(), .tx_elec_idle(),
    .rx_data(a_tx), .rx_valid(a_tx_v), .phy_status(1'b0), .rx_status(3'b0),
    .rx_elec_idle(1'b0), .m2p_message_bus(), .p2m_message_bus('0),
    .block_locked(b_block_locked), .sync_error(b_sync_error),
    .in_data_phase(), .rx_overflow()
  );
endmodule : b2b_ucie_pcie_ucie_fd

`default_nettype wire
