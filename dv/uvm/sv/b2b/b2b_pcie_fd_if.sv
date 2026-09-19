// -----------------------------------------------------------------------------
// b2b_pcie_fd_if — boundary bundle for the FULL-DUPLEX B2B "external PCIe" config
// (PLAN H3b / Phase I I8b).
//
// Ports of dv/harness/b2b_pcie_ucie_pcie_fd.sv: two ucie2_pipe7_bridge joined at
// their FDI seam with BOTH directions live. Each end injects a block-aligned PIPE
// word stream into its own PIPE RX and recovers the far end's re-framed words out
// of its own PIPE TX:
//   forward : a_rx (PIPE into A) -> A.pl -> B.lp -> b_tx (PIPE out of B)
//   reverse : b_rx (PIPE into B) -> B.pl -> A.lp -> a_tx (PIPE out of A)
// Both FDI links self-bring-up to ACTIVE (neither FDI port is external). Mirrors
// the PyUVM test dv/pyuvm/test_b2b_pcie_fd.py.
// -----------------------------------------------------------------------------
interface b2b_pcie_fd_if #(
  parameter int unsigned FDI_W = 128,
  parameter int unsigned PW    = 80
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // ---- Left (bridge A) PCIe: PIPE RX in (forward) + PIPE TX out (reverse) ----
  logic [PW-1:0] a_rx_data       = '0;
  logic          a_rx_valid      = 1'b0;
  logic [PW-1:0] a_tx_data;                 // reverse (B->A) re-framed here
  logic          a_tx_data_valid;
  logic          a_block_locked;            // bridge A deframer (forward path)
  logic          a_sync_error;
  // ---- Right (bridge B) PCIe: PIPE RX in (reverse) + PIPE TX out (forward) ----
  logic [PW-1:0] b_rx_data       = '0;
  logic          b_rx_valid      = 1'b0;
  logic [PW-1:0] b_tx_data;                 // forward (A->B) re-framed here
  logic          b_tx_data_valid;
  logic          b_block_locked;            // bridge B deframer (reverse path)
  logic          b_sync_error;
endinterface : b2b_pcie_fd_if
