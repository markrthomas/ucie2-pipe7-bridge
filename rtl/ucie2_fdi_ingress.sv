// -----------------------------------------------------------------------------
// ucie2_fdi_ingress — UCIe 2.0 FDI transmit (Protocol Layer -> Adapter) to the
// internal 128-bit block contract consumed by the MAC datapath.
//
// PLAN Item 3. Because a frozen FDI transfer is FDI_DW = BLOCK_PAYLOAD = 128 bits
// (crosscheck B.1), one FDI transfer is exactly one block — no RDI-style
// multi-word reassembly. This is a combinational valid/ready adapter gated by the
// FDI link state (data flows only when the link is ACTIVE).
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_fdi_ingress
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FDI_W = FDI_DW,
  parameter int unsigned BLK   = BLOCK_PAYLOAD
) (
  // ---- FDI transmit (Protocol Layer -> bridge), lclk domain ----
  input  wire [FDI_W-1:0]  lp_data,
  input  wire              lp_valid,
  input  wire              lp_irdy,
  output wire              pl_trdy,
  input  wire              link_active,   // from ucie2_fdi_link_fsm

  // ---- Block payload output (to the TX CDC / datapath) ----
  output wire              blk_valid,
  output wire [BLK-1:0]    blk_data,
  output wire              blk_is_os,
  input  wire              blk_ready
);
  // Adapter accepts a transfer only when the downstream block sink is ready and
  // the link is ACTIVE. FDI handshake completes when lp_valid & lp_irdy & pl_trdy.
  assign pl_trdy   = blk_ready & link_active;
  assign blk_valid = lp_valid & lp_irdy & pl_trdy;
  assign blk_data  = lp_data[BLK-1:0];
  // FLAGGED (crosscheck B.1): is_os derivation from FDI flit type is deferred;
  // default every block to a data block until the flit-type hook is added.
  assign blk_is_os = 1'b0;

endmodule : ucie2_fdi_ingress

`default_nettype wire
