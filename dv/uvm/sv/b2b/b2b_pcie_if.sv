// -----------------------------------------------------------------------------
// b2b_pcie_if — boundary bundle for the B2B "external PCIe" config (PLAN H2).
//
// Ports of dv/harness/b2b_pcie_ucie_pcie.sv: two ucie2_pipe7_bridge joined at
// their FDI ports (PCIe -> [A] -> UCIe == UCIe -> [B] -> PCIe). The TB injects a
// block-aligned PIPE word stream into bridge A's PIPE RX, observes the flits
// recovered at the UCIe seam, and captures bridge B's re-framed PIPE output.
// Unidirectional (A->B). Mirrors dv/pyuvm/test_b2b_pcie.py.
// -----------------------------------------------------------------------------
interface b2b_pcie_if #(
  parameter int unsigned FDI_W = 128,
  parameter int unsigned PW    = 80
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // Left external: PCIe/PIPE RX word stream into bridge A (TB-driven).
  logic [PW-1:0]    a_rx_data  = '0;
  logic             a_rx_valid = 1'b0;
  logic             a_block_locked;
  logic             a_sync_error;
  // Middle observation: UCIe flits recovered at the A->B FDI seam.
  logic [FDI_W-1:0] mid_pl_data;
  logic             mid_pl_valid;
  // Right external: PCIe/PIPE TX word stream out of bridge B.
  logic [PW-1:0]    b_tx_data;
  logic             b_tx_data_valid;
endinterface : b2b_pcie_if
