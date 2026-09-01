// -----------------------------------------------------------------------------
// ucie2_pipe7_if — DUT boundary bundle for the SV UVM environment.
//
// SCAFFOLD (PLAN Item 13 seed). Carries the FROZEN (Item 0) FDI controller-facing
// and PIPE 7.1 MAC-facing signal set. Agents/drivers/scoreboard are added in
// Phase D; today only the smoke test samples this for the per-cycle trace.
// Signal set: docs/ucie2_pipe71_spec_crosscheck.md section B.
// -----------------------------------------------------------------------------
interface ucie2_pipe7_if #(
  parameter int unsigned FDI_W = 128,
  parameter int unsigned PW    = 80,
  parameter int unsigned PK    = PW/8,
  parameter int unsigned MBW   = 8
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // FDI transmit (Protocol Layer -> bridge)
  logic [FDI_W-1:0] lp_data;
  logic             lp_valid;
  logic             lp_irdy;
  logic             pl_trdy;
  // FDI receive (bridge -> Protocol Layer)
  logic [FDI_W-1:0] pl_data;
  logic             pl_valid;
  logic             pl_flit_cancel;
  // FDI link state machine
  logic [3:0]       lp_state_req;
  logic [3:0]       pl_state_sts;
  logic             lp_linkerror;
  logic             pl_stallreq;
  logic             lp_stallack;
  // FDI rx-active / clock / wake
  logic             lp_rx_active_req;
  logic             pl_rx_active_sts;
  logic             pl_clk_req;
  logic             lp_clk_ack;
  logic             lp_wake_req;
  logic             pl_wake_ack;

  // PIPE MAC -> PHY
  logic [PW-1:0]    tx_data;
  logic [PK-1:0]    tx_data_k;
  logic             tx_data_valid;
  logic [3:0]       rate;
  logic [3:0]       power_down;
  logic [2:0]       width;
  logic [2:0]       rx_width;
  logic             tx_detect_rx;
  logic [3:0]       tx_elec_idle;
  // PIPE PHY -> MAC
  logic [PW-1:0]    rx_data;
  logic             rx_valid;
  logic             phy_status;
  logic [2:0]       rx_status;
  logic             rx_elec_idle;
  // PIPE message bus
  logic [MBW-1:0]   m2p_message_bus;
  logic [MBW-1:0]   p2m_message_bus;
endinterface : ucie2_pipe7_if
