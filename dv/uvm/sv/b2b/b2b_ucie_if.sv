// -----------------------------------------------------------------------------
// b2b_ucie_if — boundary bundle for the B2B "external UCIe" config (PLAN H1).
//
// Ports of dv/harness/b2b_ucie_pcie_ucie.sv: two ucie2_pipe7_bridge joined at
// their PIPE ports (UCIe -> [A] -> PCIe == PCIe -> [B] -> UCIe). The TB drives
// bridge A's FDI TX + link bring-up, observes the middle PIPE word stream, and
// recovers FDI flits out of bridge B. Unidirectional (A->B). Mirrors the PyUVM
// test dv/pyuvm/test_b2b_ucie.py.
// -----------------------------------------------------------------------------
interface b2b_ucie_if #(
  parameter int unsigned FDI_W = 128,
  parameter int unsigned PW    = 80
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // Left external: UCIe/FDI TX into bridge A + A's link bring-up (TB-driven).
  logic [FDI_W-1:0] a_lp_data       = '0;
  logic             a_lp_valid      = 1'b0;
  logic             a_lp_irdy       = 1'b0;
  logic             a_pl_trdy;
  logic [3:0]       a_lp_state_req  = 4'h0;   // FDI_RESET (must not be x at reset)
  logic [3:0]       a_pl_state_sts;
  logic             a_lp_stallack   = 1'b0;
  logic             a_pl_stallreq;
  // Middle observation: PIPE word stream on the A->B link.
  logic [PW-1:0]    mid_tx_data;
  logic             mid_tx_data_valid;
  // Right external: UCIe/FDI RX recovered out of bridge B.
  logic [FDI_W-1:0] b_pl_data;
  logic             b_pl_valid;
  logic             b_pl_flit_cancel;
  logic             b_block_locked;
  logic             b_sync_error;
endinterface : b2b_ucie_if
