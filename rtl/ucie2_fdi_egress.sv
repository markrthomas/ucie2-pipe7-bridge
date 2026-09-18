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
  input  wire              blk_is_os,     // recovered flit-type (deframer sync header)
  input  wire              blk_err,       // recovered block came through an RX error
  output wire              blk_ready,
  input  wire              link_active,   // from ucie2_fdi_link_fsm

  // ---- FDI receive (bridge -> Protocol Layer) ----
  output wire [FDI_W-1:0]  pl_data,
  output wire              pl_valid,
  output wire              pl_is_os,      // recovered flit-type, valid with pl_valid
  output wire              pl_flit_cancel
);
  // No backpressure on FDI RX: always ready to drain a recovered block while the
  // link is ACTIVE.
  assign blk_ready = link_active;
  assign pl_valid  = blk_valid & link_active;
  // FDI_W == BLK (128); zero-extend defensively if a wider FDI is ever configured.
  assign pl_data   = FDI_W'(blk_data);
  // Forward the recovered flit-type to FDI RX (Phase I I2; crosscheck B resolved).
  assign pl_is_os  = blk_is_os;
  // pl_flit_cancel (adapter flit retraction), Phase I I3; crosscheck B resolved.
  // The adapter retracts a flit in flight when the recovered block is untrustworthy
  // -- it arrived through an RX datapath error (blk_err, carried per-block from the
  // RX FIFO/CDC error channel). Asserted coincident with pl_valid so the protocol
  // layer discards exactly that flit.
  assign pl_flit_cancel = pl_valid & blk_err;

endmodule : ucie2_fdi_egress

`default_nettype wire
