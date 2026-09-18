// -----------------------------------------------------------------------------
// b2b_ucie_fd_if — boundary bundle for the FULL-DUPLEX B2B "external UCIe" config
// (PLAN H3b / Phase I I8).
//
// Ports of dv/harness/b2b_ucie_pcie_ucie_fd.sv: two ucie2_pipe7_bridge joined at
// PIPE with BOTH directions live. Each end (A, B) drives its own FDI TX + link
// bring-up and recovers the far end's flits out of its own FDI RX:
//   forward : a_lp -> A.tx -> B.rx -> b_pl
//   reverse : b_lp -> B.tx -> A.rx -> a_pl
// Mirrors the PyUVM test dv/pyuvm/test_b2b_ucie_fd.py.
// -----------------------------------------------------------------------------
interface b2b_ucie_fd_if #(
  parameter int unsigned FDI_W = 128,
  parameter int unsigned PW    = 80
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // ---- Left (bridge A): FDI TX in + link + reverse FDI RX out ----
  logic [FDI_W-1:0] a_lp_data       = '0;
  logic             a_lp_valid      = 1'b0;
  logic             a_lp_irdy       = 1'b0;
  logic             a_pl_trdy;
  logic [3:0]       a_lp_state_req  = 4'h0;    // FDI_RESET (must not be x at reset)
  logic [3:0]       a_pl_state_sts;
  logic             a_lp_stallack   = 1'b0;
  logic             a_pl_stallreq;
  logic [FDI_W-1:0] a_pl_data;                 // reverse (B->A) recovered here
  logic             a_pl_valid;
  logic             a_block_locked;
  logic             a_sync_error;
  // ---- Right (bridge B): FDI TX in + link + forward FDI RX out ----
  logic [FDI_W-1:0] b_lp_data       = '0;
  logic             b_lp_valid      = 1'b0;
  logic             b_lp_irdy       = 1'b0;
  logic             b_pl_trdy;
  logic [3:0]       b_lp_state_req  = 4'h0;
  logic [3:0]       b_pl_state_sts;
  logic             b_lp_stallack   = 1'b0;
  logic             b_pl_stallreq;
  logic [FDI_W-1:0] b_pl_data;                 // forward (A->B) recovered here
  logic             b_pl_valid;
  logic             b_block_locked;
  logic             b_sync_error;
endinterface : b2b_ucie_fd_if
