// -----------------------------------------------------------------------------
// ucie2_pipe7_pkg — shared parameters and types for the UCIe 2.0 (FDI) <-> PCIe
// PIPE 7.1 MAC bridge.
//
// FROZEN by PLAN Item 0 (2026-08-31). Every literal here is either spec-cited or
// carries a `// FLAGGED:` note; the row-by-row basis is in
// docs/ucie2_pipe71_spec_crosscheck.md. Sources:
//   - PIPE 7.1 encodings: Intel Ref 643108 Rev 7.1, via predecessor
//     ~/proj/ucie_rdi_to_pcie6_pipe7/{src/pipe7_pkg.sv,docs/pipe71_spec_crosscheck.md}
//   - FDI signal set / flit mapping: public UCIe 2.0 material (uciedigital, D2D
//     adapter deep-dive) — see the cross-check doc, section B.
// -----------------------------------------------------------------------------
package ucie2_pipe7_pkg;

  // ===========================================================================
  // FDI (Flit-Aware Die-to-Die Interface, controller-facing)
  // ===========================================================================
  // FDI data-transfer width. 128b makes one FDI transfer map 1:1 onto the
  // datapath's internal 128-bit block {is_os,data128} (crosscheck B.1).
  parameter int unsigned FDI_DW         = 128;
  // Standard UCIe flit size; 256 B => 16 transfers/flit at FDI_DW=128.
  // lint_off UNUSEDPARAM: forward-declared for the Phase-B FDI front-end.
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned FDI_FLIT_BYTES = 256;
  /* verilator lint_on UNUSEDPARAM */

  // FDI link states. The state SET is FDI/LPIF-aligned; the numeric encodings
  // are our choice.
  // FLAGGED: fdi_state_e encodings not spec-pinned (crosscheck section C).
  typedef enum logic [3:0] {
    FDI_RESET     = 4'd0,
    FDI_ACTIVE    = 4'd1,
    FDI_L1        = 4'd2,
    FDI_L2        = 4'd3,
    FDI_LINKRESET = 4'd4,
    FDI_LINKERROR = 4'd5,
    FDI_RETRAIN   = 4'd6,
    FDI_DISABLED  = 4'd7
  } fdi_state_e;

  // ===========================================================================
  // Internal block contract (FDI front-end <-> datapath), spec-cited framing
  // ===========================================================================
  // Gen5 128b/130b block: 2-bit sync header + 128-bit payload = 130 bits. The
  // sync header is embedded in TxData/RxData by the MAC (no discrete block-coding
  // pins in SerDes). crosscheck section G; PCIe 6.x 128b/130b.
  // lint_off UNUSEDPARAM: the block-contract constants are consumed by the
  // Phase-B FDI front-end / gearbox, not by this shell.
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned SYNC_HDR_BITS = 2;
  parameter int unsigned BLOCK_PAYLOAD = 128;
  parameter int unsigned BLOCK_BITS    = SYNC_HDR_BITS + BLOCK_PAYLOAD;  // 130
  parameter logic [1:0]  SYNC_HDR_DATA = 2'b10;   // Data block
  parameter logic [1:0]  SYNC_HDR_OS   = 2'b01;   // Ordered-Set block
  /* verilator lint_on UNUSEDPARAM */
  // FLAGGED: is_os derivation from FDI flit type deferred to the front-end
  //          (crosscheck B.1) — defaults to data blocks until then.

  // ===========================================================================
  // PIPE 7.1 MAC-facing (SerDes architecture, PCIe Gen5+Gen6) — reused, spec-cited
  // ===========================================================================
  // Max PIPE parallel data width; legal widths per width_e are {10,20,40,80,160}.
  // The bridge's PIPE_WIDTH parameter picks the active width (default 80).
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned PIPE_WIDTH_MAX = 160;     // consumed by Phase-B datapath
  parameter int unsigned BUFFER_DEPTH   = 16;      // CDC elastic-buffer entries
  /* verilator lint_on UNUSEDPARAM */
  parameter int unsigned PIPE_WIDTH     = 80;      // shell default (a legal width)

  // PowerDown[3:0] (Ref 643108 Table 6-5). 0..3 P-states; 4..15 PHY-specific.
  typedef enum logic [3:0] {
    PD_P0  = 4'h0,
    PD_P0S = 4'h1,
    PD_P1  = 4'h2,
    PD_P2  = 4'h3
  } powerdown_e;

  // Rate[3:0] (Ref 643108 Table 6-5). Gen5=32GT/s=4, Gen6=64GT/s=5 in scope.
  typedef enum logic [3:0] {
    RATE_2P5  = 4'd0,
    RATE_5P0  = 4'd1,
    RATE_8P0  = 4'd2,
    RATE_16P0 = 4'd3,
    RATE_GEN5 = 4'd4,   // 32 GT/s, 128b/130b (in scope)
    RATE_GEN6 = 4'd5,   // 64 GT/s, PAM4 FLIT (in scope)
    RATE_128  = 4'd6
  } rate_e;

  // Width[2:0] / RxWidth[2:0] (Ref 643108 Tables 6-5/6-16). PCIe SerDes bits.
  typedef enum logic [2:0] {
    W_10  = 3'd0,
    W_20  = 3'd1,
    W_40  = 3'd2,
    W_80  = 3'd3,
    W_160 = 3'd4
  } width_e;

  // Control FSM request kinds (what pipe7_mac_ctrl_fsm is asked to sequence).
  typedef enum logic [1:0] {
    REQ_POWER = 2'd0,
    REQ_RATE  = 2'd1,
    REQ_WIDTH = 2'd2
  } ctrl_req_e;

  // ===========================================================================
  // Message bus + register map (Ref 643108 Table 6-10) — reused, spec-cited
  // ===========================================================================
  typedef enum logic [3:0] {
    MB_NOP             = 4'h0,
    MB_WRITE_UNCOMMIT  = 4'h1,
    MB_WRITE_COMMIT    = 4'h2,
    MB_READ            = 4'h3,
    MB_READ_COMPLETION = 4'h4,
    MB_WRITE_ACK       = 4'h5
  } msgbus_cmd_e;

  parameter int unsigned MB_BUS_WIDTH  = 8;    // M2P/P2M_MessageBus[7:0]
  parameter int unsigned MB_ADDR_WIDTH = 12;   // 12-bit register address space
  // lint_off UNUSEDPARAM: data width + register addresses feed the Phase-B
  // msgbus master / regfile, not this shell.
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned MB_DATA_WIDTH = 8;

  parameter logic [MB_ADDR_WIDTH-1:0] REG_PHY_TX_CTRL_BASE = 12'h400;
  parameter logic [MB_ADDR_WIDTH-1:0] REG_PHY_TX_CTRL_END  = 12'h40A;
  // Working sub-offset for PAM4RestrictedLevels (exact spec offset not pinned;
  // same caveat as the predecessor). crosscheck section F.
  parameter logic [MB_ADDR_WIDTH-1:0] REG_PHY_PAM4_RESTRICTED_LEVELS = 12'h406;
  /* verilator lint_on UNUSEDPARAM */
  // FLAGGED: register file <-> UCIe 2.0 management/sideband transport mapping is
  //          future work (crosscheck section F); the msgbus loop is the config
  //          plane for now.

endpackage : ucie2_pipe7_pkg
