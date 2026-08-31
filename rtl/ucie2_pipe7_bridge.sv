// -----------------------------------------------------------------------------
// ucie2_pipe7_bridge — top-level shell for the UCIe 2.0 (FDI) <-> PCIe PIPE 7.1
// MAC bridge.
//
// SCAFFOLD (PLAN Item 2). Ports declare the FDI (controller-facing) and PIPE 7.1
// (MAC-facing) boundary contract so the environment (lint, TB elaboration, CI)
// has a real DUT to compile against. The datapath is intentionally empty — it is
// built out in Phase B (Items 3-9), at which point the lint waivers below are
// removed as signals become driven/consumed.
//
// The module-scope lint waivers are legitimate ONLY while this is a shell; a
// reviewer should reject their reappearance once the datapath exists.
// -----------------------------------------------------------------------------
`default_nettype none

// Shell-only lint waivers: this module declares the full boundary but drives no
// datapath yet, so every input reads as UNUSEDSIGNAL and some outputs would read
// as UNDRIVEN. The waiver spans the whole module (ports included) and MUST be
// removed as Phase B wires each block. A reviewer should reject these surviving
// past a non-empty datapath.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */

module ucie2_pipe7_bridge
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FLIT_W = FDI_FLIT_W,
  parameter int unsigned PW     = PIPE_WIDTH
) (
  // ---- Clocks / reset -------------------------------------------------------
  input  wire                 lclk,       // FDI-side clock (UCIe local clock)
  input  wire                 lclk_rst_n, // FDI-side async reset, active-low
  input  wire                 pclk,       // PIPE PCLK (PHY-owned, MAC-facing)
  input  wire                 pclk_rst_n, // PIPE-side async reset, active-low

  // ---- FDI: transmit (Protocol Layer -> Adapter) ----------------------------
  input  wire [FLIT_W-1:0]    lp_flit,        // flit data from protocol layer
  input  wire                 lp_flit_valid,  // flit data valid
  input  wire                 lp_valid,       // protocol layer has valid data
  output wire                 pl_trdy,        // adapter ready to accept a flit
  input  wire [2:0]           lp_state_req,   // requested link state (fdi_state_e)
  input  wire                 lp_linkerror,   // protocol layer flags link error
  output wire                 pl_stallreq,    // adapter requests protocol stall
  input  wire                 lp_stallack,    // protocol layer acks stall

  // ---- FDI: receive (Adapter -> Protocol Layer) -----------------------------
  output wire [FLIT_W-1:0]    pl_flit,        // flit data to protocol layer
  output wire                 pl_flit_valid,  // flit data valid
  output wire                 pl_valid,       // adapter has valid data
  output wire [2:0]           pl_state_sts,   // current link state (fdi_state_e)

  // ---- PIPE 7.1: MAC -> PHY (command; MAC-owned) -----------------------------
  output wire [PW-1:0]        tx_data,
  output wire [PIPE_K-1:0]    tx_data_k,      // control/K per byte (Gen5 128b/130b)
  output wire                 tx_data_valid,
  output wire [2:0]           rate,           // pcie_rate_e
  output wire [1:0]           power_down,     // pipe_pwrdn_e
  output wire                 tx_detect_rx,
  output wire                 tx_elec_idle,

  // ---- PIPE 7.1: PHY -> MAC (status; PHY-owned) ------------------------------
  input  wire [PW-1:0]        rx_data,
  input  wire [PIPE_K-1:0]    rx_data_k,
  input  wire                 rx_data_valid,
  input  wire                 rx_valid,
  input  wire                 phy_status,
  input  wire [2:0]           rx_status,
  input  wire                 rx_elec_idle
);

  // TODO(Phase B, Items 3-9): FDI flit TX/RX + FC + state FSM, FDI<->PCLK CDC,
  // Gen5 gearbox framer/deframer, Gen6 PAM4 datapath, rate-aware mux + PIPE MAC
  // control FSM, management/sideband regfile.

  // Defined idle defaults so the shell elaborates and simulates deterministically.
  assign pl_trdy       = 1'b0;
  assign pl_stallreq   = 1'b0;
  assign pl_flit       = '0;
  assign pl_flit_valid = 1'b0;
  assign pl_valid      = 1'b0;
  assign pl_state_sts  = FDI_ST_RESET;

  assign tx_data       = '0;
  assign tx_data_k     = '0;
  assign tx_data_valid = 1'b0;
  assign rate          = RATE_GEN6;
  assign power_down    = PD_P1;
  assign tx_detect_rx  = 1'b0;
  assign tx_elec_idle  = 1'b1;

endmodule : ucie2_pipe7_bridge

/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */

`default_nettype wire
