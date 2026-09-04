// -----------------------------------------------------------------------------
// tb_b2b_pcie — SV UVM top for the B2B "external PCIe" config (PLAN H2).
//
// Instantiates the dv/harness B2B wrapper (two ucie2_pipe7_bridge joined at FDI)
// + the b2b_pcie_if bundle, hands the vif to UVM, and runs b2b_pcie_test. Clock/
// reset identical to tb_ucie2_pipe7 (2 ns both domains, reset deassert at 11 ns).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_b2b_pcie;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import b2b_pcie_uvm_pkg::*;

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

  b2b_pcie_if #(.FDI_W(FDI_W), .PW(PW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  b2b_pcie_ucie_pcie dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    .a_rx_data(vif.a_rx_data), .a_rx_valid(vif.a_rx_valid),
    .a_block_locked(vif.a_block_locked), .a_sync_error(vif.a_sync_error),
    .mid_pl_data(vif.mid_pl_data), .mid_pl_valid(vif.mid_pl_valid),
    .b_tx_data(vif.b_tx_data), .b_tx_data_valid(vif.b_tx_data_valid)
  );

  initial begin
    uvm_config_db#(virtual b2b_pcie_if)::set(null, "*", "vif", vif);
    run_test("b2b_pcie_test");
  end
endmodule : tb_b2b_pcie
