// -----------------------------------------------------------------------------
// b2b_ucie_fd_uvm_pkg — SV UVM package for the FULL-DUPLEX B2B "external UCIe"
// config (PLAN H3b / Phase I I8).
//
// Cookbook-style one-class-per-file, pulled in via ordered `include. Reuses the
// generic FDI stimulus classes (fdi_flit_item / fdi_sequencer / fdi_seq_lib) from
// the single-bridge env -- same tokens, driven by +VEC/+N_FLITS -- then the
// full-duplex B2B UCIe sided driver/monitor + dual-direction scoreboard/test.
// `include search path is +incdir+$(SV) (see dv/uvm/vlt/Makefile).
// -----------------------------------------------------------------------------
package b2b_ucie_fd_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;

  localparam int unsigned N_FLITS      = 8;
  localparam int unsigned BRINGUP_LCLK = 8;
  localparam int unsigned RUN_PCLK     = 200;
  localparam int unsigned PW           = PIPE_WIDTH_DEFAULT;
  localparam int unsigned FDIW         = FDI_DW;

  // Reused generic FDI stimulus (shared with the single-bridge env).
  `include "fdi_agent/fdi_flit_item.sv"
  `include "fdi_agent/fdi_sequencer.sv"
  `include "fdi_agent/fdi_seq_lib.sv"
  // Full-duplex B2B UCIe components.
  `include "b2b/b2b_ucie_fd_driver.sv"
  `include "b2b/b2b_ucie_fd_monitor.sv"
  `include "b2b/b2b_ucie_fd_scoreboard.sv"
  `include "b2b/b2b_ucie_fd_test.sv"

endpackage : b2b_ucie_fd_uvm_pkg
