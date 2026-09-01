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
  parameter int unsigned MBW   = 8
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // FDI transmit (Protocol Layer -> bridge)
  logic [FDI_W-1:0] lp_data       = '0;
  logic             lp_valid       = 1'b0;
  logic             lp_irdy        = 1'b0;
  logic             pl_trdy;
  // FDI receive (bridge -> Protocol Layer)
  logic [FDI_W-1:0] pl_data;
  logic             pl_valid;
  logic             pl_flit_cancel;
  // FDI link state machine
  // lp_state_req MUST be initialised to FDI_RESET (0): if it is x at reset
  // deassert the link FSM sees a mismatch and immediately asserts pl_stallreq,
  // diverging from the PyUVM trace at cycle 0.
  logic [3:0]       lp_state_req   = 4'h0;   // FDI_RESET
  logic [3:0]       pl_state_sts;
  logic             lp_linkerror   = 1'b0;
  logic             pl_stallreq;
  logic             lp_stallack    = 1'b0;
  // FDI rx-active / clock / wake
  logic             lp_rx_active_req = 1'b0;
  logic             pl_rx_active_sts;
  logic             pl_clk_req;
  logic             lp_clk_ack     = 1'b0;
  logic             lp_wake_req    = 1'b0;
  logic             pl_wake_ack;

  // Management: PIPE control request
  logic             req_valid      = 1'b0;
  logic [1:0]       req_kind       = 2'b0;
  logic [3:0]       req_power_down = 4'h0;
  logic [3:0]       req_rate       = 4'h0;
  logic [2:0]       req_width      = 3'h0;
  logic [2:0]       req_rxwidth    = 3'h0;
  logic             busy;
  logic             done;
  logic             req_error;
  // Management: message-bus request
  logic             mb_req_valid   = 1'b0;
  logic             mb_req_write   = 1'b0;
  logic             mb_req_committed = 1'b0;
  logic [11:0]      mb_req_addr    = 12'h0;
  logic [7:0]       mb_req_wdata   = 8'h0;
  logic             mb_req_ready;
  logic             mb_busy;
  logic             mb_rsp_valid;
  logic             mb_rsp_is_read;
  logic [7:0]       mb_rsp_rdata;
  logic             mb_rsp_error;

  // PIPE PHY -> MAC stimulus inputs (loopback / PHY model driven by TB)
  logic [PW-1:0]    rx_data        = '0;
  logic             rx_valid       = 1'b0;
  logic             phy_status     = 1'b0;
  logic [2:0]       rx_status      = 3'h0;
  logic             rx_elec_idle   = 1'b0;
  logic [MBW-1:0]   p2m_message_bus = '0;
  // PIPE MAC -> PHY (DUT outputs)
  logic [PW-1:0]    tx_data;
  logic             tx_data_valid;
  logic [3:0]       rate;
  logic [3:0]       power_down;
  logic [2:0]       width;
  logic [2:0]       rx_width;
  logic             tx_detect_rx;
  logic [3:0]       tx_elec_idle;
  // PIPE message bus (DUT output)
  logic [MBW-1:0]   m2p_message_bus;
  // Bridge status (DUT outputs)
  logic             block_locked;
  logic             sync_error;
  logic             in_data_phase;
  logic             rx_overflow;
endinterface : ucie2_pipe7_if
