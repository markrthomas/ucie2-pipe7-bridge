// ============================================================================
// GENERATED FILE — DO NOT EDIT.
//   Source of truth: rtl/*.sv + dv/uvm/sv/*.  Regenerate: make eda-playground
//   EDA Playground: single all-in-one file (design + testbench)
//   Settings: top = tb_ucie2_pipe7; pick a UVM-capable tool + a UVM version;
//             run-option +UVM_NO_RELNOTES. Assertions need the tool's SVA
//             support enabled (the bound ucie2_pipe7_sva checker).
//   This is a PORTABILITY/DEMO bundle: NOT part of the sacred gate and it
//   cannot run tools/trace_compare.py. Verify by running it in EDA Playground.
// ============================================================================
`timescale 1ns/1ps

// ==== rtl/ucie2_pipe7_pkg.sv ====
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
  // Default active PIPE width (a legal width). Named *_DEFAULT so it does not
  // collide (VARHIDDEN) with the datapath modules' local PIPE_WIDTH parameter.
  parameter int unsigned PIPE_WIDTH_DEFAULT = 80;

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

// ==== rtl/pipe7_cdc_elastic_buf.sv ====


/**
 * pipe7_cdc_elastic_buf -- parameterized dual-clock elastic buffer with
 * Gray-coded pointer CDC and stable registered outputs.
 *
 * Ported from the predecessor `ucie_rdi_fifo_cdc` (proven + formally checked).
 * Crosses the RDI clock domain and the PIPE PCLK domain in either direction:
 *   - TX path: wr = RDI domain, rd = PCLK domain
 *   - RX path: wr = PCLK domain, rd = RDI domain
 * The module itself is domain-agnostic; the instantiating bridge assigns
 * wr_clk / rd_clk to rdi_clk / pclk as appropriate.
 */
module pipe7_cdc_elastic_buf #(
    parameter int INPUT_DATA_WIDTH  = 16,
    parameter int OUTPUT_DATA_WIDTH = 32,
    parameter int BUFFER_DEPTH      = 16
) (
    input  logic                          wr_clk,
    input  logic                          rd_clk,
    input  logic                          rst_n,

    // Write domain
    input  logic                          wr_valid,
    output logic                          wr_ready,
    input  logic [INPUT_DATA_WIDTH-1:0]   wr_data,
    input  logic                          wr_error,
    output logic                          wr_full,

    // Read domain
    output logic                          rd_valid,
    input  logic                          rd_ready,
    output logic [OUTPUT_DATA_WIDTH-1:0]  rd_data,
    output logic                          rd_error
);

    localparam int PTR_WIDTH = $clog2(BUFFER_DEPTH) + 1;

    // Storage is two parallel memories (data + error) rather than an array of a packed
    // {data,error} struct. The two forms are functionally identical, but the parallel-memory
    // form is portable across the independent DV engine (iverilog cannot elaborate an
    // array-of-packed-struct with a bit-select on a field -- it hits a packed-dimensions
    // assertion), whereas Verilator handles both. Keeping this form lets both engines run the
    // identical shipped RTL (see docs/verification_plan.md, Phase G).
    logic [INPUT_DATA_WIDTH-1:0] buf_data  [BUFFER_DEPTH];
    logic                        buf_error [BUFFER_DEPTH];

    // --- Gray Code Conversions ---
    function automatic logic [PTR_WIDTH-1:0] bin2gray(input logic [PTR_WIDTH-1:0] bin);
        return bin ^ (bin >> 1);
    endfunction

    function automatic logic [PTR_WIDTH-1:0] gray2bin(input logic [PTR_WIDTH-1:0] gray);
        logic [PTR_WIDTH-1:0] bin;
        bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
        for (int i = PTR_WIDTH-2; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        return bin;
    endfunction

    // --- Write Domain ---
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] wr_ptr_gray;
    assign wr_ptr_gray = bin2gray(wr_ptr);

    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_valid && wr_ready) begin
            buf_data [wr_ptr[PTR_WIDTH-2:0]] <= wr_data;
            buf_error[wr_ptr[PTR_WIDTH-2:0]] <= wr_error;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    // --- CDC: Write pointer (gray) to Read Domain ---
    logic [PTR_WIDTH-1:0] wr_ptr_gray_sync_r1, wr_ptr_gray_sync;

    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_gray_sync_r1 <= '0;
            wr_ptr_gray_sync <= '0;
        end else begin
            wr_ptr_gray_sync_r1 <= wr_ptr_gray;
            wr_ptr_gray_sync <= wr_ptr_gray_sync_r1;
        end
    end

    // --- Read Domain ---
    logic [PTR_WIDTH-1:0] rd_wr_ptr, rd_ptr;
    logic empty;

    assign rd_wr_ptr = gray2bin(wr_ptr_gray_sync);
    assign empty = (rd_wr_ptr == rd_ptr);

    logic [OUTPUT_DATA_WIDTH-1:0] rd_data_mux;
    logic rd_error_mux;

    generate
        if (OUTPUT_DATA_WIDTH > INPUT_DATA_WIDTH) begin : GEN_EXTEND
            assign rd_data_mux = {{(OUTPUT_DATA_WIDTH-INPUT_DATA_WIDTH){1'b0}},
                                  buf_data[rd_ptr[PTR_WIDTH-2:0]]};
        end else if (OUTPUT_DATA_WIDTH < INPUT_DATA_WIDTH) begin : GEN_TRUNCATE
            assign rd_data_mux = buf_data[rd_ptr[PTR_WIDTH-2:0]][OUTPUT_DATA_WIDTH-1:0];
        end else begin : GEN_DIRECT
            assign rd_data_mux = buf_data[rd_ptr[PTR_WIDTH-2:0]];
        end
    endgenerate
    assign rd_error_mux = buf_error[rd_ptr[PTR_WIDTH-2:0]];

    // Standard registered output FIFO logic
    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr   <= '0;
            rd_valid <= 1'b0;
            rd_data  <= '0;
            rd_error <= 1'b0;
        end else begin
            if (rd_ready || !rd_valid) begin
                if (!empty) begin
                    rd_ptr   <= rd_ptr + 1'b1;
                    rd_valid <= 1'b1;
                    rd_data  <= rd_data_mux;
                    rd_error <= rd_error_mux;
                end else begin
                    rd_valid <= 1'b0;
                end
            end
        end
    end

    // --- CDC: Read pointer (gray) back to Write Domain ---
    logic [PTR_WIDTH-1:0] rd_ptr_gray;
    assign rd_ptr_gray = bin2gray(rd_ptr);

    logic [PTR_WIDTH-1:0] rd_ptr_gray_sync_r1, rd_ptr_gray_sync;

    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr_gray_sync_r1 <= '0;
            rd_ptr_gray_sync <= '0;
        end else begin
            rd_ptr_gray_sync_r1 <= rd_ptr_gray;
            rd_ptr_gray_sync <= rd_ptr_gray_sync_r1;
        end
    end

    logic [PTR_WIDTH-1:0] wr_rd_ptr;
    assign wr_rd_ptr = gray2bin(rd_ptr_gray_sync);

    assign wr_full = (wr_ptr[PTR_WIDTH-2:0] == wr_rd_ptr[PTR_WIDTH-2:0]) &&
                     (wr_ptr[PTR_WIDTH-1] != wr_rd_ptr[PTR_WIDTH-1]);
    assign wr_ready = !wr_full;

endmodule

// ==== rtl/pipe7_gen6_datapath.sv ====


/**
 * pipe7_gen6_datapath -- Gen6 (64 GT/s, Rate=5) wide raw datapath. Closure-plan item 6.
 *
 * Item 0 established that Gen6 at the PIPE interface is NOT "flit mode" and carries NO
 * 128b/130b sync header: it is a wider parallel TxData/RxData conduit of already-encoded
 * data (1b/1b at the PIPE datapath). The 256B flit + FEC + LCRC are built controller-side
 * and arrive on RDI; the bridge does not frame flits on the PIPE side, and PAM4
 * precoding/gray-code is entirely PHY-side (crosscheck B2/I1/I3/I4/G5). So unlike the Gen5
 * path (pipe7_tx_framer/pipe7_rx_deframer, which embed a 2-bit sync header), the Gen6 path
 * is a registered wide pass-through with no block coding and no RX block-alignment hunt --
 * word boundaries are an above-PIPE (controller) concern.
 *
 * The MAC's only PAM4 knob is PAM4RestrictedLevels (a PHY Tx Control field programmed over
 * the message bus, item 4); the precoding math is PHY-side. This block just carries/holds
 * that config value (pam4_cfg_out) alongside the datapath -- there is no generic
 * "precoding-enable" register (crosscheck G5).
 *
 * Active only in gen6_mode (Rate=Gen6); when low the Gen5 framer owns TxData and this block
 * drives no valid. PIPE_WIDTH is the wide Gen6 width (default 160). Rate/Width/L0p control is
 * the ordinary pipe7_mac_ctrl_fsm handshake (L0p = a plain Width/RxWidth change, crosscheck
 * C3/C4) -- not modelled here.
 */
module pipe7_gen6_datapath
    import ucie2_pipe7_pkg::*;
#(
    parameter int PIPE_WIDTH = 160
) (
    input  logic                        clk,
    input  logic                        reset_n,

    input  logic                        gen6_mode,     // 1 = Rate=Gen6 (this path active)
    input  logic [MB_DATA_WIDTH-1:0]    pam4_restricted_levels, // MAC PAM4 config (carried)

    // ---- TX payload in (from RDI datapath / elastic buffer) ----
    input  logic                        tx_pl_valid,
    input  logic [PIPE_WIDTH-1:0]       tx_pl_data,
    output logic                        tx_pl_ready,

    // ---- PIPE MAC Tx (raw wide data; no sync header) ----
    output logic [PIPE_WIDTH-1:0]       tx_data,
    output logic                        tx_data_valid,

    // ---- PIPE MAC Rx (raw wide data; no sync header) ----
    input  logic [PIPE_WIDTH-1:0]       rx_data,
    input  logic                        rx_data_valid,

    // ---- RX payload out ----
    output logic                        rx_pl_valid,
    output logic [PIPE_WIDTH-1:0]       rx_pl_data,

    // ---- Observability ----
    output logic [MB_DATA_WIDTH-1:0]    pam4_cfg_out
);

    // One wide word per PCLK, no coding overhead: accept whenever active.
    assign tx_pl_ready = gen6_mode;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_data       <= '0;
            tx_data_valid <= 1'b0;
            rx_pl_data    <= '0;
            rx_pl_valid   <= 1'b0;
            pam4_cfg_out  <= '0;
        end else begin
            // TX: drive the payload straight onto TxData (no sync header, no 128b/130b).
            tx_data_valid <= gen6_mode && tx_pl_valid;
            if (gen6_mode && tx_pl_valid)
                tx_data <= tx_pl_data;

            // RX: recover the payload directly from RxData (no deframing).
            rx_pl_valid <= gen6_mode && rx_data_valid;
            if (gen6_mode && rx_data_valid)
                rx_pl_data <= rx_data;

            // Hold the MAC-side PAM4 config (programmed via the message bus).
            pam4_cfg_out <= pam4_restricted_levels;
        end
    end

endmodule

// ==== rtl/pipe7_mac_ctrl_fsm.sv ====


/**
 * pipe7_mac_ctrl_fsm -- PIPE 7.1 MAC PowerDown / Rate / Width control sequencer,
 * gated on PhyStatus. Closure-plan item 3 (first behavioral core).
 *
 * Role: accept a control request from the controller side (REQ_POWER / REQ_RATE /
 * REQ_WIDTH), drive the corresponding PIPE MAC command signal(s), and wait for the PHY's
 * single-cycle PhyStatus completion before returning to idle. Enforces the spec legality
 * rule that a Rate/Width change may be requested only in P0 or P1 with TxElecIdle asserted
 * (PIPE 7.1 §8.4.1); illegal requests are rejected with a req_error pulse and no signal
 * change. See docs/interface_spec.md (handshake protocols) and docs/pipe71_spec_crosscheck.md.
 *
 * Clocking: all signals are in the pclk domain. PCLK_IS_PHY_INPUT selects the PCLK-as-PHY
 * -input rate/width handshake (PclkChangeOk -> PclkChangeAck -> PhyStatus); default 0 =
 * PCLK-as-PHY-output (completion is a single PhyStatus pulse). Reset# is async active-low.
 *
 * Scope: control plane only. TxElecIdle is held asserted here (no data phase yet); the
 * datapath deasserts it in P0 data mode from item 5 onward.
 *
 * Completion watchdog (item 28): each PhyStatus/PclkChangeOk wait is bounded by TIMEOUT_CYCLES
 * pclk cycles. A hung PHY no longer hangs the FSM -- on expiry the request is aborted with a
 * req_error pulse and the FSM recovers to S_IDLE (the applied command signals hold their last
 * value; the controller may retry). TIMEOUT_CYCLES=0 disables the watchdog (unbounded wait).
 * The default (1024) never fires in normal operation (PhyStatus completes in << 64 cycles).
 */
module pipe7_mac_ctrl_fsm
    import ucie2_pipe7_pkg::*;
#(
    parameter bit PCLK_IS_PHY_INPUT = 1'b0,
    parameter int TIMEOUT_CYCLES    = 1024
) (
    input  logic        pclk,
    input  logic        reset_n,          // PIPE Reset# (async, active-low)

    // ---- Request interface (controller side) ----
    input  logic        req_valid,        // accepted for one cycle when !busy
    input  ctrl_req_e   req_kind,
    input  logic [3:0]  req_power_down,
    input  logic [3:0]  req_rate,
    input  logic [2:0]  req_width,
    input  logic [2:0]  req_rxwidth,
    output logic        busy,             // high while a request is in flight
    output logic        done,             // 1-cycle pulse: request completed via PhyStatus
    output logic        req_error,        // 1-cycle pulse: request rejected (illegal)

    // ---- PIPE MAC command outputs (MAC -> PHY) ----
    output logic [3:0]  power_down,       // PowerDown[3:0]
    output logic [3:0]  rate,             // Rate[3:0]
    output logic [2:0]  width,            // Width[2:0]
    output logic [2:0]  rx_width,         // RxWidth[2:0]
    output logic [3:0]  tx_elec_idle,     // TxElecIdle[3:0]
    output logic        rx_standby,       // RxStandby
    output logic        pclk_change_ack,  // PclkChangeAck (PCLK-as-PHY-input only)

    // ---- PIPE MAC status inputs (PHY -> MAC) ----
    input  logic        phy_status,       // single-cycle completion
    input  logic        pclk_change_ok    // PHY ready for PCLK/rate/width change
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_PWR_WAIT,       // waiting PhyStatus after a PowerDown change
        S_RW_PREP,        // TxElecIdle asserted; apply Rate/Width next cycle
        S_RW_WAIT_OK,     // (PCLK-input) waiting PclkChangeOk
        S_RW_APPLY_WAIT   // waiting PhyStatus after Rate/Width change
    } state_e;

    state_e     state;
    logic [3:0] shadow_rate;
    logic [2:0] shadow_width;
    logic [2:0] shadow_rxw;

    // Completion watchdog (item 28): count cycles spent waiting on the PHY.
    localparam int WDW = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES + 1);
    logic [WDW-1:0] wd_cnt;
    wire in_wait    = (state == S_PWR_WAIT) || (state == S_RW_WAIT_OK) || (state == S_RW_APPLY_WAIT);
    wire wd_expired = (TIMEOUT_CYCLES != 0) && in_wait && (wd_cnt >= WDW'(TIMEOUT_CYCLES - 1));

    // Rate/Width may be changed only in P0 or P1 (PIPE 7.1 §8.4.1). P0s (1) and P2 (3)
    // are illegal.
    function automatic logic rw_legal(input logic [3:0] pd);
        return (pd == PD_P0) || (pd == PD_P1);
    endfunction

    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= S_IDLE;
            power_down      <= PD_P0;
            rate            <= RATE_GEN5;
            width           <= W_160;
            rx_width        <= W_160;
            tx_elec_idle    <= 4'hF;      // idle until a data phase exists (item 5+)
            rx_standby      <= 1'b1;
            pclk_change_ack <= 1'b0;
            busy            <= 1'b0;
            done            <= 1'b0;
            req_error       <= 1'b0;
            shadow_rate     <= RATE_GEN5;
            shadow_width    <= W_160;
            shadow_rxw      <= W_160;
            wd_cnt          <= '0;
        end else begin
            done      <= 1'b0;            // default-low pulses
            req_error <= 1'b0;

            // Watchdog counter: run while waiting on the PHY, clear otherwise.
            wd_cnt <= in_wait ? (wd_cnt + 1'b1) : '0;

            unique case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (req_valid) begin
                        unique case (req_kind)
                            REQ_POWER: begin
                                power_down <= req_power_down;
                                busy       <= 1'b1;
                                state      <= S_PWR_WAIT;
                            end
                            REQ_RATE, REQ_WIDTH: begin
                                if (rw_legal(power_down)) begin
                                    tx_elec_idle <= 4'hF;   // required asserted for the change
                                    // latch only the requested field(s); others unchanged
                                    shadow_rate  <= (req_kind == REQ_RATE)  ? req_rate    : rate;
                                    shadow_width <= (req_kind == REQ_WIDTH) ? req_width   : width;
                                    shadow_rxw   <= (req_kind == REQ_WIDTH) ? req_rxwidth : rx_width;
                                    busy         <= 1'b1;
                                    state        <= S_RW_PREP;
                                end else begin
                                    req_error <= 1'b1;      // not in P0/P1: reject, no change
                                end
                            end
                            // coverage: unreachable: req_kind is a valid enum (unique case)
                            /* verilator coverage_off */ default: req_error <= 1'b1; /* verilator coverage_on */
                        endcase
                    end
                end

                S_PWR_WAIT: begin
                    if (phy_status) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end else if (wd_expired) begin
                        req_error <= 1'b1;       // PHY never completed: abort + recover
                        busy      <= 1'b0;
                        state     <= S_IDLE;
                    end
                end

                S_RW_PREP: begin
                    rate     <= shadow_rate;
                    width    <= shadow_width;
                    rx_width <= shadow_rxw;
                    state    <= PCLK_IS_PHY_INPUT ? S_RW_WAIT_OK : S_RW_APPLY_WAIT;
                end

                S_RW_WAIT_OK: begin
                    if (pclk_change_ok) begin
                        // In a real PCLK-input design the MAC changes PCLK here; modelled
                        // as an immediate ack once the PHY is ready.
                        pclk_change_ack <= 1'b1;
                        state           <= S_RW_APPLY_WAIT;
                    end else if (wd_expired) begin
                        req_error <= 1'b1;       // PHY never signalled ready: abort + recover
                        busy      <= 1'b0;
                        state     <= S_IDLE;
                    end
                end

                S_RW_APPLY_WAIT: begin
                    if (phy_status) begin
                        pclk_change_ack <= 1'b0;
                        done            <= 1'b1;
                        busy            <= 1'b0;
                        state           <= S_IDLE;
                    end else if (wd_expired) begin
                        pclk_change_ack <= 1'b0;
                        req_error       <= 1'b1; // PHY never completed: abort + recover
                        busy            <= 1'b0;
                        state           <= S_IDLE;
                    end
                end

                // coverage: unreachable defensive default (all states enumerated)
                /* verilator coverage_off */ default: state <= S_IDLE; /* verilator coverage_on */
            endcase
        end
    end

endmodule

// ==== rtl/pipe7_mac_datapath_ra.sv ====


/**
 * pipe7_mac_datapath_ra -- rate-aware MAC datapath (closure-plan item 17). Generalizes the
 * item-15 pipe7_mac_datapath: it muxes the Gen5 128b/130b gearbox (pipe7_tx_framer_gb /
 * pipe7_rx_deframer_gb, up to two blocks/PCLK) against the Gen6 raw wide path
 * (pipe7_gen6_datapath) by Rate, while a data-phase FSM owns TxElecIdle (asserted except while
 * transmitting; a data phase starts only in P0). So TxDataValid is never high while TxElecIdle
 * is asserted (assertion P1) in either rate.
 *
 * Both physical paths are PIPE_WIDTH wide (default 160). Each rate's RX only processes RxData in
 * that rate (rx_valid is gated by the mode) so the inactive deframer never mis-locks on the
 * other mode's data. Width/RxWidth are carried for observation; runtime sub-width (using only
 * the low bits) is a later refinement -- the datapath runs at the physical PIPE_WIDTH here.
 */
module pipe7_mac_datapath_ra
    import ucie2_pipe7_pkg::*;
#(
    parameter int PIPE_WIDTH = 160
) (
    input  logic                     clk,
    input  logic                     reset_n,

    // ---- Control context ----
    input  logic [3:0]               rate,           // RATE_GEN5 / RATE_GEN6
    input  logic [3:0]               power_down,     // data phase only in P0
    input  logic                     data_enable,
    input  logic [MB_DATA_WIDTH-1:0] pam4_restricted_levels,

    // ---- Gen5 block payload in (up to two blocks/PCLK) ----
    input  logic [1:0]               g5_pl_cnt,
    input  logic [BLOCK_PAYLOAD-1:0] g5_pl_data0,
    input  logic                     g5_pl_is_os0,
    input  logic [BLOCK_PAYLOAD-1:0] g5_pl_data1,
    input  logic                     g5_pl_is_os1,
    output logic [1:0]               g5_pl_acc,

    // ---- Gen6 raw payload in (one wide word/PCLK) ----
    input  logic                     g6_pl_valid,
    input  logic [PIPE_WIDTH-1:0]    g6_pl_data,
    output logic                     g6_pl_ready,

    // ---- PIPE MAC Tx ----
    output logic [PIPE_WIDTH-1:0]    tx_data,
    output logic                     tx_data_valid,
    output logic [3:0]               tx_elec_idle,

    // ---- PIPE MAC Rx ----
    input  logic [PIPE_WIDTH-1:0]    rx_data,
    input  logic                     rx_valid,

    // ---- Gen5 recovered blocks out (up to two/PCLK) ----
    output logic [1:0]               g5_rx_cnt,
    output logic [BLOCK_PAYLOAD-1:0] g5_rx_data0,
    output logic                     g5_rx_os0,
    output logic [BLOCK_PAYLOAD-1:0] g5_rx_data1,
    output logic                     g5_rx_os1,

    // ---- Gen6 recovered raw out ----
    output logic                     g6_rx_valid,
    output logic [PIPE_WIDTH-1:0]    g6_rx_data,

    // ---- Status ----
    output logic                     block_locked,
    output logic                     sync_error,
    output logic                     in_data_phase,
    output logic [MB_DATA_WIDTH-1:0] pam4_cfg_out
);

    wire is_gen6 = (rate == RATE_GEN6);

    // ---------------- Data-phase FSM (owns TxElecIdle) ----------------
    typedef enum logic {DP_IDLE, DP_DATA} dp_e;
    dp_e        state;
    logic [1:0] drain_cnt;
    wire        active = (state == DP_DATA);

    assign tx_elec_idle  = active ? 4'h0 : 4'hF;
    assign in_data_phase = active;

    // ---------------- Gen5 gearbox path ----------------
    logic [1:0]            g5_cnt_gated;
    logic [PIPE_WIDTH-1:0] g5_tx_data;
    logic                  g5_tx_valid;

    assign g5_cnt_gated = (active && !is_gen6) ? g5_pl_cnt : 2'd0;

    pipe7_tx_framer_gb #(.PIPE_WIDTH(PIPE_WIDTH)) framer (
        .clk, .reset_n,
        .pl_cnt(g5_cnt_gated), .pl_data0(g5_pl_data0), .pl_is_os0(g5_pl_is_os0),
        .pl_data1(g5_pl_data1), .pl_is_os1(g5_pl_is_os1), .pl_acc(g5_pl_acc),
        .tx_data(g5_tx_data), .tx_data_valid(g5_tx_valid)
    );

    pipe7_rx_deframer_gb #(.PIPE_WIDTH(PIPE_WIDTH)) deframer (
        .clk, .reset_n,
        .rx_data(rx_data), .rx_valid(rx_valid && !is_gen6),
        .pl_cnt(g5_rx_cnt), .pl_data0(g5_rx_data0), .pl_is_os0(g5_rx_os0),
        .pl_data1(g5_rx_data1), .pl_is_os1(g5_rx_os1),
        .block_locked(block_locked), .sync_error(sync_error)
    );

    // ---------------- Gen6 raw path ----------------
    logic                  g6_tx_valid;
    logic [PIPE_WIDTH-1:0]  g6_tx_data;
    wire                    g6_mode = active && is_gen6;

    pipe7_gen6_datapath #(.PIPE_WIDTH(PIPE_WIDTH)) gen6 (
        .clk, .reset_n,
        .gen6_mode(g6_mode), .pam4_restricted_levels,
        .tx_pl_valid(g6_pl_valid), .tx_pl_data(g6_pl_data), .tx_pl_ready(g6_pl_ready),
        .tx_data(g6_tx_data), .tx_data_valid(g6_tx_valid),
        .rx_data(rx_data), .rx_data_valid(rx_valid && is_gen6),
        .rx_pl_valid(g6_rx_valid), .rx_pl_data(g6_rx_data),
        .pam4_cfg_out(pam4_cfg_out)
    );

    // ---------------- Tx mux by rate ----------------
    assign tx_data       = is_gen6 ? g6_tx_data  : g5_tx_data;
    assign tx_data_valid = is_gen6 ? g6_tx_valid : g5_tx_valid;

    // ---------------- Data-phase FSM ----------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= DP_IDLE;
            drain_cnt <= 2'd0;
        end else begin
            unique case (state)
                DP_IDLE: begin
                    drain_cnt <= 2'd0;
                    if (data_enable && (power_down == PD_P0))
                        state <= DP_DATA;
                end
                DP_DATA: begin
                    if (!data_enable && !tx_data_valid) begin
                        if (drain_cnt >= 2'd2) begin state <= DP_IDLE; drain_cnt <= 2'd0; end
                        else                        drain_cnt <= drain_cnt + 2'd1;
                    end else begin
                        drain_cnt <= 2'd0;
                    end
                end
                // coverage: unreachable defensive default (both states enumerated)
                /* verilator coverage_off */ default: state <= DP_IDLE; /* verilator coverage_on */
            endcase
        end
    end

endmodule

// ==== rtl/pipe7_msgbus_master.sv ====


/**
 * pipe7_msgbus_master -- PIPE 7.1 MAC-side message-bus (M2P) master. Closure-plan item 4.
 *
 * Role: turn a single register-access request from the controller side into the spec-shaped
 * M2P framing (PIPE 7.1 §6.1.4.2, Tables 6-10..6-14) and process the PHY's P2M response.
 * The 8-bit bus is PCLK-synchronous and reset by Reset#; idle = 0x00, and any non-idle byte
 * begins a transaction (crosscheck G1/G2/G3/G8).
 *
 * Framing driven on M2P (cmd in the upper nibble, Addr[11:8] in the lower nibble of byte 0):
 *   read              : {READ,        Addr[11:8]}, Addr[7:0]                 (2 bytes)
 *   write_uncommitted : {WR_UNCOMMIT, Addr[11:8]}, Addr[7:0], Data[7:0]      (3 bytes)
 *   write_committed   : {WR_COMMIT,   Addr[11:8]}, Addr[7:0], Data[7:0]      (3 bytes)
 *
 * Response consumed on P2M:
 *   read              : read_completion = {READ_COMPLETION, x}, Data[7:0]    (2 bytes)
 *   write_committed   : write_ack       = {WRITE_ACK, x}                     (start byte)
 *   write_uncommitted : none (completes once framed)
 *
 * Flow control (crosscheck G8): one outstanding transaction per master (enforced structurally
 * -- the FSM is single-transaction and holds `busy`); a committed write blocks until write_ack.
 *
 * Scope: control-plane message framing only. A real design multiplexes several logical
 * requesters ahead of this master; that arbitration is added with the regfile write-through
 * path in item 5+.
 *
 * Response watchdog (item 28): the write_ack / read_completion waits are bounded by
 * TIMEOUT_CYCLES pclk cycles. A hung PHY no longer hangs the master -- on expiry the
 * transaction completes with rsp_valid + rsp_error (the controller sees a failed access and
 * may retry) and the FSM recovers to S_IDLE. TIMEOUT_CYCLES=0 disables the watchdog; the
 * default (1024) never fires in normal operation (P2M completes in a few cycles).
 */
module pipe7_msgbus_master
    import ucie2_pipe7_pkg::*;
#(
    parameter int TIMEOUT_CYCLES = 1024
) (
    input  logic                      pclk,
    input  logic                      reset_n,        // PIPE Reset# (async, active-low)

    // ---- Request interface (controller side) ----
    input  logic                      req_valid,      // accepted for one cycle when req_ready
    input  logic                      req_write,      // 1 = write, 0 = read
    input  logic                      req_committed,  // write only: 1 = committed (wait ack)
    input  logic [MB_ADDR_WIDTH-1:0]  req_addr,
    input  logic [MB_DATA_WIDTH-1:0]  req_wdata,
    output logic                      req_ready,      // high in idle (can accept a request)
    output logic                      busy,           // transaction in flight

    // ---- Response interface (controller side) ----
    output logic                      rsp_valid,      // 1-cycle pulse: transaction complete
    output logic                      rsp_is_read,    // qualifies rsp_rdata
    output logic [MB_DATA_WIDTH-1:0]  rsp_rdata,      // valid with rsp_valid when rsp_is_read
    output logic                      rsp_error,      // reserved (timeout/protocol) -- item 7

    // ---- Message bus ----
    output logic [MB_BUS_WIDTH-1:0]   m2p,            // M2P_MessageBus[7:0] (MAC -> PHY)
    input  logic [MB_BUS_WIDTH-1:0]   p2m             // P2M_MessageBus[7:0] (PHY -> MAC)
);

    localparam logic [7:0] MB_IDLE = 8'h00;

    typedef enum logic [2:0] {
        S_IDLE,        // driving idle; can accept a request
        S_ADDR,        // byte 1: Addr[7:0]
        S_WDATA,       // byte 2: Data[7:0] (writes)
        S_WR_FIN,      // uncommitted write framed -> completion pulse
        S_WACK_WAIT,   // committed write: await write_ack start byte
        S_RC_WAIT1,    // read: await read_completion start byte
        S_RC_WAIT2     // read: capture Data[7:0]
    } state_e;

    state_e                     state;
    logic                       wr_q;        // latched: this is a write
    logic                       committed_q; // latched: committed write
    logic [7:0]                 addr_lo_q;   // Addr[7:0] (byte 1); Addr[11:8] is sent in byte 0
    logic [MB_DATA_WIDTH-1:0]   wdata_q;

    // Command opcode for byte 0 from the latched request kind.
    function automatic logic [3:0] cmd_of(input logic wr, input logic committed);
        if (!wr)            return MB_READ;
        else if (committed) return MB_WRITE_COMMIT;
        else                return MB_WRITE_UNCOMMIT;
    endfunction

    assign req_ready = (state == S_IDLE);
    assign busy      = (state != S_IDLE);

    // Response watchdog (item 28): count cycles spent awaiting a P2M completion.
    localparam int WDW = (TIMEOUT_CYCLES < 2) ? 1 : $clog2(TIMEOUT_CYCLES + 1);
    logic [WDW-1:0] wd_cnt;
    wire in_wait    = (state == S_WACK_WAIT) || (state == S_RC_WAIT1);
    wire wd_expired = (TIMEOUT_CYCLES != 0) && in_wait && (wd_cnt >= WDW'(TIMEOUT_CYCLES - 1));

    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            state       <= S_IDLE;
            m2p         <= MB_IDLE;
            wr_q        <= 1'b0;
            committed_q <= 1'b0;
            addr_lo_q   <= '0;
            wdata_q     <= '0;
            rsp_valid   <= 1'b0;
            rsp_is_read <= 1'b0;
            rsp_rdata   <= '0;
            rsp_error   <= 1'b0;
            wd_cnt      <= '0;
        end else begin
            rsp_valid <= 1'b0;          // default-low 1-cycle pulse
            rsp_error <= 1'b0;          // asserted only on a watchdog timeout (below)
            m2p       <= MB_IDLE;       // default idle unless a state drives a byte

            // Watchdog counter: run while awaiting a P2M response, clear otherwise.
            wd_cnt <= in_wait ? (wd_cnt + 1'b1) : '0;

            unique case (state)
                S_IDLE: begin
                    if (req_valid) begin
                        wr_q        <= req_write;
                        committed_q <= req_write && req_committed;
                        addr_lo_q   <= req_addr[7:0];
                        wdata_q     <= req_wdata;
                        // byte 0: {cmd, Addr[11:8]}
                        m2p   <= {cmd_of(req_write, req_write && req_committed),
                                  req_addr[MB_ADDR_WIDTH-1:8]};
                        state <= S_ADDR;
                    end
                end

                S_ADDR: begin
                    m2p <= addr_lo_q;               // byte 1: Addr[7:0]
                    if (wr_q) state <= S_WDATA;
                    else      state <= S_RC_WAIT1;
                end

                S_WDATA: begin
                    m2p <= wdata_q;                 // byte 2: Data[7:0]
                    if (committed_q) state <= S_WACK_WAIT;
                    else             state <= S_WR_FIN;
                end

                S_WR_FIN: begin
                    // Uncommitted write is complete once framed on the bus.
                    rsp_valid   <= 1'b1;
                    rsp_is_read <= 1'b0;
                    state       <= S_IDLE;
                end

                S_WACK_WAIT: begin
                    if (p2m[7:4] == MB_WRITE_ACK) begin
                        rsp_valid   <= 1'b1;
                        rsp_is_read <= 1'b0;
                        state       <= S_IDLE;
                    end else if (wd_expired) begin
                        rsp_valid   <= 1'b1;     // no write_ack: complete with error + recover
                        rsp_is_read <= 1'b0;
                        rsp_error   <= 1'b1;
                        state       <= S_IDLE;
                    end
                end

                S_RC_WAIT1: begin
                    // read_completion start byte: {READ_COMPLETION, x}
                    if (p2m[7:4] == MB_READ_COMPLETION) state <= S_RC_WAIT2;
                    else if (wd_expired) begin
                        rsp_valid   <= 1'b1;     // no read_completion: complete with error + recover
                        rsp_is_read <= 1'b1;
                        rsp_error   <= 1'b1;
                        state       <= S_IDLE;
                    end
                end

                S_RC_WAIT2: begin
                    rsp_rdata   <= p2m;             // second byte carries Data[7:0]
                    rsp_valid   <= 1'b1;
                    rsp_is_read <= 1'b1;
                    state       <= S_IDLE;
                end

                // coverage: unreachable defensive default (all states enumerated)
                /* verilator coverage_off */ default: state <= S_IDLE; /* verilator coverage_on */
            endcase
        end
    end

endmodule

// ==== rtl/pipe7_regfile.sv ====


/**
 * pipe7_regfile -- MAC-side register file for the PIPE message-bus register space.
 * Closure-plan item 4.
 *
 * A compact, parameterizable 8-bit register file addressed in the 12-bit message-bus
 * address space (PIPE 7.1 §6.1.4.2). It provides the local storage that the message-bus
 * master writes toward / reads back for the MAC-owned configuration this IP programs into
 * the PHY -- Tx equalization presets / de-emphasis and the PAM4RestrictedLevels field in
 * the PHY Tx Control block (0x400..0x40A), and Rx-margining control (crosscheck G4/G5/G6).
 * There is deliberately NO FEC register: FEC lives controller-side and nothing FEC crosses
 * the PIPE boundary (crosscheck G7).
 *
 * The window is [BASE_ADDR, BASE_ADDR+NUM_REGS). Item 0 confirmed the PHY Tx Control base
 * (0x400) and the Rx-margin addresses but did not pin the sub-offset of every named field
 * inside that block, so this file stays a generic addressable window (named fields are
 * documented in docs/pipe71_mac_signal_map.md) rather than hard-coding unverified offsets.
 *
 * Ports: a synchronous host write and a combinational host read (single-cycle), plus a
 * flattened `regs_flat` snapshot for TB/UVM monitors. `host_hit` decodes whether host_addr
 * falls in this file's window. Reset clears all registers.
 */
module pipe7_regfile
    import ucie2_pipe7_pkg::*;
#(
    parameter int                     NUM_REGS  = 8,
    parameter logic [MB_ADDR_WIDTH-1:0] BASE_ADDR = REG_PHY_TX_CTRL_BASE
) (
    input  logic                       pclk,
    input  logic                       reset_n,

    // ---- Host (controller) access port ----
    input  logic                       host_we,
    input  logic                       host_re,
    input  logic [MB_ADDR_WIDTH-1:0]   host_addr,
    input  logic [MB_DATA_WIDTH-1:0]   host_wdata,
    output logic [MB_DATA_WIDTH-1:0]   host_rdata,
    output logic                       host_hit,     // host_addr is within this window

    // ---- Observation ----
    output logic [NUM_REGS*MB_DATA_WIDTH-1:0] regs_flat
);

    localparam int IDX_W = $clog2(NUM_REGS);

    logic [MB_DATA_WIDTH-1:0] regs [NUM_REGS];

    // Window decode. `idx` is meaningful only when in-range (guarded by host_hit); the
    // offset is explicitly truncated to the index width.
    logic [IDX_W-1:0] idx;
    assign idx      = IDX_W'(host_addr - BASE_ADDR);
    assign host_hit = (host_addr >= BASE_ADDR) &&
                      (host_addr <  BASE_ADDR + MB_ADDR_WIDTH'(NUM_REGS));

    // Combinational host read (0 when out of window / not reading).
    always_comb begin
        host_rdata = '0;
        if (host_re && host_hit) host_rdata = regs[idx];
    end

    // Synchronous host write; reset clears the file.
    always_ff @(posedge pclk or negedge reset_n) begin
        if (!reset_n) begin
            for (int i = 0; i < NUM_REGS; i++) regs[i] <= '0;
        end else if (host_we && host_hit) begin
            regs[idx] <= host_wdata;
        end
    end

    // Flattened snapshot for monitors.
    always_comb begin
        for (int i = 0; i < NUM_REGS; i++)
            regs_flat[i*MB_DATA_WIDTH +: MB_DATA_WIDTH] = regs[i];
    end

endmodule

// ==== rtl/pipe7_rx_burst_fifo.sv ====


/**
 * pipe7_rx_burst_fifo -- RX burst-absorption skid FIFO (closure-plan item 29).
 *
 * The full-width Gen5 deframer (pipe7_rx_deframer_gb) can recover UP TO TWO 130b blocks in a
 * single PCLK (a 160-bit RxData word straddling two blocks), but the downstream RDI<->PCLK
 * elastic buffer accepts one block/PCLK. This FIFO absorbs the 0/1/2-blocks-per-cycle burst and
 * drains it one block/PCLK into the CDC. It is the piece that lets the rate-aware datapath fold
 * into the integrated bridge without dropping recovered blocks (as long as the average recovered
 * rate stays <= 1 block/PCLK -- guaranteed when the RDI source rate keeps the datapath below the
 * CDC drain, the same envelope the RX-overflow flag guards).
 *
 * push_cnt (0/1/2) writes din0 then din1 this cycle; pop drains one entry when pop_ready. If a
 * push would exceed DEPTH the excess is dropped and `overflow` pulses (surfaced by the bridge as
 * part of rx_overflow). DEPTH must be >= 3 so a 2-burst on an almost-full FIFO is detectable.
 */
module pipe7_rx_burst_fifo #(
    parameter int WIDTH = 129,   // {is_os, data128}
    parameter int DEPTH = 4
) (
    input  logic             clk,
    input  logic             reset_n,

    // Burst write (up to two entries per cycle).
    input  logic [1:0]       push_cnt,
    input  logic [WIDTH-1:0] din0,
    input  logic [WIDTH-1:0] din1,

    // Single read.
    output logic             pop_valid,
    output logic [WIDTH-1:0] pop_data,
    input  logic             pop_ready,

    output logic             overflow    // 1-cycle pulse: a burst did not fit (block dropped)
);
    localparam int AW = $clog2(DEPTH);
    // DEPTH must be a power of 2: wr_ptr arithmetic relies on natural truncation
    // (AW bits) for correct modulo-DEPTH wrapping without a hardware divider.
    initial begin
        if (DEPTH < 3 || (DEPTH & (DEPTH - 1)) != 0)
            $fatal(1, "pipe7_rx_burst_fifo: DEPTH=%0d must be >= 3 and a power of 2", DEPTH);
    end

    logic [WIDTH-1:0] mem [DEPTH];
    logic [AW:0]      count;
    logic [AW-1:0]    wr_ptr, rd_ptr;

    wire        do_pop = pop_valid && pop_ready;
    // Slots free this cycle = current free entries + the one this cycle's pop releases.
    wire [AW:0] avail  = (DEPTH[AW:0] - count) + (do_pop ? (AW+1)'(1) : (AW+1)'(0));
    // Accept min(push_cnt, avail); push_cnt is 0..2 so avail[1:0] is exact when avail < push_cnt.
    wire [1:0]  accept = (avail >= (AW+1)'(push_cnt)) ? push_cnt : avail[1:0];

    assign pop_valid = (count != 0);
    assign pop_data  = mem[rd_ptr];
    assign overflow  = (accept != push_cnt);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            count  <= '0;
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (accept >= 1) mem[wr_ptr]        <= din0;
            // AW'(1) casts both operands to AW bits before adding so Verilator
            // does not warn about implicit 32-bit expansion of the integer literal.
            // Natural AW-bit truncation = modulo DEPTH (valid because DEPTH is a
            // power of 2 — see assertion above).
            if (accept >= 2) mem[wr_ptr + AW'(1)] <= din1;
            wr_ptr <= wr_ptr + accept[AW-1:0];
            if (do_pop) rd_ptr <= rd_ptr + 1'b1;
            count  <= count + {{(AW-1){1'b0}}, accept} - (do_pop ? {{AW{1'b0}}, 1'b1} : '0);
        end
    end

endmodule

// ==== rtl/pipe7_rx_deframer_gb.sv ====


/**
 * pipe7_rx_deframer_gb -- Gen5 128b/130b RX deframer, full-width gearbox variant (closure-plan
 * item 16). Consumes RxData[PIPE_WIDTH-1:0] and recovers up to TWO 130-bit blocks per PCLK, so
 * a 160-bit word (which can span parts of two blocks) never lets the accumulator overflow.
 * Block alignment is the sync-header hunt with single-bit slip (as pipe7_rx_deframer); up to two
 * legal blocks are extracted per cycle. Inverse bit order of pipe7_tx_framer_gb.
 */
module pipe7_rx_deframer_gb
    import ucie2_pipe7_pkg::*;
#(
    parameter int PIPE_WIDTH = 160
) (
    input  logic                     clk,
    input  logic                     reset_n,

    input  logic [PIPE_WIDTH-1:0]    rx_data,
    input  logic                     rx_valid,

    // Up to two block payloads recovered per cycle.
    output logic [1:0]               pl_cnt,
    output logic [BLOCK_PAYLOAD-1:0] pl_data0,
    output logic                     pl_is_os0,
    output logic [BLOCK_PAYLOAD-1:0] pl_data1,
    output logic                     pl_is_os1,

    output logic                     block_locked,
    output logic                     sync_error
);

    // Headroom for the appended word plus up to two straddling blocks.
    localparam int RACC_W = PIPE_WIDTH + 3*BLOCK_BITS;

    logic [RACC_W-1:0] racc;
    int                rfill;

    wire [RACC_W-1:0] rx_ext = {{(RACC_W-PIPE_WIDTH){1'b0}}, rx_data};

    function automatic logic legal(input logic [1:0] s);
        return (s == SYNC_HDR_DATA) || (s == SYNC_HDR_OS);
    endfunction

    logic [RACC_W-1:0] a_base, a_cur, n_racc;
    int                f_base, f_cur, n_rfill;
    logic [1:0]        s0, s1;
    logic              n_locked, flush;

    always_comb begin
        // Overflow guard: a persistently misaligned/noisy RX stream would otherwise grow the
        // accumulator without bound (append PIPE_WIDTH, slip only one bit). If appending this word
        // would exceed the accumulator, flush and re-hunt from empty and flag sync_error, rather
        // than silently truncating racc. Unreachable on an aligned stream (up to two blocks are
        // drained per cycle), so it never fires on legal data.
        flush = (rfill + PIPE_WIDTH) > RACC_W;

        // Append this cycle's word (if valid), unless flushing.
        if (flush)          begin a_base = '0;                        f_base = 0;                  end
        else if (rx_valid)  begin a_base = racc | (rx_ext << rfill);  f_base = rfill + PIPE_WIDTH; end
        else                begin a_base = racc;                      f_base = rfill;             end

        // Defaults for every comb-assigned signal (no inferred latches).
        pl_cnt     = 2'd0;
        pl_data0   = a_base[BLOCK_BITS-1:2];
        pl_is_os0  = 1'b0;
        pl_data1   = '0;
        pl_is_os1  = 1'b0;
        sync_error = flush ? block_locked : 1'b0;
        n_locked   = flush ? 1'b0 : block_locked;
        s0         = 2'b00;
        s1         = 2'b00;
        a_cur      = a_base;
        f_cur      = f_base;
        n_racc     = a_base;
        n_rfill    = f_base;

        // Extract block 0.
        if (f_cur >= BLOCK_BITS) begin
            s0 = a_cur[1:0];
            if (legal(s0)) begin
                pl_data0  = a_cur[BLOCK_BITS-1:2];
                pl_is_os0 = (s0 == SYNC_HDR_OS);
                pl_cnt    = 2'd1;
                n_locked  = 1'b1;
                a_cur     = a_cur >> BLOCK_BITS;
                f_cur     = f_cur - BLOCK_BITS;
                // Extract block 1 (only if immediately available and legal).
                if (f_cur >= BLOCK_BITS) begin
                    s1 = a_cur[1:0];
                    if (legal(s1)) begin
                        pl_data1  = a_cur[BLOCK_BITS-1:2];
                        pl_is_os1 = (s1 == SYNC_HDR_OS);
                        pl_cnt    = 2'd2;
                        a_cur     = a_cur >> BLOCK_BITS;
                        f_cur     = f_cur - BLOCK_BITS;
                    end
                    // If block 1's header is illegal, leave it: it becomes block 0 next cycle
                    // and is slipped there if still illegal.
                end
            end else begin
                // Not aligned: slip one bit and re-hunt.
                sync_error = block_locked;
                n_locked   = 1'b0;
                a_cur      = a_cur >> 1;
                f_cur      = f_cur - 1;
            end
        end

        n_racc  = a_cur;
        n_rfill = f_cur;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            racc         <= '0;
            rfill        <= 0;
            block_locked <= 1'b0;
        end else begin
            racc         <= n_racc;
            rfill        <= n_rfill;
            block_locked <= n_locked;
        end
    end

endmodule

// ==== rtl/pipe7_tx_framer_gb.sv ====


/**
 * pipe7_tx_framer_gb -- Gen5 128b/130b TX framer, full-width gearbox variant (closure-plan
 * item 16). Unlike pipe7_tx_framer (single block per PCLK, PIPE_WIDTH <= 130), this accepts up
 * to TWO 130-bit blocks per PCLK and emits PIPE_WIDTH bits per PCLK, so the full SerDes width
 * set {10,20,40,80,160} is supported -- at 160 the datapath needs ~1.23 blocks/PCLK, bursting
 * to two.
 *
 * Interface: the controller offers pl_cnt (0/1/2) blocks each cycle on {pl_data0,pl_is_os0} and
 * {pl_data1,pl_is_os1}; pl_acc reports how many were accepted (limited by accumulator room).
 * Bit order matches pipe7_tx_framer: block = {payload, sync[1:0]}, LSB-first onto TxData.
 */
module pipe7_tx_framer_gb
    import ucie2_pipe7_pkg::*;
#(
    parameter int PIPE_WIDTH = 160
) (
    input  logic                     clk,
    input  logic                     reset_n,

    // Up to two block payloads offered per cycle.
    input  logic [1:0]               pl_cnt,      // number offered: 0, 1, or 2
    input  logic [BLOCK_PAYLOAD-1:0] pl_data0,
    input  logic                     pl_is_os0,
    input  logic [BLOCK_PAYLOAD-1:0] pl_data1,
    input  logic                     pl_is_os1,
    output logic [1:0]               pl_acc,      // number accepted this cycle

    output logic [PIPE_WIDTH-1:0]    tx_data,
    output logic                     tx_data_valid
);

    localparam int ACC_W = PIPE_WIDTH + 2*BLOCK_BITS;

    logic [ACC_W-1:0] acc;
    int               fill;

    wire [1:0]            sync0 = pl_is_os0 ? SYNC_HDR_OS : SYNC_HDR_DATA;
    wire [1:0]            sync1 = pl_is_os1 ? SYNC_HDR_OS : SYNC_HDR_DATA;
    wire [ACC_W-1:0]     blk0  = {{(ACC_W-BLOCK_BITS){1'b0}}, pl_data0, sync0};
    wire [ACC_W-1:0]     blk1  = {{(ACC_W-BLOCK_BITS){1'b0}}, pl_data1, sync1};

    logic [ACC_W-1:0] acc_e, n_acc;
    int               fill_e, n_fill, room, room_blocks, take, offered;
    logic             emit;

    always_comb begin
        // Emit one word if we have >= PIPE_WIDTH bits.
        emit = (fill >= PIPE_WIDTH);
        if (emit) begin acc_e = acc >> PIPE_WIDTH; fill_e = fill - PIPE_WIDTH; end
        else      begin acc_e = acc;               fill_e = fill;             end

        // How many whole blocks fit (0/1/2), capped by what's offered.
        room = ACC_W - fill_e;
        if      (room >= 2*BLOCK_BITS) room_blocks = 2;
        else if (room >=   BLOCK_BITS) room_blocks = 1;
        else                           room_blocks = 0;
        offered = int'(pl_cnt);
        take    = (offered < room_blocks) ? offered : room_blocks;

        // Append accepted blocks at the top of the accumulator.
        n_acc  = acc_e;
        n_fill = fill_e;
        if (take >= 1) begin n_acc = n_acc | (blk0 << n_fill); n_fill = n_fill + BLOCK_BITS; end
        if (take >= 2) begin n_acc = n_acc | (blk1 << n_fill); n_fill = n_fill + BLOCK_BITS; end
        pl_acc = take[1:0];
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            acc           <= '0;
            fill          <= 0;
            tx_data       <= '0;
            tx_data_valid <= 1'b0;
        end else begin
            tx_data_valid <= emit;
            tx_data       <= acc[PIPE_WIDTH-1:0];
            acc           <= n_acc;
            fill          <= n_fill;
        end
    end

endmodule

// ==== rtl/ucie2_fdi_egress.sv ====
// -----------------------------------------------------------------------------
// ucie2_fdi_egress — recovered internal 128-bit block -> UCIe 2.0 FDI receive
// (Adapter -> Protocol Layer).
//
// PLAN Item 3. Inverse of ucie2_fdi_ingress: one block == one FDI transfer. FDI
// RX has NO backpressure (crosscheck B), so the adapter always consumes the
// recovered block when the link is ACTIVE and presents it on pl_data/pl_valid.
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_fdi_egress
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FDI_W = FDI_DW,
  parameter int unsigned BLK   = BLOCK_PAYLOAD
) (
  // ---- Block payload input (from the RX CDC), lclk domain ----
  input  wire              blk_valid,
  input  wire [BLK-1:0]    blk_data,
  output wire              blk_ready,
  input  wire              link_active,   // from ucie2_fdi_link_fsm

  // ---- FDI receive (bridge -> Protocol Layer) ----
  output wire [FDI_W-1:0]  pl_data,
  output wire              pl_valid,
  output wire              pl_flit_cancel
);
  // No backpressure on FDI RX: always ready to drain a recovered block while the
  // link is ACTIVE.
  assign blk_ready = link_active;
  assign pl_valid  = blk_valid & link_active;
  // FDI_W == BLK (128); zero-extend defensively if a wider FDI is ever configured.
  assign pl_data   = FDI_W'(blk_data);
  // FLAGGED (crosscheck B): pl_flit_cancel (adapter flit retraction) not modeled.
  assign pl_flit_cancel = 1'b0;

endmodule : ucie2_fdi_egress

`default_nettype wire

// ==== rtl/ucie2_fdi_ingress.sv ====
// -----------------------------------------------------------------------------
// ucie2_fdi_ingress — UCIe 2.0 FDI transmit (Protocol Layer -> Adapter) to the
// internal 128-bit block contract consumed by the MAC datapath.
//
// PLAN Item 3. Because a frozen FDI transfer is FDI_DW = BLOCK_PAYLOAD = 128 bits
// (crosscheck B.1), one FDI transfer is exactly one block — no RDI-style
// multi-word reassembly. This is a combinational valid/ready adapter gated by the
// FDI link state (data flows only when the link is ACTIVE).
// -----------------------------------------------------------------------------
`default_nettype none

module ucie2_fdi_ingress
  import ucie2_pipe7_pkg::*;
#(
  parameter int unsigned FDI_W = FDI_DW,
  parameter int unsigned BLK   = BLOCK_PAYLOAD
) (
  // ---- FDI transmit (Protocol Layer -> bridge), lclk domain ----
  input  wire [FDI_W-1:0]  lp_data,
  input  wire              lp_valid,
  input  wire              lp_irdy,
  output wire              pl_trdy,
  input  wire              link_active,   // from ucie2_fdi_link_fsm

  // ---- Block payload output (to the TX CDC / datapath) ----
  output wire              blk_valid,
  output wire [BLK-1:0]    blk_data,
  output wire              blk_is_os,
  input  wire              blk_ready
);
  // Adapter accepts a transfer only when the downstream block sink is ready and
  // the link is ACTIVE. FDI handshake completes when lp_valid & lp_irdy & pl_trdy.
  assign pl_trdy   = blk_ready & link_active;
  assign blk_valid = lp_valid & lp_irdy & pl_trdy;
  assign blk_data  = lp_data[BLK-1:0];
  // FLAGGED (crosscheck B.1): is_os derivation from FDI flit type is deferred;
  // default every block to a data block until the flit-type hook is added.
  assign blk_is_os = 1'b0;

endmodule : ucie2_fdi_ingress

`default_nettype wire

// ==== rtl/ucie2_fdi_link_fsm.sv ====
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

// ==== rtl/ucie2_pipe7_bridge.sv ====
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
  // fsm_tx_elec_idle is wired to a no-connect; the bridge muxes EI from busy+datapath
  // (see tx_elec_idle assignment below).
  /* verilator lint_off UNUSEDSIGNAL */
  wire [3:0] fsm_tx_elec_idle;
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

  wire [3:0] dp_tx_elec_idle;
  // TxElecIdle ownership: the datapath controls EI in the steady state.
  // When the control FSM is busy (PowerDown/Rate/Width transition in flight) EI
  // must be asserted regardless of the datapath phase.  Mux here so the FSM
  // does not need a dedicated prep-state for PowerDown (busy already holds EI
  // high for the full duration of every in-flight request, satisfying PIPE 7.1
  // §8.4.1 for both Rate/Width and PowerDown transitions).
  assign tx_elec_idle = busy ? 4'hF : dp_tx_elec_idle;

  pipe7_mac_datapath_ra #(.PIPE_WIDTH(PW)) datapath (
    .clk(pclk), .reset_n(pclk_rst_n),
    .rate, .power_down, .data_enable, .pam4_restricted_levels(pam4_levels),
    .g5_pl_cnt, .g5_pl_data0(txc_rd_data[BLOCK_PAYLOAD-1:0]), .g5_pl_is_os0(txc_rd_data[BLOCK_PAYLOAD]),
    .g5_pl_data1('0), .g5_pl_is_os1(1'b0), .g5_pl_acc,
    .g6_pl_valid(1'b0), .g6_pl_data('0), .g6_pl_ready(g6_pl_ready_nc),
    .tx_data, .tx_data_valid, .tx_elec_idle(dp_tx_elec_idle),
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

  // rx_overflow: sticky error flag — set on any burst overflow, cleared only by
  // reset.  A future management soft-clear write will be wired here once the
  // regfile interface is complete.
  logic rx_overflow_q;
  always_ff @(posedge pclk or negedge pclk_rst_n) begin
    if (!pclk_rst_n)      rx_overflow_q <= 1'b0;
    else if (rxb_overflow) rx_overflow_q <= 1'b1;
  end
  assign rx_overflow = rx_overflow_q;

  // Intentionally unused: PIPE RxStatus/RxElecIdle (handling is future work) and
  // the recovered block's is_os bit (not forwarded to FDI RX — FLAGGED, crosscheck B).
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused = (|rx_status) | rx_elec_idle | rxc_rd_data[BLOCK_PAYLOAD];
  /* verilator lint_on UNUSEDSIGNAL */

endmodule : ucie2_pipe7_bridge

`default_nettype wire

// ==== dv/uvm/sv/ucie2_pipe7_sva.sv ====
// -----------------------------------------------------------------------------
// ucie2_pipe7_sva — bound SystemVerilog assertions on the bridge boundary
// (Phase F increment 1, deferred from PLAN item 9).
//
// A checker module bound into `ucie2_pipe7_bridge`.  It contains NO logic and
// drives nothing: it only observes the boundary ports and asserts properties
// that must hold for the directed Gen5 round-trip.  There are deliberately no
// RTL edits — the bind at the bottom of this file attaches it to every
// ucie2_pipe7_bridge instance.
//
// Where it runs:
//   * `make lint-uvm`  — elaborated (compiled) with the SV UVM env.
//   * `make uvm`       — the `--binary` build/run CHECKS the properties
//                        (dv/uvm/vlt/Makefile passes `--assert`).  CI/Railway.
// It is deliberately NOT added to `rtl/` — the root `make lint`, `make pyuvm`
// and `make fcov` source lists are `$(wildcard rtl/*.sv)`, so putting it there
// would silently pull SVA into the Icarus functional-coverage tier and perturb
// the existing (sacred, byte-identical) gate.  This file is additive: it is
// listed only in dv/uvm/vlt/Makefile.
//
// Two clock domains are observed: pclk (PIPE side) and lclk (FDI side).  Each
// property names its own clock and is disabled during that domain's reset.
//
// FLAGGED for a human (see the a_no_tx_while_elec_idle comment): the bridge's
// TxElecIdle mux makes the unqualified PIPE rule "TxDataValid low whenever
// TxElecIdle is asserted" false while the control FSM is `busy`.  The assertion
// below is qualified with `!busy` so it is a true invariant rather than a guess.
// -----------------------------------------------------------------------------
`default_nettype none

// SYNCASYNCNET: the `disable iff (!rst_n)` qualifiers read the same reset nets the
// RTL uses asynchronously. That is the standard way to reset-qualify an assertion
// and implies no synchronous reset flop, so suppress the (-Wall-only) warning here
// rather than weakening the RTL lint. Verified: with this off, RTL + this file
// pass `verilator --lint-only -Wall -sv --timing --assert`.
/* verilator lint_off SYNCASYNCNET */
module ucie2_pipe7_sva (
  // ---- Clocks / resets ----
  input wire        lclk,
  input wire        lclk_rst_n,
  input wire        pclk,
  input wire        pclk_rst_n,

  // ---- PIPE 7.1 Tx (pclk) ----
  input wire        tx_data_valid,
  input wire [3:0]  tx_elec_idle,
  input wire        busy,

  // ---- Bridge status (pclk) ----
  input wire        block_locked,
  input wire        sync_error,
  input wire        rx_overflow,

  // ---- FDI link-state handshake (lclk) ----
  input wire [3:0]  lp_state_req,
  input wire [3:0]  pl_state_sts,
  input wire        lp_linkerror,
  input wire        pl_stallreq,
  input wire        lp_stallack
);

  // ===========================================================================
  // P1 — TxDataValid is never high while TxElecIdle is asserted.
  //
  // pipe7_mac_datapath_ra's data-phase FSM owns TxElecIdle and only leaves the
  // data phase after TxDataValid has been low for the full drain, so
  // `dp_tx_elec_idle == 0` whenever TxDataValid is high.  At the bridge boundary
  // ucie2_pipe7_bridge.sv:214 muxes in `busy ? 4'hF : dp_tx_elec_idle`, which
  // forces EI asserted for an in-flight PowerDown/Rate/Width request regardless
  // of the datapath phase — so the rule is qualified with `!busy` here.  The
  // directed round-trip never raises req_valid, so `busy` is 0 throughout and
  // the qualifier costs no coverage.  Whether the bridge should instead hold off
  // a control request until the datapath has drained is an RTL question, left
  // FLAGGED for a human rather than guessed at.
  // ===========================================================================
  a_no_tx_while_elec_idle: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n)
      (!busy && tx_data_valid) |-> (tx_elec_idle == 4'h0)
  ) else $error("[SVA] tx_data_valid high while tx_elec_idle=%h asserted", tx_elec_idle);

  // ===========================================================================
  // P2 — block lock / sync_error.
  //
  // (a) Structural: the deframer only clears block_locked in the same cycle it
  //     raises sync_error, so lock is sticky while sync_error stays low.  True
  //     for any stimulus.
  // (b) Steady state: once locked, the directed round-trip's clean PHY loopback
  //     never loses alignment, so sync_error stays low.  This is the per-cycle
  //     form of the end-of-test check already in both scoreboards.
  // ===========================================================================
  a_lock_is_sticky: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n)
      (block_locked && !sync_error) |=> block_locked
  ) else $error("[SVA] block_locked dropped without sync_error");

  a_no_sync_error_once_locked: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n)
      block_locked |-> !sync_error
  ) else $error("[SVA] sync_error raised after block_locked");

  // ===========================================================================
  // P3 — the FDI pl_stallreq handshake is well formed (ucie2_fdi_link_fsm).
  //
  // (a) Once requested, the stall is held until the Protocol Layer acks it (or a
  //     link error tears the handshake down).
  // (b) pl_state_sts only ever changes as the result of a completed
  //     stallreq/stallack handshake, or of lp_linkerror.
  // ===========================================================================
  a_stallreq_held_until_ack: assert property (
    @(posedge lclk) disable iff (!lclk_rst_n)
      (pl_stallreq && !lp_stallack && !lp_linkerror) |=> pl_stallreq
  ) else $error("[SVA] pl_stallreq dropped without lp_stallack");

  a_state_change_handshaked: assert property (
    @(posedge lclk) disable iff (!lclk_rst_n)
      (pl_state_sts != $past(pl_state_sts)) |->
        ($past(lp_linkerror) || ($past(pl_stallreq) && $past(lp_stallack)))
  ) else $error("[SVA] pl_state_sts changed to %h outside the stall handshake",
                pl_state_sts);

  // lp_state_req is observed for context only (it is the request the handshake
  // above commits); keep it referenced so strict lint sees no unused port.
  /* verilator lint_off UNUSEDSIGNAL */
  wire _unused_sva = |lp_state_req;
  /* verilator lint_on UNUSEDSIGNAL */

  // ===========================================================================
  // P4 — the RX burst FIFO never overflows in the directed round-trip.
  // rx_overflow is a sticky flag cleared only by reset, so this also proves it
  // never fired earlier in the run.
  // ===========================================================================
  a_no_rx_overflow: assert property (
    @(posedge pclk) disable iff (!pclk_rst_n) !rx_overflow
  ) else $error("[SVA] rx_overflow asserted (RX burst FIFO overran)");

endmodule : ucie2_pipe7_sva
/* verilator lint_on SYNCASYNCNET */

// Bind one checker into every bridge instance.  Connections are by explicit
// name to the bridge's own boundary ports — no RTL hierarchy is reached into.
bind ucie2_pipe7_bridge ucie2_pipe7_sva u_sva (
  .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
  .tx_data_valid(tx_data_valid), .tx_elec_idle(tx_elec_idle), .busy(busy),
  .block_locked(block_locked), .sync_error(sync_error), .rx_overflow(rx_overflow),
  .lp_state_req(lp_state_req), .pl_state_sts(pl_state_sts),
  .lp_linkerror(lp_linkerror), .pl_stallreq(pl_stallreq), .lp_stallack(lp_stallack)
);

`default_nettype wire

// ==== dv/uvm/sv/ucie2_pipe7_if.sv ====
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

// ==== dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv ====
// -----------------------------------------------------------------------------
// ucie2_pipe7_uvm_pkg — SV UVM environment (PLAN item 13).
//
// A real multi-agent UVM env laid out UVM-Cookbook style — one class per file,
// pulled into this single package via ordered `include (the Cookbook's own
// idiom). The tree under dv/uvm/sv/:
//   fdi_agent/  fdi_flit_item, fdi_sequencer, fdi_seq_lib, fdi_driver,
//               fdi_monitor, fdi_agent  (controller-facing agent + stall_ack)
//   pipe_agent/ pipe_monitor (tx), phy_loopback, pipe_agent  (MAC/PHY-facing)
//   env/        bridge_scoreboard, bridge_env
//   test/       ucie2_roundtrip_test
// mirroring the PyUVM tier (dv/pyuvm/{agents,seq_lib,env}.py).
//
// ONE package keeps every shared type (fdi_flit_item, the localparams below, the
// virtual interface) in one compilation unit, so the split is a pure textual
// reorganization: same tokens, same order, same compilation unit -> the emitted
// per-cycle trace is byte-identical and tools/trace_compare.py stays green. The
// component timing tasks are forked by ucie2_roundtrip_test (not via auto
// run_phases) precisely to preserve that fork order.
//
// Include order respects type dependencies: item -> sequencer -> sequence ->
// driver/monitor -> agent, both agents before env, env before test.
// -----------------------------------------------------------------------------
package ucie2_pipe7_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;

  localparam int unsigned N_FLITS      = 8;
  localparam int unsigned BRINGUP_LCLK = 8;
  localparam int unsigned RUN_PCLK     = 200;
  localparam int unsigned PW           = PIPE_WIDTH_DEFAULT;
  localparam int unsigned FDIW         = FDI_DW;

  // FDI controller-facing agent
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_flit_item.sv ----
// -----------------------------------------------------------------------------
// fdi_flit_item — FDI stimulus transaction (PLAN item 13).
//
// One class per file, UVM-Cookbook style. `include`d at package scope by
// ucie2_pipe7_uvm_pkg.sv, so it sees the package localparams (FDIW). Mirrors
// dv/pyuvm/seq_lib/fdi_seq_lib.py's item. Payload is filled by fdi_flit_seq.
// -----------------------------------------------------------------------------
class fdi_flit_item extends uvm_sequence_item;
  rand bit [FDIW-1:0] data;
  bit                 is_os;
  `uvm_object_utils(fdi_flit_item)
  function new(string name = "fdi_flit_item");
    super.new(name);
  endfunction
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_sequencer.sv ----
// -----------------------------------------------------------------------------
// fdi_sequencer — sequencer for fdi_flit_item (PLAN item 13).
//
// A plain uvm_sequencer specialization (UVM-Cookbook style: the sequencer gets
// its own file even when it is a simple typedef). `include`d after
// fdi_flit_item.sv by ucie2_pipe7_uvm_pkg.sv.
// -----------------------------------------------------------------------------
typedef uvm_sequencer#(fdi_flit_item) fdi_sequencer;
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_seq_lib.sv ----
// -----------------------------------------------------------------------------
// fdi_seq_lib — FDI flit sequence (PLAN item 13).
//
// Mirrors dv/pyuvm/seq_lib/fdi_seq_lib.py. Stimulus source is data-driven and
// selected at run time by plusargs so BOTH testbenches drive the identical
// sequence (trace_compare stays byte-identical):
//   +VEC=<path>     -> $readmemh a shared .vec (one 128b payload/line), the
//                      seeded-random or ramp file from dv/common/vectors.
//   (no +VEC)       -> the compiled-in directed ramp
//                      (payload[i] = (0x1000+i)<<64 | (0xABCD0000+i)); this keeps
//                      the self-contained EDA Playground bundle runnable.
//   +N_FLITS=<n>    -> flit count (default N_FLITS localparam = 8).
// `include`d at package scope by ucie2_pipe7_uvm_pkg.sv (sees its localparam N_FLITS).
// -----------------------------------------------------------------------------
class fdi_flit_seq extends uvm_sequence#(fdi_flit_item);
  `uvm_object_utils(fdi_flit_seq)
  function new(string name = "fdi_flit_seq");
    super.new(name);
  endfunction
  virtual task body();
    int unsigned      n_flits;
    string            vec;
    bit               have_vec;
    logic [FDIW-1:0]  mem [int];   // associative: $readmemh-compatible, unbounded
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    have_vec = $value$plusargs("VEC=%s", vec);
    if (have_vec) $readmemh(vec, mem);
    for (int i = 0; i < n_flits; i++) begin
      fdi_flit_item it;
      it = fdi_flit_item::type_id::create($sformatf("flit%0d", i));
      it.data  = have_vec ? mem[i]
                          : ((128'(16'h1000 + i) << 64) | 128'(32'hABCD0000 + i));
      it.is_os = 1'b0;
      start_item(it);
      finish_item(it);
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_driver.sv ----
// -----------------------------------------------------------------------------
// fdi_driver — FDI controller-facing driver + stall-ack responder (PLAN item 13).
//
// Bring-up + directed flit drive on the proven fixed schedule, plus the FDI
// stall handshake. Mirrors dv/pyuvm/agents/fdi_agent.py. The timing tasks
// (drive/stall_ack) are forked by the test in the proven order so the per-cycle
// trace stays byte-identical; get_next_item/item_done are zero sim-time, so
// routing payloads through the sequencer does not perturb the cycle schedule.
// -----------------------------------------------------------------------------
class fdi_driver extends uvm_driver#(fdi_flit_item);
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) drv_ap;   // driven flits -> scoreboard
  `uvm_component_utils(fdi_driver)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    drv_ap = new("drv_ap", this);
  endfunction

  // Forked by the test after cycle 0 is recorded. Identical schedule to the
  // proven stimulus(): request ACTIVE, BRINGUP_LCLK bubbles, then one flit per
  // lclk honoring #0.1 post-edge writes, then deassert.
  virtual task drive();
    int unsigned n_flits;
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    vif.lp_state_req = FDI_ACTIVE;
    repeat (BRINGUP_LCLK) @(posedge vif.lclk);
    for (int i = 0; i < n_flits; i++) begin
      seq_item_port.get_next_item(req);          // zero sim time
      #0.1;
      vif.lp_data  = req.data;
      vif.lp_valid = 1'b1;
      vif.lp_irdy  = 1'b1;
      // FDI flow control: a flit transfers only when lp_valid & lp_irdy & pl_trdy.
      // Hold it (signals stay asserted) until pl_trdy so a burst longer than the
      // internal FIFO never drops flits; for short bursts pl_trdy stays high and
      // the schedule is unchanged. Mirrors the PyUVM driver's pl_trdy gate.
      do begin @(posedge vif.lclk); #0.1; end while (!vif.pl_trdy);
      drv_ap.write(req.data);                     // accepted this cycle
      seq_item_port.item_done();                 // zero sim time
    end
    #0.1;
    vif.lp_valid = 1'b0;
    vif.lp_irdy  = 1'b0;
  endtask

  // Auto-complete the FDI stall handshake: sample at N, drive at N+1 -> visible
  // to the RTL at N+2, matching cocotb's VPI write latency.
  virtual task stall_ack();
    logic captured;
    forever begin
      @(posedge vif.lclk); #0.1;   // cycle N: sample
      captured = vif.pl_stallreq;
      @(posedge vif.lclk); #0.1;   // cycle N+1: drive -> visible at N+2
      vif.lp_stallack = captured;
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_monitor.sv ----
// -----------------------------------------------------------------------------
// fdi_monitor — FDI RX monitor: recovers pl_data flits (PLAN item 13).
//
// Mirrors dv/pyuvm/agents/fdi_agent.py's RX monitor. Its capture() task is forked
// by the test in the proven order; #0.1 post-edge sampling keeps the recovered
// stream (and trace_compare) byte-identical.
// -----------------------------------------------------------------------------
class fdi_rx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [FDIW-1:0]) ap;
  `uvm_component_utils(fdi_rx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.lclk); #0.1;
      if (vif.pl_valid) ap.write(vif.pl_data);
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/fdi_agent/fdi_agent.sv ----
// -----------------------------------------------------------------------------
// fdi_agent — FDI controller-facing agent (PLAN item 13).
//
// Assembles the sequencer + driver + RX monitor and connects the driver to the
// sequencer. Mirrors dv/pyuvm/agents/fdi_agent.py. The driver/monitor timing
// tasks are forked by the test (proven order) so the per-cycle trace stays
// byte-identical.
// -----------------------------------------------------------------------------
class fdi_agent extends uvm_agent;
  fdi_sequencer  seqr;
  fdi_driver     driver;
  fdi_rx_monitor rx_mon;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(fdi_agent)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "fdi_agent: vif not set")
    seqr   = fdi_sequencer::type_id::create("seqr", this);
    driver = fdi_driver::type_id::create("driver", this);
    rx_mon = fdi_rx_monitor::type_id::create("rx_mon", this);
    driver.vif = vif;
    rx_mon.vif = vif;
  endfunction
  virtual function void connect_phase(uvm_phase phase);
    driver.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass
  // PIPE MAC/PHY-facing agent
// ---- inlined from dv/uvm/sv/pipe_agent/pipe_monitor.sv ----
// -----------------------------------------------------------------------------
// pipe_monitor — PIPE MAC-facing TX monitor: captures tx_data words (item 13).
//
// Mirrors the PyUVM PipeTxMonitor. Its capture() task is forked by the test
// (proven order); #0.1 post-edge sampling keeps trace_compare byte-identical.
// -----------------------------------------------------------------------------
class pipe_tx_monitor extends uvm_monitor;
  virtual ucie2_pipe7_if vif;
  uvm_analysis_port#(bit [PW-1:0]) ap;
  `uvm_component_utils(pipe_tx_monitor)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction
  virtual task capture();
    forever begin
      @(posedge vif.pclk); #0.1;
      if (vif.tx_data_valid) ap.write(vif.tx_data);
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/pipe_agent/phy_loopback.sv ----
// -----------------------------------------------------------------------------
// phy_loopback — PIPE PHY loopback: rx <- tx via a 1-cycle shadow (item 13).
//
// Net 2-cycle delay, matching cocotb's VPI write latency so the Gen5 128b/130b
// deframer recovers what the framer sent. Mirrors the PyUVM loopback. Its run()
// task is forked by the test (proven order) so trace_compare stays byte-identical.
// -----------------------------------------------------------------------------
class phy_loopback extends uvm_component;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(phy_loopback)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  // Drive the PREVIOUS cycle's capture at each edge (1-cycle shadow register) so
  // rx = tx from N-1 lands at N+1 = a net 2-cycle delay. Covers every cycle (no
  // skipped slots), preserving block alignment for the deframer.
  virtual task run();
    logic [PW-1:0] cap_data  = '0;
    logic          cap_valid = 1'b0;
    forever begin
      @(posedge vif.pclk); #0.1;
      vif.rx_data  = cap_data;
      vif.rx_valid = cap_valid;
      cap_data  = vif.tx_data;
      cap_valid = vif.tx_data_valid;
    end
  endtask
endclass
// ---- inlined from dv/uvm/sv/pipe_agent/pipe_agent.sv ----
// -----------------------------------------------------------------------------
// pipe_agent — PIPE MAC-facing agent (PLAN item 13).
//
// Assembles the TX monitor + PHY loopback. Mirrors the PyUVM pipe agent. The
// timing tasks are forked by the test (proven order) so the per-cycle trace
// stays byte-identical.
// -----------------------------------------------------------------------------
class pipe_agent extends uvm_agent;
  pipe_tx_monitor tx_mon;
  phy_loopback    loopback;
  virtual ucie2_pipe7_if vif;
  `uvm_component_utils(pipe_agent)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "pipe_agent: vif not set")
    tx_mon   = pipe_tx_monitor::type_id::create("tx_mon", this);
    loopback = phy_loopback::type_id::create("loopback", this);
    tx_mon.vif   = vif;
    loopback.vif = vif;
  endfunction
endclass
  // Environment
// ---- inlined from dv/uvm/sv/env/bridge_scoreboard.sv ----
// -----------------------------------------------------------------------------
// bridge_scoreboard — round-trip identity + datapath invariants (PLAN item 13).
//
// Mirrors the PyUVM BridgeScoreboard: recovered FDI flits (rx_mon) must equal the
// driven flits (driver.drv_ap), the deframer must reach block_locked with no
// sync_error, and at least as many flits as were driven must be recovered (the
// driven count, so the check tracks any run length). TX word count is tracked
// for the report. These are exactly the proven directed test's self-checks.
// The `uvm_analysis_imp_decl macros must precede the class (they define the
// _exp/_rx/_tx analysis-imp specializations it uses).
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_tx)

class bridge_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_exp#(bit [FDIW-1:0], bridge_scoreboard) exp_ap;
  uvm_analysis_imp_rx #(bit [FDIW-1:0], bridge_scoreboard) rx_ap;
  uvm_analysis_imp_tx #(bit [PW-1:0],   bridge_scoreboard) tx_ap;

  bit [FDIW-1:0] exp_q[$];
  bit [FDIW-1:0] rx_q[$];
  int unsigned   tx_count;
  virtual ucie2_pipe7_if vif;

  `uvm_component_utils(bridge_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_ap = new("exp_ap", this);
    rx_ap  = new("rx_ap",  this);
    tx_ap  = new("tx_ap",  this);
  endfunction

  function void write_exp(bit [FDIW-1:0] d); exp_q.push_back(d); endfunction
  function void write_rx (bit [FDIW-1:0] d); rx_q.push_back(d);  endfunction
  function void write_tx (bit [PW-1:0]   d); tx_count++;         endfunction

  virtual function void check_phase(uvm_phase phase);
    if (vif.sync_error !== 1'b0)
      `uvm_error("SB", "deframer raised sync_error")
    if (vif.block_locked !== 1'b1)
      `uvm_error("SB", "deframer never reached block_locked")
    if (rx_q.size() < exp_q.size())
      `uvm_error("SB", $sformatf("only %0d flits recovered (< %0d driven)",
                                 rx_q.size(), exp_q.size()))
    else
      for (int i = 0; i < exp_q.size(); i++)
        if (rx_q[i] !== exp_q[i])
          `uvm_error("SB", $sformatf("round-trip mismatch [%0d]: got %h exp %h",
                                     i, rx_q[i], exp_q[i]))
    `uvm_info("SB", $sformatf("roundtrip: %0d driven, tx %0d words, recovered %0d",
              exp_q.size(), tx_count, rx_q.size()), UVM_LOW)
  endfunction
endclass
// ---- inlined from dv/uvm/sv/env/bridge_env.sv ----
// -----------------------------------------------------------------------------
// bridge_env — FDI agent + PIPE agent + scoreboard, analysis wiring (item 13).
//
// Mirrors dv/pyuvm/env.py. The test forks the components' timing tasks (loopback,
// stall_ack, tx/rx capture, drive) in the proven order and emits the per-cycle
// trace itself, so the byte-identical trace_compare gate is preserved.
// -----------------------------------------------------------------------------
class bridge_env extends uvm_env;
  fdi_agent         agent;
  pipe_agent        pipe;
  bridge_scoreboard sb;
  virtual ucie2_pipe7_if vif;

  `uvm_component_utils(bridge_env)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "bridge_env: vif not set")
    agent = fdi_agent::type_id::create("agent", this);
    pipe  = pipe_agent::type_id::create("pipe", this);
    sb    = bridge_scoreboard::type_id::create("sb", this);
    sb.vif = vif;
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agent.driver.drv_ap.connect(sb.exp_ap);
    agent.rx_mon.ap.connect(sb.rx_ap);
    pipe.tx_mon.ap.connect(sb.tx_ap);
  endfunction
endclass
  // Test (the sacred per-cycle trace emitter)
// ---- inlined from dv/uvm/sv/test/ucie2_roundtrip_test.sv ----
// -----------------------------------------------------------------------------
// ucie2_roundtrip_test — the round-trip UVM test (PLAN item 13).
//
// SACRED TRACE EMITTER. Keeps the EXACT proven orchestration of the prior flat
// test: single 2 ns clocking, reset-deassert wait, cycle 0 sampled BEFORE the
// fork (matches cocotb start_soon), the same fork order, #0.1 post-edge sampling,
// and the same trace columns/payloads. So the emitted per-cycle trace is
// byte-identical and tools/trace_compare.py stays green. The component tasks are
// forked here (not via auto run_phases) precisely to preserve that fork order.
//
// Trace column order MUST match trace_format.TRACE_COLUMNS. Do not edit the
// run_phase body: the byte-identical cross-check depends on it verbatim.
// `include`d LAST at package scope by ucie2_pipe7_uvm_pkg.sv (after env).
// -----------------------------------------------------------------------------
class ucie2_roundtrip_test extends uvm_test;
  `uvm_component_utils(ucie2_roundtrip_test)

  bridge_env             env;
  virtual ucie2_pipe7_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual ucie2_pipe7_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' not set in config_db")
    env = bridge_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    int          fd;
    string       path;
    int unsigned run_pclk;
    fdi_flit_seq seq;
    phase.raise_objection(this);

    // Idle all inputs during reset (identical to the proven directed test).
    vif.lp_data = '0; vif.lp_valid = 0; vif.lp_irdy = 0;
    vif.lp_state_req = '0; vif.lp_linkerror = 0; vif.lp_stallack = 0;
    vif.lp_rx_active_req = 0; vif.lp_clk_ack = 0; vif.lp_wake_req = 0;
    vif.req_valid = 0; vif.req_kind = '0; vif.req_power_down = '0;
    vif.req_rate = '0; vif.req_width = '0; vif.req_rxwidth = '0;
    vif.mb_req_valid = 0; vif.mb_req_write = 0; vif.mb_req_committed = 0;
    vif.mb_req_addr = '0; vif.mb_req_wdata = '0;
    vif.rx_data = '0; vif.rx_valid = 0; vif.phy_status = 0;
    vif.rx_status = '0; vif.rx_elec_idle = 0; vif.p2m_message_bus = '0;

    // Run length (cycles to trace/drain). Default = the RUN_PCLK localparam; the
    // Make flow scales it with the flit count. Read here (zero sim-time, before the
    // wait/fork) so the fork order and #0.1 sampling below are untouched.
    if (!$value$plusargs("RUN_PCLK=%d", run_pclk)) run_pclk = RUN_PCLK;
    if (!$value$plusargs("TRACE=%s", path)) path = "bridge.trace";
    fd = $fopen(path, "w");
    if (fd == 0) `uvm_fatal("TRACE", $sformatf("cannot open %s", path));
    $fwrite(fd,
      "cycle,pl_state_sts,pl_valid,pl_trdy,pl_stallreq,pl_flit_cancel,tx_data_valid,tx_data,rate,power_down\n");

    wait (vif.pclk_rst_n === 1'b1);

    // Cycle 0 sampled BEFORE the forked tasks start (matches cocotb start_soon:
    // cycle 0 sees reset-state inputs -> pl_stallreq==0).
    @(posedge vif.pclk); #0.1;
    $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
      0, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
      vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);

    seq = fdi_flit_seq::type_id::create("seq");

    // Fork the component timing tasks in the SAME order as the proven directed
    // test (loopback, stall_ack, tx capture, rx capture, drive), then start the
    // sequence that feeds the driver.
    fork
      env.pipe.loopback.run();
      env.agent.driver.stall_ack();
      env.pipe.tx_mon.capture();
      env.agent.rx_mon.capture();
      env.agent.driver.drive();
      seq.start(env.agent.seqr);
    join_none

    for (int cyc = 1; cyc < run_pclk; cyc++) begin
      @(posedge vif.pclk); #0.1;
      $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%0d,%0d\n",
        cyc, vif.pl_state_sts, vif.pl_valid, vif.pl_trdy, vif.pl_stallreq,
        vif.pl_flit_cancel, vif.tx_data_valid, vif.tx_data, vif.rate, vif.power_down);
    end
    $fclose(fd);

    phase.drop_objection(this);
  endtask
endclass

endpackage : ucie2_pipe7_uvm_pkg

// ==== dv/uvm/sv/tb_ucie2_pipe7.sv ====
// -----------------------------------------------------------------------------
// tb_ucie2_pipe7 — SV UVM top (SCAFFOLD, PLAN Item 13 seed).
//
// Generates the two independent clocks (PIPE PCLK, FDI lclk), sequences the
// resets, instantiates the DUT + boundary interface (FROZEN Item-0 signal set),
// hands the vif to UVM, and runs the smoke test.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_ucie2_pipe7;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;
  import ucie2_pipe7_uvm_pkg::*;

  localparam int unsigned FDI_W = FDI_DW;
  localparam int unsigned PW    = PIPE_WIDTH_DEFAULT;
  localparam int unsigned MBW   = MB_BUS_WIDTH;

  logic lclk = 0, pclk = 0;
  logic lclk_rst_n = 0, pclk_rst_n = 0;

  // One 2 ns period on both domains (coincident edges) so the bridge is fully
  // synchronous and the directed round-trip is deterministic / cross-sim stable,
  // matching the PyUVM TB (dv/pyuvm/test_roundtrip.py).
  always #1.0 lclk = ~lclk;
  always #1.0 pclk = ~pclk;

  // Reset deasserts at 11 ns — a non-edge time (edges are at even ns) so both
  // simulators agree on the first post-reset cycle.
  initial begin
    lclk_rst_n = 0; pclk_rst_n = 0;
    #11;
    lclk_rst_n = 1; pclk_rst_n = 1;
  end

  ucie2_pipe7_if #(.FDI_W(FDI_W), .PW(PW), .MBW(MBW)) vif (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n)
  );

  ucie2_pipe7_bridge #(.FDI_W(FDI_W), .PW(PW)) dut (
    .lclk(lclk), .lclk_rst_n(lclk_rst_n), .pclk(pclk), .pclk_rst_n(pclk_rst_n),
    // FDI TX
    .lp_data(vif.lp_data), .lp_valid(vif.lp_valid), .lp_irdy(vif.lp_irdy),
    .pl_trdy(vif.pl_trdy),
    // FDI RX
    .pl_data(vif.pl_data), .pl_valid(vif.pl_valid), .pl_flit_cancel(vif.pl_flit_cancel),
    // FDI state machine
    .lp_state_req(vif.lp_state_req), .pl_state_sts(vif.pl_state_sts),
    .lp_linkerror(vif.lp_linkerror), .pl_stallreq(vif.pl_stallreq),
    .lp_stallack(vif.lp_stallack),
    // FDI rx-active / clock / wake
    .lp_rx_active_req(vif.lp_rx_active_req), .pl_rx_active_sts(vif.pl_rx_active_sts),
    .pl_clk_req(vif.pl_clk_req), .lp_clk_ack(vif.lp_clk_ack),
    .lp_wake_req(vif.lp_wake_req), .pl_wake_ack(vif.pl_wake_ack),
    // Management: PIPE control request
    .req_valid(vif.req_valid), .req_kind(vif.req_kind),
    .req_power_down(vif.req_power_down), .req_rate(vif.req_rate),
    .req_width(vif.req_width), .req_rxwidth(vif.req_rxwidth),
    .busy(vif.busy), .done(vif.done), .req_error(vif.req_error),
    // Management: message-bus request
    .mb_req_valid(vif.mb_req_valid), .mb_req_write(vif.mb_req_write),
    .mb_req_committed(vif.mb_req_committed), .mb_req_addr(vif.mb_req_addr),
    .mb_req_wdata(vif.mb_req_wdata), .mb_req_ready(vif.mb_req_ready),
    .mb_busy(vif.mb_busy), .mb_rsp_valid(vif.mb_rsp_valid),
    .mb_rsp_is_read(vif.mb_rsp_is_read), .mb_rsp_rdata(vif.mb_rsp_rdata),
    .mb_rsp_error(vif.mb_rsp_error),
    // PIPE MAC -> PHY
    .tx_data(vif.tx_data), .tx_data_valid(vif.tx_data_valid),
    .rate(vif.rate), .power_down(vif.power_down), .width(vif.width),
    .rx_width(vif.rx_width), .tx_detect_rx(vif.tx_detect_rx),
    .tx_elec_idle(vif.tx_elec_idle),
    // PIPE PHY -> MAC
    .rx_data(vif.rx_data), .rx_valid(vif.rx_valid), .phy_status(vif.phy_status),
    .rx_status(vif.rx_status), .rx_elec_idle(vif.rx_elec_idle),
    // PIPE message bus
    .m2p_message_bus(vif.m2p_message_bus), .p2m_message_bus(vif.p2m_message_bus),
    // Bridge status
    .block_locked(vif.block_locked), .sync_error(vif.sync_error),
    .in_data_phase(vif.in_data_phase), .rx_overflow(vif.rx_overflow)
  );

  initial begin
    uvm_config_db#(virtual ucie2_pipe7_if)::set(null, "*", "vif", vif);
    run_test("ucie2_roundtrip_test");
  end
endmodule : tb_ucie2_pipe7
