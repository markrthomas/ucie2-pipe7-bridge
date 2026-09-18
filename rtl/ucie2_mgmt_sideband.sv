// -----------------------------------------------------------------------------
// ucie2_mgmt_sideband — UCIe 2.0 management/sideband register-access transport
// (Phase I I4; resolves the §F FLAG).
//
// UCIe 2.0 standardises a management transport with register access carried over
// the sideband. This block is that transport for the bridge's *local* management
// register space: a controller-side register request (read/write of a management
// register) is serialised into a UCIe-2.0-style sideband packet, delivered over
// an on-die serial sideband bus to a completer, which performs the register-file
// access and returns a completion packet. The requester captures the read data /
// status and pulses a response. This is deliberately distinct from the PIPE 7.1
// M2P/P2M message bus (pipe7_msgbus_master), which is the MAC<->PHY config plane;
// here the register file is mapped onto the UCIe-2.0 management/sideband transport.
//
// Serial sideband framing (idle = 0x00; opcode nibbles are non-zero, so idle is
// unambiguous — crosscheck §F). Bytes are one per pclk on the 8-bit sideband:
//   request  (m2c): {op, Addr[11:8]}, Addr[7:0], [Data[7:0] on writes]
//   completion(c2m): {CPL, status},   [Data[7:0] on reads]
// op ∈ {SB_MGMT_RD, SB_MGMT_WR}; status ∈ {SB_CPL_OK, SB_CPL_ERR} (ERR = the
// address hit no management register). Reads return a data byte; writes do not.
//
// The requester and completer FSMs both live here and are wired back-to-back over
// the internal m2c/c2m 8-bit buses (registered, one outstanding transaction), so
// the whole request→serialise→access→complete round trip is a genuine transport,
// not a combinational shortcut. A response watchdog bounds the completion wait
// (TIMEOUT_CYCLES; 0 disables) so a wedged completer cannot hang the requester —
// same pattern as pipe7_msgbus_master.
//
// Not on the datapath: byte-identical Gen5 round-trip is unaffected (the sacred
// trace never issues a management request). The m2c/c2m taps are exposed for
// waves/monitors.
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_mgmt_sideband
  import ucie2_pipe7_pkg::*;
#(
  parameter int TIMEOUT_CYCLES = 1024
) (
  input  wire                      pclk,
  input  wire                      reset_n,

  // ---- Requester (controller) side ----
  input  wire                      req_valid,      // accepted for one cycle when req_ready
  input  wire                      req_write,      // 1 = write, 0 = read
  input  wire [MB_ADDR_WIDTH-1:0]  req_addr,
  input  wire [MB_DATA_WIDTH-1:0]  req_wdata,
  output wire                      req_ready,       // high in idle (can accept a request)
  output wire                      busy,            // transaction in flight

  output logic                     rsp_valid,       // 1-cycle pulse: transaction complete
  output logic                     rsp_is_read,     // qualifies rsp_rdata
  output logic [MB_DATA_WIDTH-1:0] rsp_rdata,       // valid with rsp_valid when rsp_is_read
  output logic                     rsp_error,       // completion status != OK (or timeout)

  // ---- Register-file host port (completer -> management regfile) ----
  output logic                     rf_we,
  output logic                     rf_re,
  output logic [MB_ADDR_WIDTH-1:0] rf_addr,
  output logic [MB_DATA_WIDTH-1:0] rf_wdata,
  input  wire  [MB_DATA_WIDTH-1:0] rf_rdata,
  input  wire                      rf_hit,          // rf_addr is a real management register

  // ---- Sideband observability taps (for waves/monitors) ----
  output logic [MB_BUS_WIDTH-1:0]  sb_m2c,          // requester -> completer serial byte
  output logic [MB_BUS_WIDTH-1:0]  sb_c2m           // completer -> requester serial byte
);

  localparam logic [7:0] SB_IDLE = 8'h00;

  // ===========================================================================
  // Requester FSM: serialise a request onto m2c, await the completion on c2m.
  // ===========================================================================
  typedef enum logic [2:0] {
    M_IDLE,        // driving idle; can accept a request
    M_ADDR,        // byte 1: Addr[7:0]
    M_WDATA,       // byte 2: Data[7:0] (writes)
    M_CPL_HDR,     // await completion header {CPL, status}
    M_CPL_DATA     // read: capture Data[7:0]
  } mstate_e;

  mstate_e                     mstate;
  logic                        m_wr_q;      // latched: this is a write
  logic [7:0]                  m_addr_lo_q; // Addr[7:0]
  logic [MB_DATA_WIDTH-1:0]    m_wdata_q;
  logic [3:0]                  m_status_q;  // latched completion status

  assign req_ready = (mstate == M_IDLE);
  assign busy      = (mstate != M_IDLE);

  // Completion watchdog: bound the c2m wait so a wedged completer can't hang us.
  localparam int WDW = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES + 1);
  logic [WDW-1:0] wd_cnt;
  wire m_in_wait    = (mstate == M_CPL_HDR);
  wire m_wd_expired = (TIMEOUT_CYCLES != 0) && m_in_wait &&
                      (wd_cnt >= WDW'(TIMEOUT_CYCLES - 1));

  always_ff @(posedge pclk or negedge reset_n) begin
    if (!reset_n) begin
      mstate      <= M_IDLE;
      sb_m2c      <= SB_IDLE;
      m_wr_q      <= 1'b0;
      m_addr_lo_q <= '0;
      m_wdata_q   <= '0;
      m_status_q  <= '0;
      rsp_valid   <= 1'b0;
      rsp_is_read <= 1'b0;
      rsp_rdata   <= '0;
      rsp_error   <= 1'b0;
      wd_cnt      <= '0;
    end else begin
      rsp_valid <= 1'b0;        // default-low 1-cycle pulse
      sb_m2c    <= SB_IDLE;     // default idle unless a state drives a byte
      wd_cnt    <= m_in_wait ? (wd_cnt + 1'b1) : '0;

      unique case (mstate)
        M_IDLE: begin
          if (req_valid) begin
            m_wr_q      <= req_write;
            m_addr_lo_q <= req_addr[7:0];
            m_wdata_q   <= req_wdata;
            // byte 0: {op, Addr[11:8]}
            sb_m2c <= {(req_write ? SB_MGMT_WR : SB_MGMT_RD),
                       req_addr[MB_ADDR_WIDTH-1:8]};
            mstate <= M_ADDR;
          end
        end

        M_ADDR: begin
          sb_m2c <= m_addr_lo_q;            // byte 1: Addr[7:0]
          mstate <= m_wr_q ? M_WDATA : M_CPL_HDR;
        end

        M_WDATA: begin
          sb_m2c <= m_wdata_q;              // byte 2: Data[7:0]
          mstate <= M_CPL_HDR;
        end

        M_CPL_HDR: begin
          if (sb_c2m[7:4] == SB_MGMT_CPL) begin
            m_status_q <= sb_c2m[3:0];
            if (m_wr_q) begin               // write: completion is header-only
              rsp_valid   <= 1'b1;
              rsp_is_read <= 1'b0;
              rsp_error   <= (sb_c2m[3:0] != SB_CPL_OK);
              mstate      <= M_IDLE;
            end else begin
              mstate <= M_CPL_DATA;
            end
          end else if (m_wd_expired) begin
            rsp_valid   <= 1'b1;            // no completion: fail + recover
            rsp_is_read <= ~m_wr_q;
            rsp_error   <= 1'b1;
            mstate      <= M_IDLE;
          end
        end

        M_CPL_DATA: begin
          rsp_rdata   <= sb_c2m;            // read data byte
          rsp_valid   <= 1'b1;
          rsp_is_read <= 1'b1;
          rsp_error   <= (m_status_q != SB_CPL_OK);
          mstate      <= M_IDLE;
        end

        // coverage: unreachable defensive default (all states enumerated)
        /* verilator coverage_off */ default: mstate <= M_IDLE; /* verilator coverage_on */
      endcase
    end
  end

  // ===========================================================================
  // Completer FSM: de-serialise m2c, perform the register access, return c2m.
  // ===========================================================================
  typedef enum logic [2:0] {
    C_IDLE,        // watching m2c for a request header
    C_ADDR,        // byte 1: Addr[7:0]
    C_WDATA,       // byte 2: Data[7:0] (writes)
    C_ACCESS,      // drive the regfile host port, capture read data / hit
    C_CPL_HDR,     // drive completion header {CPL, status}
    C_CPL_DATA     // read: drive Data[7:0]
  } cstate_e;

  cstate_e                     cstate;
  logic                        c_wr_q;
  logic [3:0]                  c_addr_hi_q; // Addr[11:8] from header
  logic [7:0]                  c_addr_lo_q; // Addr[7:0]
  logic [MB_DATA_WIDTH-1:0]    c_wdata_q;
  logic [MB_DATA_WIDTH-1:0]    c_rdata_q;   // captured read data
  logic [3:0]                  c_status_q;  // captured access status

  // Regfile host port is combinational off cstate; access happens in C_ACCESS.
  always_comb begin
    rf_we    = (cstate == C_ACCESS) &&  c_wr_q;
    rf_re    = (cstate == C_ACCESS) && !c_wr_q;
    rf_addr  = {{(MB_ADDR_WIDTH-12){1'b0}}, c_addr_hi_q, c_addr_lo_q};
    rf_wdata = c_wdata_q;
  end

  always_ff @(posedge pclk or negedge reset_n) begin
    if (!reset_n) begin
      cstate      <= C_IDLE;
      sb_c2m      <= SB_IDLE;
      c_wr_q      <= 1'b0;
      c_addr_hi_q <= '0;
      c_addr_lo_q <= '0;
      c_wdata_q   <= '0;
      c_rdata_q   <= '0;
      c_status_q  <= '0;
    end else begin
      sb_c2m <= SB_IDLE;          // default idle unless a state drives a byte

      unique case (cstate)
        C_IDLE: begin
          // A non-idle m2c byte with a read/write opcode starts a transaction.
          if (sb_m2c[7:4] == SB_MGMT_RD || sb_m2c[7:4] == SB_MGMT_WR) begin
            c_wr_q      <= (sb_m2c[7:4] == SB_MGMT_WR);
            c_addr_hi_q <= sb_m2c[3:0];
            cstate      <= C_ADDR;
          end
        end

        C_ADDR: begin
          c_addr_lo_q <= sb_m2c;            // byte 1: Addr[7:0]
          cstate      <= c_wr_q ? C_WDATA : C_ACCESS;
        end

        C_WDATA: begin
          c_wdata_q <= sb_m2c;             // byte 2: Data[7:0]
          cstate    <= C_ACCESS;
        end

        C_ACCESS: begin
          // rf_re/rf_we asserted this cycle (combinational); rf_rdata/rf_hit valid now.
          c_rdata_q  <= rf_rdata;
          c_status_q <= rf_hit ? SB_CPL_OK : SB_CPL_ERR;
          cstate     <= C_CPL_HDR;
        end

        C_CPL_HDR: begin
          sb_c2m <= {SB_MGMT_CPL, c_status_q};   // completion header
          cstate <= c_wr_q ? C_IDLE : C_CPL_DATA;
        end

        C_CPL_DATA: begin
          sb_c2m <= c_rdata_q;             // read data byte
          cstate <= C_IDLE;
        end

        // coverage: unreachable defensive default (all states enumerated)
        /* verilator coverage_off */ default: cstate <= C_IDLE; /* verilator coverage_on */
      endcase
    end
  end

endmodule : ucie2_mgmt_sideband

`default_nettype wire
