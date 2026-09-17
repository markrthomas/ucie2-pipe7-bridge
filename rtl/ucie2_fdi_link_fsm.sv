// -----------------------------------------------------------------------------
// ucie2_fdi_link_fsm — UCIe 2.0 FDI link state machine (PLAN Item 3, Phase I I1).
//
// Tracks pl_state_sts over the full FDI/LPIF-aligned state set, coordinates every
// host-requested transition with the LPIF stall handshake (pl_stallreq /
// lp_stallack), forces LINKERROR on lp_linkerror, runs a real multi-cycle RETRAIN
// training sequence, and mirrors the rx-active / clock / wake handshakes. Exposes
// link_active (data flows only in FDI_ACTIVE) to gate the FDI ingress/egress.
//
// State set (fdi_state_e, encoding pinned in ucie2_pipe7_pkg.sv — implementation-
// defined per LPIF, which leaves the wire encoding to the implementation):
//   RESET      power-on / uninitialized; host requests ACTIVE to bring the link up
//   ACTIVE     operational; link_active=1, data flows
//   L1 / L2    low-power request states; link_active=0
//   LINKRESET  host-requested link reset; link_active=0
//   LINKERROR  sticky on lp_linkerror; cleared by requesting another state
//   RETRAIN    training; runs RETRAIN_CYCLES then auto-returns to ACTIVE
//   DISABLED   link disabled by request; link_active=0
//
// Transition model: on a host request (lp_state_req != committed state) the FSM
// asserts pl_stallreq, waits for lp_stallack, then commits state <= lp_state_req
// (LPIF stall protocol). RESET->ACTIVE is a fast bring-up (direct, one handshake)
// — the PHY is assumed already trained; a cold multi-phase training bring-up is a
// documented future increment. Entering RETRAIN (by request) trains for
// RETRAIN_CYCLES lclk cycles, then returns to ACTIVE automatically; holding the
// RETRAIN request = continuous retrain, pulsing it = one retrain pass.
//
// NOTE (byte-identical trace): the round-trip TB only ever requests ACTIVE, so the
// committed state never becomes RETRAIN and the RETRAIN branch below is never taken
// — the RESET->stall->ACTIVE path and every observable output are identical to the
// prior minimal FSM. The new behaviour is reachable only via the other requests,
// exercised by dv/pyuvm/test_link_fsm.py (control plane, no data, no trace).
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_fdi_link_fsm
  import ucie2_pipe7_pkg::*;
#(
  // RETRAIN training duration in lclk cycles (implementation choice).
  parameter int unsigned RETRAIN_CYCLES = 4
) (
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
  // lp_clk_ack is accepted but does not gate this FSM (a full clock handshake
  // would sequence on it). Observed only.
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_clk_ack = lp_clk_ack;
  /* verilator lint_on UNUSEDSIGNAL */

  localparam int unsigned TRAIN_W = (RETRAIN_CYCLES <= 1) ? 1 : $clog2(RETRAIN_CYCLES);

  typedef enum logic {L_STEADY, L_STALL} hs_e;
  hs_e               hs;
  logic [3:0]        state_q;
  logic [TRAIN_W-1:0] train_cnt;   // RETRAIN training counter

  assign pl_state_sts = state_q;
  assign link_active  = (state_q == FDI_ACTIVE);
  assign pl_stallreq  = (hs == L_STALL);

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q          <= FDI_RESET;
      hs               <= L_STEADY;
      train_cnt        <= '0;
      pl_rx_active_sts <= 1'b0;
      pl_clk_req       <= 1'b0;
      pl_wake_ack      <= 1'b0;
    end else begin
      // Simple mirrored handshakes (registered one cycle). Clock stays requested
      // while operational (ACTIVE), while training (RETRAIN), or mid-transition.
      pl_rx_active_sts <= lp_rx_active_req;
      pl_wake_ack      <= lp_wake_req;
      pl_clk_req       <= (state_q == FDI_ACTIVE) || (state_q == FDI_RETRAIN)
                          || (hs == L_STALL);

      if (lp_linkerror) begin
        // A protocol-flagged link error forces LINKERROR (sticky until a new
        // request drives the state elsewhere, e.g. FDI_RESET / FDI_ACTIVE).
        state_q   <= FDI_LINKERROR;
        hs        <= L_STEADY;
        train_cnt <= '0;
      end else begin
        unique case (hs)
          L_STEADY: begin
            if (state_q == FDI_RETRAIN) begin
              // Real retrain sequencing: train RETRAIN_CYCLES, then back to ACTIVE.
              if (train_cnt == TRAIN_W'(RETRAIN_CYCLES - 1)) begin
                state_q   <= FDI_ACTIVE;
                train_cnt <= '0;
              end else begin
                train_cnt <= train_cnt + 1'b1;
              end
            end else if (lp_state_req != state_q) begin
              // Host requests a new state -> begin the LPIF stall handshake.
              hs <= L_STALL;
            end
          end
          L_STALL: if (lp_stallack) begin
            state_q   <= lp_state_req;   // commit the requested state
            hs        <= L_STEADY;
            train_cnt <= '0;             // fresh training window if we land in RETRAIN
          end
        endcase
      end
    end
  end

endmodule : ucie2_fdi_link_fsm

`default_nettype wire
