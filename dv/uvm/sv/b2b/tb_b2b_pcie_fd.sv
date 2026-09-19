// -----------------------------------------------------------------------------
// tb_b2b_pcie_fd — SV UVM top for the FULL-DUPLEX B2B "external PCIe" config
// (PLAN H3b / Phase I I8b).
//
// Instantiates dv/harness/b2b_pcie_ucie_pcie_fd.sv (two ucie2_pipe7_bridge joined
// at FDI, both directions live) + the b2b_pcie_fd_if bundle, hands the vif to UVM,
// and runs b2b_pcie_fd_test. One 2 ns period on both domains (coincident edges) +
// reset deassert at 11 ns, identical to tb_b2b_pcie, so the schedule matches the
// PyUVM full-duplex TB.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_b2b_pcie_fd;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import b2b_pcie_fd_uvm_pkg::*;

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

  b2b_pcie_fd_if #(.FDI_W(FDI_W), .PW(PW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  b2b_pcie_ucie_pcie_fd dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    .a_rx_data(vif.a_rx_data), .a_rx_valid(vif.a_rx_valid),
    .a_tx_data(vif.a_tx_data), .a_tx_data_valid(vif.a_tx_data_valid),
    .a_block_locked(vif.a_block_locked), .a_sync_error(vif.a_sync_error),
    .b_rx_data(vif.b_rx_data), .b_rx_valid(vif.b_rx_valid),
    .b_tx_data(vif.b_tx_data), .b_tx_data_valid(vif.b_tx_data_valid),
    .b_block_locked(vif.b_block_locked), .b_sync_error(vif.b_sync_error)
  );

  initial begin
    uvm_config_db#(virtual b2b_pcie_fd_if)::set(null, "*", "vif", vif);
    run_test("b2b_pcie_fd_test");
  end
endmodule : tb_b2b_pcie_fd
