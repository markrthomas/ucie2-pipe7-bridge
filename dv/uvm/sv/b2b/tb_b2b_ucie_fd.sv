// -----------------------------------------------------------------------------
// tb_b2b_ucie_fd — SV UVM top for the FULL-DUPLEX B2B "external UCIe" config
// (PLAN H3b / Phase I I8).
//
// Instantiates dv/harness/b2b_ucie_pcie_ucie_fd.sv (two ucie2_pipe7_bridge joined
// at PIPE, both directions live) + the b2b_ucie_fd_if bundle, hands the vif to
// UVM, and runs b2b_ucie_fd_test. One 2 ns period on both domains (coincident
// edges) + reset deassert at 11 ns, identical to tb_b2b_ucie, so the schedule
// matches the PyUVM full-duplex TB.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_b2b_ucie_fd;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import b2b_ucie_fd_uvm_pkg::*;

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

  b2b_ucie_fd_if #(.FDI_W(FDI_W), .PW(PW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  b2b_ucie_pcie_ucie_fd dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    .a_lp_data(vif.a_lp_data), .a_lp_valid(vif.a_lp_valid), .a_lp_irdy(vif.a_lp_irdy),
    .a_pl_trdy(vif.a_pl_trdy),
    .a_lp_state_req(vif.a_lp_state_req), .a_pl_state_sts(vif.a_pl_state_sts),
    .a_lp_stallack(vif.a_lp_stallack), .a_pl_stallreq(vif.a_pl_stallreq),
    .a_pl_data(vif.a_pl_data), .a_pl_valid(vif.a_pl_valid),
    .a_block_locked(vif.a_block_locked), .a_sync_error(vif.a_sync_error),
    .b_lp_data(vif.b_lp_data), .b_lp_valid(vif.b_lp_valid), .b_lp_irdy(vif.b_lp_irdy),
    .b_pl_trdy(vif.b_pl_trdy),
    .b_lp_state_req(vif.b_lp_state_req), .b_pl_state_sts(vif.b_pl_state_sts),
    .b_lp_stallack(vif.b_lp_stallack), .b_pl_stallreq(vif.b_pl_stallreq),
    .b_pl_data(vif.b_pl_data), .b_pl_valid(vif.b_pl_valid),
    .b_block_locked(vif.b_block_locked), .b_sync_error(vif.b_sync_error)
  );

  initial begin
    uvm_config_db#(virtual b2b_ucie_fd_if)::set(null, "*", "vif", vif);
    run_test("b2b_ucie_fd_test");
  end
endmodule : tb_b2b_ucie_fd
