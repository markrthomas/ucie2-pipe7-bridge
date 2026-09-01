// -----------------------------------------------------------------------------
// ucie2_fdi_egress — recovered internal 128-bit block -> UCIe 2.0 FDI receive
// (Adapter -> Protocol Layer).
//
// PLAN Item 3. Inverse of ucie2_fdi_ingress: one block == one FDI transfer. FDI
// RX has NO backpressure (crosscheck B), so the adapter always consumes the
// recovered block when the link is ACTIVE and presents it on pl_data/pl_valid.
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_fdi_egress
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FDI_W = FDI_DW,
  parameter int unsigned BLK   = BLOCK_PAYLOAD
) (
  // ---- Block payload input (from the RX CDC), lclk domain ----
  input  wire              blk_valid,
  input  wire [BLK-1:0]    blk_data,
  output wire              blk_ready,
  input  wire              link_active,   // from ucie2_fdi_link_fsm

  // ---- FDI receive (bridge -> Protocol Layer) ----
  output wire [FDI_W-1:0]  pl_data,
  output wire              pl_valid,
  output wire              pl_flit_cancel
);
  // No backpressure on FDI RX: always ready to drain a recovered block while the
  // link is ACTIVE.
  assign blk_ready = link_active;
  assign pl_valid  = blk_valid & link_active;
  // FDI_W == BLK (128); zero-extend defensively if a wider FDI is ever configured.
  assign pl_data   = FDI_W'(blk_data);
  // FLAGGED (crosscheck B): pl_flit_cancel (adapter flit retraction) not modeled.
  assign pl_flit_cancel = 1'b0;

endmodule : ucie2_fdi_egress

`default_nettype wire
