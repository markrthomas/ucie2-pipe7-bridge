// -----------------------------------------------------------------------------
// ucie2_pipe7_bridge — top-level shell for the UCIe 2.0 (FDI) <-> PCIe PIPE 7.1
// MAC bridge.
//
// SCAFFOLD (PLAN Item 2). Ports declare the FROZEN (Item 0) FDI controller-facing
// and PIPE 7.1 MAC-facing boundary so the environment (lint, TB elaboration, CI)
// has a real DUT. The datapath is empty — built in Phase B (Items 3-9), at which
// point the shell-only lint waivers below are removed as signals become driven/
// consumed. FDI signal set: docs/ucie2_pipe71_spec_crosscheck.md section B.
// -----------------------------------------------------------------------------
`default_nettype none

// Shell-only lint waivers spanning the whole module (ports included): the shell
// declares the full boundary but drives no datapath yet, so inputs read as
// UNUSEDSIGNAL and some outputs as UNDRIVEN. MUST be removed as Phase B wires
// each block; a reviewer should reject these surviving a non-empty datapath.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */

module ucie2_pipe7_bridge
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FDI_W = FDI_DW,      // FDI transfer width (128)
  parameter int unsigned PW    = PIPE_WIDTH   // active PIPE parallel width
) (
  // ---- Clocks / reset -------------------------------------------------------
  input  wire                 lclk,       // FDI-side clock (UCIe local clock)
  input  wire                 lclk_rst_n, // FDI-side async reset, active-low
  input  wire                 pclk,       // PIPE PCLK (PHY-owned, MAC-facing)
  input  wire                 pclk_rst_n, // PIPE-side async reset, active-low

  // ---- FDI: transmit (Protocol Layer -> Adapter/bridge) ---------------------
  input  wire [FDI_W-1:0]     lp_data,        // flit/stream payload word
  input  wire                 lp_valid,       // lp_data valid
  input  wire                 lp_irdy,        // protocol layer ready to transfer
  output wire                 pl_trdy,        // adapter ready to accept a transfer

  // ---- FDI: receive (Adapter/bridge -> Protocol Layer) ----------------------
  output wire [FDI_W-1:0]     pl_data,        // received flit/stream payload
  output wire                 pl_valid,       // pl_data valid (RX has no backpressure)
  output wire                 pl_flit_cancel, // adapter retracts a flit (FLAGGED)

  // ---- FDI: link state machine ----------------------------------------------
  input  wire [3:0]           lp_state_req,   // requested link state (fdi_state_e)
  output wire [3:0]           pl_state_sts,   // current link state (fdi_state_e)
  input  wire                 lp_linkerror,   // protocol layer flags link error
  output wire                 pl_stallreq,    // adapter requests protocol stall
  input  wire                 lp_stallack,    // protocol layer acks stall

  // ---- FDI: rx-active / clock / wake handshakes -----------------------------
  input  wire                 lp_rx_active_req, // request Rx active
  output wire                 pl_rx_active_sts, // Rx active status
  output wire                 pl_clk_req,       // adapter clock request
  input  wire                 lp_clk_ack,       // protocol layer clock ack
  input  wire                 lp_wake_req,      // wake request
  output wire                 pl_wake_ack,      // wake ack

  // ---- PIPE 7.1: MAC -> PHY (command; MAC-owned) -----------------------------
  output wire [PW-1:0]        tx_data,
  output wire [PW/8-1:0]      tx_data_k,      // control/K per byte (Gen5 128b/130b)
  output wire                 tx_data_valid,
  output wire [3:0]           rate,           // rate_e
  output wire [3:0]           power_down,     // powerdown_e
  output wire [2:0]           width,          // width_e (Tx)
  output wire [2:0]           rx_width,       // width_e (Rx)
  output wire                 tx_detect_rx,
  output wire [3:0]           tx_elec_idle,

  // ---- PIPE 7.1: PHY -> MAC (status; PHY-owned) ------------------------------
  input  wire [PW-1:0]        rx_data,
  input  wire                 rx_valid,
  input  wire                 phy_status,
  input  wire [2:0]           rx_status,
  input  wire                 rx_elec_idle,

  // ---- PIPE 7.1: message bus (config plane) ---------------------------------
  output wire [MB_BUS_WIDTH-1:0] m2p_message_bus,
  input  wire [MB_BUS_WIDTH-1:0] p2m_message_bus
);

  // TODO(Phase B, Items 3-9): FDI flit TX/RX + FC + state FSM, FDI<->PCLK CDC,
  // Gen5 gearbox framer/deframer, Gen6 PAM4 datapath, rate-aware mux + PIPE MAC
  // control FSM, management/sideband regfile.

  // Defined idle defaults so the shell elaborates and simulates deterministically.
  assign pl_trdy          = 1'b0;
  assign pl_data          = '0;
  assign pl_valid         = 1'b0;
  assign pl_flit_cancel   = 1'b0;
  assign pl_state_sts     = FDI_RESET;
  assign pl_stallreq      = 1'b0;
  assign pl_rx_active_sts = 1'b0;
  assign pl_clk_req       = 1'b0;
  assign pl_wake_ack      = 1'b0;

  assign tx_data          = '0;
  assign tx_data_k        = '0;
  assign tx_data_valid    = 1'b0;
  assign rate             = RATE_GEN6;
  assign power_down       = PD_P1;
  assign width            = W_80;
  assign rx_width         = W_80;
  assign tx_detect_rx     = 1'b0;
  assign tx_elec_idle     = 4'hF;
  assign m2p_message_bus  = '0;

endmodule : ucie2_pipe7_bridge

/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */

`default_nettype wire
