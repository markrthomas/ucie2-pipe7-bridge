// -----------------------------------------------------------------------------
// ucie2_pipe7_if — DUT boundary bundle for the SV UVM environment.
//
// SCAFFOLD (PLAN Item 13 seed). Carries the full FDI (controller-facing) and
// PIPE 7.1 (MAC-facing) signal set so agents can drive/monitor it. The agents,
// drivers, and scoreboard are added in Phase D; today only the smoke test uses it
// to sample the DUT boundary for the per-cycle trace.
// -----------------------------------------------------------------------------
interface ucie2_pipe7_if #(
  parameter int unsigned FLIT_W = 256,
  parameter int unsigned PW     = 64,
  parameter int unsigned PK     = PW/8
) (
  input logic lclk,
  input logic lclk_rst_n,
  input logic pclk,
  input logic pclk_rst_n
);
  // FDI transmit (Protocol Layer -> Adapter)
  logic [FLIT_W-1:0] lp_flit;
  logic              lp_flit_valid;
  logic              lp_valid;
  logic              pl_trdy;
  logic [2:0]        lp_state_req;
  logic              lp_linkerror;
  logic              pl_stallreq;
  logic              lp_stallack;

  // FDI receive (Adapter -> Protocol Layer)
  logic [FLIT_W-1:0] pl_flit;
  logic              pl_flit_valid;
  logic              pl_valid;
  logic [2:0]        pl_state_sts;

  // PIPE MAC -> PHY
  logic [PW-1:0]     tx_data;
  logic [PK-1:0]     tx_data_k;
  logic              tx_data_valid;
  logic [2:0]        rate;
  logic [1:0]        power_down;
  logic              tx_detect_rx;
  logic              tx_elec_idle;

  // PIPE PHY -> MAC
  logic [PW-1:0]     rx_data;
  logic [PK-1:0]     rx_data_k;
  logic              rx_data_valid;
  logic              rx_valid;
  logic              phy_status;
  logic [2:0]        rx_status;
  logic              rx_elec_idle;
endinterface : ucie2_pipe7_if
