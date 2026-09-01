// -----------------------------------------------------------------------------
// tb_ucie2_pipe7 — SV UVM top (SCAFFOLD, PLAN Item 13 seed).
//
// Generates the two independent clocks (PIPE PCLK, FDI lclk), sequences the
// resets, instantiates the DUT + boundary interface (FROZEN Item-0 signal set),
// hands the vif to UVM, and runs the smoke test.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_ucie2_pipe7;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import ucie2_pipe7_uvm_pkg::*;

  localparam int unsigned FDI_W = FDI_DW;
  localparam int unsigned PW    = PIPE_WIDTH_DEFAULT;
  localparam int unsigned MBW   = MB_BUS_WIDTH;

  logic lclk = 0, pclk = 0;
  logic lclk_rst_n = 0, pclk_rst_n = 0;

  // One 2 ns period on both domains (coincident edges) so the bridge is fully
  // synchronous and the directed round-trip is deterministic / cross-sim stable,
  // matching the PyUVM TB (dv/pyuvm/test_roundtrip.py).
  always #1.0 lclk = ~lclk;
  always #1.0 pclk = ~pclk;

  // Reset deasserts at 11 ns — a non-edge time (edges are at even ns) so both
  // simulators agree on the first post-reset cycle.
  initial begin
    lclk_rst_n = 0; pclk_rst_n = 0;
    #11;
    lclk_rst_n = 1; pclk_rst_n = 1;
  end

  ucie2_pipe7_if #(.FDI_W(FDI_W), .PW(PW), .MBW(MBW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  ucie2_pipe7_bridge #(.FDI_W(FDI_W), .PW(PW)) dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    // FDI TX
    .lp_data(vif.lp_data), .lp_valid(vif.lp_valid), .lp_irdy(vif.lp_irdy),
    .pl_trdy(vif.pl_trdy),
    // FDI RX
    .pl_data(vif.pl_data), .pl_valid(vif.pl_valid), .pl_flit_cancel(vif.pl_flit_cancel),
    // FDI state machine
    .lp_state_req(vif.lp_state_req), .pl_state_sts(vif.pl_state_sts),
    .lp_linkerror(vif.lp_linkerror), .pl_stallreq(vif.pl_stallreq),
    .lp_stallack(vif.lp_stallack),
    // FDI rx-active / clock / wake
    .lp_rx_active_req(vif.lp_rx_active_req), .pl_rx_active_sts(vif.pl_rx_active_sts),
    .pl_clk_req(vif.pl_clk_req), .lp_clk_ack(vif.lp_clk_ack),
    .lp_wake_req(vif.lp_wake_req), .pl_wake_ack(vif.pl_wake_ack),
    // Management: PIPE control request
    .req_valid(vif.req_valid), .req_kind(vif.req_kind),
    .req_power_down(vif.req_power_down), .req_rate(vif.req_rate),
    .req_width(vif.req_width), .req_rxwidth(vif.req_rxwidth),
    .busy(vif.busy), .done(vif.done), .req_error(vif.req_error),
    // Management: message-bus request
    .mb_req_valid(vif.mb_req_valid), .mb_req_write(vif.mb_req_write),
    .mb_req_committed(vif.mb_req_committed), .mb_req_addr(vif.mb_req_addr),
    .mb_req_wdata(vif.mb_req_wdata), .mb_req_ready(vif.mb_req_ready),
    .mb_busy(vif.mb_busy), .mb_rsp_valid(vif.mb_rsp_valid),
    .mb_rsp_is_read(vif.mb_rsp_is_read), .mb_rsp_rdata(vif.mb_rsp_rdata),
    .mb_rsp_error(vif.mb_rsp_error),
    // PIPE MAC -> PHY
    .tx_data(vif.tx_data), .tx_data_valid(vif.tx_data_valid),
    .rate(vif.rate), .power_down(vif.power_down), .width(vif.width),
    .rx_width(vif.rx_width), .tx_detect_rx(vif.tx_detect_rx),
    .tx_elec_idle(vif.tx_elec_idle),
    // PIPE PHY -> MAC
    .rx_data(vif.rx_data), .rx_valid(vif.rx_valid), .phy_status(vif.phy_status),
    .rx_status(vif.rx_status), .rx_elec_idle(vif.rx_elec_idle),
    // PIPE message bus
    .m2p_message_bus(vif.m2p_message_bus), .p2m_message_bus(vif.p2m_message_bus),
    // Bridge status
    .block_locked(vif.block_locked), .sync_error(vif.sync_error),
    .in_data_phase(vif.in_data_phase), .rx_overflow(vif.rx_overflow)
  );

  initial begin
    uvm_config_db#(virtual ucie2_pipe7_if)::set(null, "*", "vif", vif);
    run_test("ucie2_roundtrip_test");
  end
endmodule : tb_ucie2_pipe7
