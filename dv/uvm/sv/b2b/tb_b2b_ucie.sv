// -----------------------------------------------------------------------------
// tb_b2b_ucie — SV UVM top for the B2B "external UCIe" config (PLAN H1).
//
// Instantiates the dv/harness B2B wrapper (two ucie2_pipe7_bridge joined at PIPE)
// + the b2b_ucie_if bundle, hands the vif to UVM, and runs b2b_ucie_test. One
// 2 ns period on both domains (coincident edges) + reset deassert at 11 ns,
// identical to tb_ucie2_pipe7, so the schedule matches the PyUVM B2B TB.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_b2b_ucie;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import b2b_ucie_uvm_pkg::*;

  localparam int unsigned FDI_W = FDI_DW;
  localparam int unsigned PW    = PIPE_WIDTH_DEFAULT;

  logic lclk = 0, pclk = 0;
  logic lclk_rst_n = 0, pclk_rst_n = 0;
  always #1.0 lclk = ~lclk;
  always #1.0 pclk = ~pclk;
  initial begin
    lclk_rst_n = 0; pclk_rst_n = 0;
    #11;
    lclk_rst_n = 1; pclk_rst_n = 1;
  end

  b2b_ucie_if #(.FDI_W(FDI_W), .PW(PW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  b2b_ucie_pcie_ucie dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    .a_lp_data(vif.a_lp_data), .a_lp_valid(vif.a_lp_valid), .a_lp_irdy(vif.a_lp_irdy),
    .a_pl_trdy(vif.a_pl_trdy),
    .a_lp_state_req(vif.a_lp_state_req), .a_pl_state_sts(vif.a_pl_state_sts),
    .a_lp_stallack(vif.a_lp_stallack), .a_pl_stallreq(vif.a_pl_stallreq),
    .mid_tx_data(vif.mid_tx_data), .mid_tx_data_valid(vif.mid_tx_data_valid),
    .b_pl_data(vif.b_pl_data), .b_pl_valid(vif.b_pl_valid),
    .b_pl_flit_cancel(vif.b_pl_flit_cancel),
    .b_block_locked(vif.b_block_locked), .b_sync_error(vif.b_sync_error)
  );

  initial begin
    uvm_config_db#(virtual b2b_ucie_if)::set(null, "*", "vif", vif);
    run_test("b2b_ucie_test");
  end
endmodule : tb_b2b_ucie
