// -----------------------------------------------------------------------------
// ucie2_fdi_link_fsm — minimal-functional UCIe 2.0 FDI link state machine.
//
// PLAN Item 3 (FDI state-machine handshake). Tracks pl_state_sts, transitions on
// lp_state_req via a stall handshake (pl_stallreq/lp_stallack), forces LINKERROR
// on lp_linkerror, and mirrors the rx-active / clock / wake handshakes. Exposes
// link_active to gate the FDI ingress/egress so data flows only in FDI_ACTIVE.
//
// Scope: minimal-functional (the "most logical path"). fdi_state_e encodings are
// FLAGGED (crosscheck C); full LPIF bring-up/retrain sequencing is future work.
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_fdi_link_fsm
  import ucie2_pipe7_pkg::*;
(
  input  wire        clk,          // lclk (FDI domain)
  input  wire        reset_n,

  // ---- FDI link-state request / status ----
  input  wire [3:0]  lp_state_req, // requested state (fdi_state_e)
  output wire [3:0]  pl_state_sts, // current state  (fdi_state_e)
  input  wire        lp_linkerror,
  output wire        pl_stallreq,
  input  wire        lp_stallack,

  // ---- FDI rx-active / clock / wake handshakes ----
  input  wire        lp_rx_active_req,
  output logic       pl_rx_active_sts,
  output logic       pl_clk_req,
  input  wire        lp_clk_ack,
  input  wire        lp_wake_req,
  output logic       pl_wake_ack,

  // ---- Gate for the FDI datapath adapters ----
  output wire        link_active
);
  // lp_clk_ack is accepted but does not gate this minimal FSM (a real clock
  // handshake would sequence on it). Observed only.
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_clk_ack = lp_clk_ack;
  /* verilator lint_on UNUSEDSIGNAL */

  typedef enum logic {L_STEADY, L_STALL} hs_e;
  hs_e         hs;
  logic [3:0]  state_q;

  assign pl_state_sts = state_q;
  assign link_active  = (state_q == FDI_ACTIVE);
  assign pl_stallreq  = (hs == L_STALL);

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q          <= FDI_RESET;
      hs               <= L_STEADY;
      pl_rx_active_sts <= 1'b0;
      pl_clk_req       <= 1'b0;
      pl_wake_ack      <= 1'b0;
    end else begin
      // Simple mirrored handshakes (registered one cycle).
      pl_rx_active_sts <= lp_rx_active_req;
      pl_wake_ack      <= lp_wake_req;
      pl_clk_req       <= (state_q == FDI_ACTIVE) || (hs == L_STALL);

      if (lp_linkerror) begin
        // A protocol-flagged link error forces LINKERROR (sticky until a new
        // request drives the state elsewhere, e.g. FDI_RESET).
        state_q <= FDI_LINKERROR;
        hs      <= L_STEADY;
      end else begin
        unique case (hs)
          L_STEADY: if (lp_state_req != state_q) hs <= L_STALL;
          L_STALL:  if (lp_stallack) begin
                      state_q <= lp_state_req;
                      hs      <= L_STEADY;
                    end
        endcase
      end
    end
  end

endmodule : ucie2_fdi_link_fsm

`default_nettype wire
