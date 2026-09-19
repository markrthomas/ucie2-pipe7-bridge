// -----------------------------------------------------------------------------
// b2b_pcie_fd_uvm_pkg — SV UVM package for the FULL-DUPLEX B2B "external PCIe"
// config (PLAN H3b / Phase I I8b).
//
// Cookbook-style one-class-per-file, pulled in via ordered `include. No shared FDI
// stimulus classes here: like the half-duplex PCIe env, the stimulus is a
// pre-framed PIPE word stream the sided driver replays from +VEC_WORDS. Include
// order respects dependencies (driver/monitor before scoreboard before test).
// `include search path is +incdir+$(SV) (see dv/uvm/vlt/Makefile).
// -----------------------------------------------------------------------------
package b2b_pcie_fd_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;

  localparam int unsigned N_FLITS  = 8;
  localparam int unsigned RUN_PCLK = 200;
  localparam int unsigned PW       = PIPE_WIDTH_DEFAULT;
  localparam int unsigned FDIW     = FDI_DW;

  `include "b2b/b2b_pcie_fd_driver.sv"
  `include "b2b/b2b_pcie_fd_monitor.sv"
  `include "b2b/b2b_pcie_fd_scoreboard.sv"
  `include "b2b/b2b_pcie_fd_test.sv"

endpackage : b2b_pcie_fd_uvm_pkg
