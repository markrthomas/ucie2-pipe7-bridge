// -----------------------------------------------------------------------------
// ucie2_pipe7_bridge — UCIe 2.0 (FDI) <-> PCIe PIPE 7.1 MAC-facing bridge
// (integrated top, PLAN Item 9).
//
//   FDI TX flit --> ucie2_fdi_ingress --> tx CDC (lclk->pclk) --> TX adapter
//               --> pipe7_mac_datapath_ra (Gen5 128b/130b gearbox / Gen6 raw,
//                   TxElecIdle-gated) --> TxData
//   RxData --> pipe7_mac_datapath_ra --> pipe7_rx_burst_fifo --> rx CDC
//          (pclk->lclk) --> ucie2_fdi_egress --> FDI RX flit
//   FDI link state: ucie2_fdi_link_fsm (gates data on FDI_ACTIVE).
//   PIPE control:   pipe7_mac_ctrl_fsm sequences PowerDown/Rate/Width on PhyStatus.
//   Message bus:    pipe7_msgbus_master + pipe7_regfile drive M2P / consume P2M.
//
// Boundary = the FROZEN (Item 0) FDI + PIPE 7.1 signal set, PLUS a documented
// controller-side MANAGEMENT interface (control req + msgbus req) and bridge
// STATUS outputs — these are the bridge's own management/observability ports, not
// PIPE/FDI spec signals. (No TxDataK: SerDes embeds the sync header in TxData —
// crosscheck E.)
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_pipe7_bridge
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FDI_W = FDI_DW,             // FDI transfer width (128)
  parameter int unsigned PW    = PIPE_WIDTH_DEFAULT  // active PIPE parallel width
) (
  // ---- Clocks / reset -------------------------------------------------------
  input  wire                    lclk,
  input  wire                    lclk_rst_n,
  input  wire                    pclk,
  input  wire                    pclk_rst_n,

  // ---- FDI: transmit (Protocol Layer -> bridge) -----------------------------
  input  wire [FDI_W-1:0]        lp_data,
  input  wire                    lp_valid,
  input  wire                    lp_irdy,
  output wire                    pl_trdy,

  // ---- FDI: receive (bridge -> Protocol Layer) ------------------------------
  output wire [FDI_W-1:0]        pl_data,
  output wire                    pl_valid,
  output wire                    pl_flit_cancel,

  // ---- FDI: link state machine ----------------------------------------------
  input  wire [3:0]              lp_state_req,
  output wire [3:0]              pl_state_sts,
  input  wire                    lp_linkerror,
  output wire                    pl_stallreq,
  input  wire                    lp_stallack,

  // ---- FDI: rx-active / clock / wake handshakes -----------------------------
  input  wire                    lp_rx_active_req,
  output wire                    pl_rx_active_sts,
  output wire                    pl_clk_req,
  input  wire                    lp_clk_ack,
  input  wire                    lp_wake_req,
  output wire                    pl_wake_ack,

  // ---- Management: PIPE control request (controller -> bridge) --------------
  input  wire                    req_valid,
  input  wire [1:0]              req_kind,        // ctrl_req_e
  input  wire [3:0]              req_power_down,
  input  wire [3:0]              req_rate,
  input  wire [2:0]              req_width,
  input  wire [2:0]              req_rxwidth,
  output wire                    busy,
  output wire                    done,
  output wire                    req_error,

  // ---- Management: message-bus request (controller -> bridge) ---------------
  input  wire                    mb_req_valid,
  input  wire                    mb_req_write,
  input  wire                    mb_req_committed,
  input  wire [MB_ADDR_WIDTH-1:0] mb_req_addr,
  input  wire [MB_DATA_WIDTH-1:0] mb_req_wdata,
  output wire                    mb_req_ready,
  output wire                    mb_busy,
  output wire                    mb_rsp_valid,
  output wire                    mb_rsp_is_read,
  output wire [MB_DATA_WIDTH-1:0] mb_rsp_rdata,
  output wire                    mb_rsp_error,

  // ---- PIPE 7.1: MAC -> PHY (command; MAC-owned) -----------------------------
  output wire [PW-1:0]           tx_data,
  output wire                    tx_data_valid,
  output wire [3:0]              rate,           // rate_e
  output wire [3:0]              power_down,     // powerdown_e
  output wire [2:0]              width,          // width_e (Tx)
  output wire [2:0]              rx_width,       // width_e (Rx)
  output wire                    tx_detect_rx,
  output wire [3:0]              tx_elec_idle,

  // ---- PIPE 7.1: PHY -> MAC (status; PHY-owned) ------------------------------
  input  wire [PW-1:0]           rx_data,
  input  wire                    rx_valid,
  input  wire                    phy_status,
  input  wire [2:0]              rx_status,
  input  wire                    rx_elec_idle,

  // ---- PIPE 7.1: message bus (config plane) ---------------------------------
  output wire [MB_BUS_WIDTH-1:0] m2p_message_bus,
  input  wire [MB_BUS_WIDTH-1:0] p2m_message_bus,

  // ---- Bridge status / observability ----------------------------------------
  output wire                    block_locked,
  output wire                    sync_error,
  output wire                    in_data_phase,
  output wire                    rx_overflow
);

  localparam int PWID = BLOCK_PAYLOAD + 1;   // CDC block-payload width {is_os,data128}
  wire both_rst_n = lclk_rst_n & pclk_rst_n; // CDC spans both domains

  assign tx_detect_rx = 1'b0;   // Rx-detect not modeled

  // ================= FDI link state machine (lclk) =================
  wire link_active;
  ucie2_fdi_link_fsm link (
    .clk(lclk), .reset_n(lclk_rst_n),
    .lp_state_req, .pl_state_sts, .lp_linkerror, .pl_stallreq, .lp_stallack,
    .lp_rx_active_req, .pl_rx_active_sts, .pl_clk_req, .lp_clk_ack,
    .lp_wake_req, .pl_wake_ack, .link_active(link_active)
  );

  // ================= PIPE control plane (pclk) =================
  /* verilator lint_off UNUSEDSIGNAL */
  wire [3:0] fsm_tx_elec_idle;   // FSM's EI output unused; the datapath owns EI
  wire       rx_standby_nc, pclk_change_ack_nc;
  /* verilator lint_on UNUSEDSIGNAL */
  pipe7_mac_ctrl_fsm #(.PCLK_IS_PHY_INPUT(1'b0)) ctrl (
    .pclk, .reset_n(pclk_rst_n),
    .req_valid, .req_kind(ctrl_req_e'(req_kind)),
    .req_power_down, .req_rate, .req_width, .req_rxwidth,
    .busy, .done, .req_error,
    .power_down, .rate, .width, .rx_width,
    .tx_elec_idle(fsm_tx_elec_idle), .rx_standby(rx_standby_nc),
    .pclk_change_ack(pclk_change_ack_nc),
    .phy_status, .pclk_change_ok(1'b1)
  );

  // ================= Message bus + regfile (pclk) =================
  pipe7_msgbus_master mbus (
    .pclk, .reset_n(pclk_rst_n),
    .req_valid(mb_req_valid), .req_write(mb_req_write), .req_committed(mb_req_committed),
    .req_addr(mb_req_addr), .req_wdata(mb_req_wdata),
    .req_ready(mb_req_ready), .busy(mb_busy),
    .rsp_valid(mb_rsp_valid), .rsp_is_read(mb_rsp_is_read), .rsp_rdata(mb_rsp_rdata),
    .rsp_error(mb_rsp_error),
    .m2p(m2p_message_bus), .p2m(p2m_message_bus)
  );
  wire mb_wr = mb_req_valid && mb_req_ready && mb_req_write;   // write-through
  /* verilator lint_off UNUSEDSIGNAL */
  wire [MB_DATA_WIDTH-1:0]   rf_rdata_nc;
  wire                       rf_hit_nc;
  wire [8*MB_DATA_WIDTH-1:0] rf_snap;
  /* verilator lint_on UNUSEDSIGNAL */
  pipe7_regfile #(.NUM_REGS(8), .BASE_ADDR(REG_PHY_TX_CTRL_BASE)) rf (
    .pclk, .reset_n(pclk_rst_n),
    .host_we(mb_wr), .host_re(1'b0), .host_addr(mb_req_addr), .host_wdata(mb_req_wdata),
    .host_rdata(rf_rdata_nc), .host_hit(rf_hit_nc), .regs_flat(rf_snap)
  );
  localparam int PAM4_IDX = int'(REG_PHY_PAM4_RESTRICTED_LEVELS) - int'(REG_PHY_TX_CTRL_BASE);
  wire [MB_DATA_WIDTH-1:0] pam4_levels = rf_snap[PAM4_IDX*MB_DATA_WIDTH +: MB_DATA_WIDTH];

  // ================= TX: FDI ingress -> CDC -> datapath =================
  wire                     ig_blk_valid, ig_blk_is_os, ig_blk_ready;
  wire [BLOCK_PAYLOAD-1:0] ig_blk_data;
  ucie2_fdi_ingress ingress (
    .lp_data, .lp_valid, .lp_irdy, .pl_trdy, .link_active,
    .blk_valid(ig_blk_valid), .blk_data(ig_blk_data), .blk_is_os(ig_blk_is_os),
    .blk_ready(ig_blk_ready)
  );

  wire            txc_rd_valid, txc_rd_ready, txc_wr_full;
  wire [PWID-1:0] txc_rd_data;
  /* verilator lint_off UNUSEDSIGNAL */
  wire            txc_rd_error, txc_wr_ready_nc;
  /* verilator lint_on UNUSEDSIGNAL */
  assign ig_blk_ready = !txc_wr_full;

  pipe7_cdc_elastic_buf #(.INPUT_DATA_WIDTH(PWID), .OUTPUT_DATA_WIDTH(PWID), .BUFFER_DEPTH(BUFFER_DEPTH)) tx_cdc (
    .wr_clk(lclk), .rd_clk(pclk), .rst_n(both_rst_n),
    .wr_valid(ig_blk_valid && ig_blk_ready), .wr_ready(txc_wr_ready_nc),
    .wr_data({ig_blk_is_os, ig_blk_data}), .wr_error(1'b0), .wr_full(txc_wr_full),
    .rd_valid(txc_rd_valid), .rd_ready(txc_rd_ready), .rd_data(txc_rd_data), .rd_error(txc_rd_error)
  );

  // TX adapter: 1-block/PCLK CDC drives the gearbox burst-accept interface.
  wire        data_enable = txc_rd_valid;
  wire [1:0]  g5_pl_acc;
  wire [1:0]  g5_pl_cnt = txc_rd_valid ? 2'd1 : 2'd0;
  assign txc_rd_ready = |g5_pl_acc;

  wire [1:0]               g5_rx_cnt;
  wire [BLOCK_PAYLOAD-1:0] g5_rx_data0, g5_rx_data1;
  wire                     g5_rx_os0, g5_rx_os1;
  wire                     g6_rx_valid;
  wire [PW-1:0]            g6_rx_data;
  /* verilator lint_off UNUSEDSIGNAL */
  wire                     g6_pl_ready_nc;
  wire [MB_DATA_WIDTH-1:0] pam4_cfg_nc;
  /* verilator lint_on UNUSEDSIGNAL */

  pipe7_mac_datapath_ra #(.PIPE_WIDTH(PW)) datapath (
    .clk(pclk), .reset_n(pclk_rst_n),
    .rate, .power_down, .data_enable, .pam4_restricted_levels(pam4_levels),
    .g5_pl_cnt, .g5_pl_data0(txc_rd_data[BLOCK_PAYLOAD-1:0]), .g5_pl_is_os0(txc_rd_data[BLOCK_PAYLOAD]),
    .g5_pl_data1('0), .g5_pl_is_os1(1'b0), .g5_pl_acc,
    .g6_pl_valid(1'b0), .g6_pl_data('0), .g6_pl_ready(g6_pl_ready_nc),
    .tx_data, .tx_data_valid, .tx_elec_idle,
    .rx_data, .rx_valid,
    .g5_rx_cnt, .g5_rx_data0, .g5_rx_os0, .g5_rx_data1, .g5_rx_os1,
    .g6_rx_valid, .g6_rx_data,
    .block_locked, .sync_error, .in_data_phase, .pam4_cfg_out(pam4_cfg_nc)
  );

  // ================= RX: burst FIFO -> CDC -> FDI egress =================
  wire                     rx_is_gen6 = (rate == RATE_GEN6);
  wire [BLOCK_PAYLOAD-1:0] g6_rx_blk;
  generate
    if (PW >= BLOCK_PAYLOAD) begin : g_g6_trunc
      assign g6_rx_blk = g6_rx_data[BLOCK_PAYLOAD-1:0];
    end else begin : g_g6_pad
      assign g6_rx_blk = {{(BLOCK_PAYLOAD-PW){1'b0}}, g6_rx_data};
    end
  endgenerate

  wire [1:0]      rx_push_cnt = rx_is_gen6 ? {1'b0, g6_rx_valid} : g5_rx_cnt;
  wire [PWID-1:0] rx_din0     = rx_is_gen6 ? {1'b0, g6_rx_blk} : {g5_rx_os0, g5_rx_data0};
  wire [PWID-1:0] rx_din1     = {g5_rx_os1, g5_rx_data1};

  wire            rxb_valid, rxb_overflow;
  wire [PWID-1:0] rxb_data;
  wire            rxc_rd_valid, rxc_rd_ready, rxc_wr_ready;
  wire [PWID-1:0] rxc_rd_data;
  /* verilator lint_off UNUSEDSIGNAL */
  wire            rxc_wr_full, rxc_rd_error;
  /* verilator lint_on UNUSEDSIGNAL */

  pipe7_rx_burst_fifo #(.WIDTH(PWID), .DEPTH(4)) rx_burst (
    .clk(pclk), .reset_n(pclk_rst_n),
    .push_cnt(rx_push_cnt), .din0(rx_din0), .din1(rx_din1),
    .pop_valid(rxb_valid), .pop_data(rxb_data), .pop_ready(rxc_wr_ready),
    .overflow(rxb_overflow)
  );

  pipe7_cdc_elastic_buf #(.INPUT_DATA_WIDTH(PWID), .OUTPUT_DATA_WIDTH(PWID), .BUFFER_DEPTH(BUFFER_DEPTH)) rx_cdc (
    .wr_clk(pclk), .rd_clk(lclk), .rst_n(both_rst_n),
    .wr_valid(rxb_valid), .wr_ready(rxc_wr_ready),
    .wr_data(rxb_data), .wr_error(1'b0), .wr_full(rxc_wr_full),
    .rd_valid(rxc_rd_valid), .rd_ready(rxc_rd_ready), .rd_data(rxc_rd_data), .rd_error(rxc_rd_error)
  );

  ucie2_fdi_egress egress (
    .blk_valid(rxc_rd_valid), .blk_data(rxc_rd_data[BLOCK_PAYLOAD-1:0]),
    .blk_ready(rxc_rd_ready), .link_active(link_active),
    .pl_data, .pl_valid, .pl_flit_cancel
  );

  // ================= RX overflow (registered pulse) =================
  logic rx_overflow_q;
  always_ff @(posedge pclk or negedge pclk_rst_n) begin
    if (!pclk_rst_n) rx_overflow_q <= 1'b0;
    else             rx_overflow_q <= rxb_overflow;
  end
  assign rx_overflow = rx_overflow_q;

  // Intentionally unused: PIPE RxStatus/RxElecIdle (handling is future work) and
  // the recovered block's is_os bit (not forwarded to FDI RX — FLAGGED, crosscheck B).
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused = (|rx_status) | rx_elec_idle | rxc_rd_data[BLOCK_PAYLOAD];
  /* verilator lint_on UNUSEDSIGNAL */

endmodule : ucie2_pipe7_bridge

`default_nettype wire
