// -----------------------------------------------------------------------------
// tb_ucie2_pipe7 — SV UVM top (SCAFFOLD, PLAN Item 13 seed).
//
// Generates the two independent clocks (PIPE PCLK, FDI lclk), sequences the
// resets, instantiates the DUT + boundary interface, hands the vif to UVM, and
// runs the smoke test.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_ucie2_pipe7;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import ucie2_pipe7_uvm_pkg::*;

  localparam int unsigned FLIT_W = FDI_FLIT_W;
  localparam int unsigned PW     = PIPE_WIDTH;

  logic lclk = 0, pclk = 0;
  logic lclk_rst_n = 0, pclk_rst_n = 0;

  // Independent clocks — the DUT crosses between them.
  always #1.5 lclk = ~lclk;   // ~333 MHz
  always #1.0 pclk = ~pclk;   // 500 MHz

  // Reset sequencing: hold both low, release after a few cycles.
  initial begin
    lclk_rst_n = 0; pclk_rst_n = 0;
    #10;
    lclk_rst_n = 1; pclk_rst_n = 1;
  end

  ucie2_pipe7_if #(.FLIT_W(FLIT_W), .PW(PW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  ucie2_pipe7_bridge #(.FLIT_W(FLIT_W), .PW(PW)) dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    .lp_flit(vif.lp_flit), .lp_flit_valid(vif.lp_flit_valid), .lp_valid(vif.lp_valid),
    .pl_trdy(vif.pl_trdy), .lp_state_req(vif.lp_state_req),
    .lp_linkerror(vif.lp_linkerror), .pl_stallreq(vif.pl_stallreq),
    .lp_stallack(vif.lp_stallack),
    .pl_flit(vif.pl_flit), .pl_flit_valid(vif.pl_flit_valid), .pl_valid(vif.pl_valid),
    .pl_state_sts(vif.pl_state_sts),
    .tx_data(vif.tx_data), .tx_data_k(vif.tx_data_k), .tx_data_valid(vif.tx_data_valid),
    .rate(vif.rate), .power_down(vif.power_down), .tx_detect_rx(vif.tx_detect_rx),
    .tx_elec_idle(vif.tx_elec_idle),
    .rx_data(vif.rx_data), .rx_data_k(vif.rx_data_k), .rx_data_valid(vif.rx_data_valid),
    .rx_valid(vif.rx_valid), .phy_status(vif.phy_status), .rx_status(vif.rx_status),
    .rx_elec_idle(vif.rx_elec_idle)
  );

  initial begin
    uvm_config_db#(virtual ucie2_pipe7_if)::set(null, "*", "vif", vif);
    run_test("ucie2_smoke_test");
  end
endmodule : tb_ucie2_pipe7
