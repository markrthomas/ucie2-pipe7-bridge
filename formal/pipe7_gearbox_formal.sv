// -----------------------------------------------------------------------------
// pipe7_gearbox_formal -- formal (BMC) wrapper for the Gen5 128b/130b gearbox pair
// rtl/pipe7_tx_framer_gb.sv + rtl/pipe7_rx_deframer_gb.sv.
//
// Phase F increment 3. Read ONLY by the formal tier (`make formal` -> SymbiYosys);
// no RTL is modified and nothing here is compiled by lint / pyuvm / fcov / uvm /
// trace-compare. Every DUT input is FREE (unconstrained) -- in particular the
// deframer sees an arbitrary, possibly garbage, RxData stream, which is exactly
// the case the sync-header hunt has to survive.
//
// Both DUTs are proved at the PIPE_WIDTH the bridge defaults to
// (ucie2_pipe7_pkg::PIPE_WIDTH_DEFAULT = 80). Properties are stated on the module
// boundary only (yosys' Verilog frontend does not resolve hierarchical references),
// so the framer's accumulator invariant is re-derived from observable I/O by
// counting blocks in and words out.
//
// TX framer -- "gearbox sync legality", the flow/occupancy side:
//   T1  pl_acc <= pl_cnt: the framer never accepts more blocks than were offered.
//   T2  pl_acc is never the illegal count 3.
//   T3  ACCUMULATOR INVARIANT (no overflow, no underflow). The fill implied by the
//       observable interface -- BLOCK_BITS * (blocks accepted) minus PIPE_WIDTH *
//       (words emitted) -- always stays within [0, ACC_W]. So the gearbox never
//       drops payload bits and never emits a word it does not have, for ANY
//       offer pattern.
//
// RX deframer -- "gearbox sync legality", the block-alignment side:
//   R1  pl_cnt is never the illegal count 3.
//   R2  a sync error is only ever raised from a locked state (sync_error ->
//       block_locked): an unlocked hunt never reports an error.
//   R3  a sync error never comes with a delivered block (sync_error -> pl_cnt==0):
//       a block with an illegal sync header is NEVER passed upstream.
//   R4  a sync error always drops lock on the next cycle.
//   R5  delivering a block always implies lock on the next cycle.
//   R6  unused block slots are quiet: pl_cnt<2 -> pl_data1/pl_is_os1 are zero, and
//       pl_cnt==0 -> pl_is_os0 is zero.
// -----------------------------------------------------------------------------
module pipe7_gearbox_formal #(
    parameter int PIPE_WIDTH = ucie2_pipe7_pkg::PIPE_WIDTH_DEFAULT
) (
    input logic                                   clk,

    // Free stimulus -- TX framer side.
    input logic [1:0]                             pl_cnt_in,
    input logic [ucie2_pipe7_pkg::BLOCK_PAYLOAD-1:0] pl_data0_in,
    input logic                                   pl_is_os0_in,
    input logic [ucie2_pipe7_pkg::BLOCK_PAYLOAD-1:0] pl_data1_in,
    input logic                                   pl_is_os1_in,

    // Free stimulus -- RX deframer side (arbitrary, possibly illegal, line data).
    input logic [PIPE_WIDTH-1:0]                  rx_data,
    input logic                                   rx_valid
);

    localparam int BLOCK_BITS = ucie2_pipe7_pkg::BLOCK_BITS;   // 130
    localparam int ACC_W      = PIPE_WIDTH + 2*BLOCK_BITS;     // framer accumulator

    // ---- Reset sequencer: reset_n low in cycle 0, released for ever after. ----
    logic past_valid = 1'b0;
    logic reset_n    = 1'b0;

    always_ff @(posedge clk) begin
        reset_n    <= 1'b1;
        past_valid <= reset_n;
    end

    // =========================================================================
    // TX framer
    // =========================================================================
    logic [1:0]            pl_acc;
    logic [PIPE_WIDTH-1:0] tx_data;
    logic                  tx_data_valid;

    pipe7_tx_framer_gb #(.PIPE_WIDTH (PIPE_WIDTH)) u_tx (
        .clk           (clk),
        .reset_n       (reset_n),
        .pl_cnt        (pl_cnt_in),
        .pl_data0      (pl_data0_in),
        .pl_is_os0     (pl_is_os0_in),
        .pl_data1      (pl_data1_in),
        .pl_is_os1     (pl_is_os1_in),
        .pl_acc        (pl_acc),
        .tx_data       (tx_data),
        .tx_data_valid (tx_data_valid)
    );

    // Observable reconstruction of the framer's accumulator occupancy. Counting
    // only starts once Reset# is released, exactly like the DUT's own registers.
    // tx_data_valid is the registered "emit", so the occupancy implied at this
    // cycle is (blocks in) - (words already out + the word going out now).
    // (Kept multiplier-free -- constant-selected increments only -- so the BMC
    // formula stays small.)
    wire signed [31:0] bits_in = (pl_acc == 2'd2) ? 32'(2*BLOCK_BITS)
                               : (pl_acc == 2'd1) ? 32'(BLOCK_BITS) : 32'sd0;

    logic signed [31:0] tx_bal;   // BLOCK_BITS*(blocks in) - PIPE_WIDTH*(words out)
    always_ff @(posedge clk) begin
        if (!reset_n) tx_bal <= 32'sd0;
        else          tx_bal <= tx_bal + bits_in - (tx_data_valid ? 32'(PIPE_WIDTH) : 32'sd0);
    end

    // The word leaving this cycle was already subtracted from the DUT's fill one
    // cycle earlier (tx_data_valid is the registered "emit"), so correct for it.
    wire signed [31:0] tx_fill = tx_bal - (tx_data_valid ? 32'(PIPE_WIDTH) : 32'sd0);

    // =========================================================================
    // RX deframer
    // =========================================================================
    logic [1:0]                                  rx_pl_cnt;
    logic [ucie2_pipe7_pkg::BLOCK_PAYLOAD-1:0]   rx_pl_data0, rx_pl_data1;
    logic                                        rx_pl_is_os0, rx_pl_is_os1;
    logic                                        block_locked, sync_error;

    pipe7_rx_deframer_gb #(.PIPE_WIDTH (PIPE_WIDTH)) u_rx (
        .clk          (clk),
        .reset_n      (reset_n),
        .rx_data      (rx_data),
        .rx_valid     (rx_valid),
        .pl_cnt       (rx_pl_cnt),
        .pl_data0     (rx_pl_data0),
        .pl_is_os0    (rx_pl_is_os0),
        .pl_data1     (rx_pl_data1),
        .pl_is_os1    (rx_pl_is_os1),
        .block_locked (block_locked),
        .sync_error   (sync_error)
    );

    logic sync_error_q, cnt_nz_q;
    always_ff @(posedge clk) begin
        sync_error_q <= sync_error;
        cnt_nz_q     <= (rx_pl_cnt != 2'd0);
    end

    // =========================================================================
    // Properties
    // =========================================================================
    always_ff @(posedge clk) begin
        if (reset_n) begin
            // T1 / T2 -- the framer never over-accepts.
            assert (pl_acc <= pl_cnt_in);
            assert (pl_acc != 2'd3);

            // T3 -- accumulator invariant: no overflow, no underflow.
            assert (tx_fill >= 0);
            assert (tx_fill <= ACC_W);

            // R1 -- the deframer never claims an illegal block count.
            assert (rx_pl_cnt != 2'd3);

            // R2 -- an error is only raised from a locked state.
            assert (!sync_error || block_locked);

            // R3 -- a block with an illegal sync header is never passed upstream.
            assert (!sync_error || (rx_pl_cnt == 2'd0));

            // R6 -- unused block slots are quiet.
            assert ((rx_pl_cnt == 2'd2) || (!rx_pl_is_os1 && (rx_pl_data1 == '0)));
            assert ((rx_pl_cnt != 2'd0) || !rx_pl_is_os0);
        end

        if (past_valid) begin
            // R4 -- a sync error always drops lock.
            assert (!sync_error_q || !block_locked);

            // R5 -- delivering a block always implies lock.
            assert (!cnt_nz_q || block_locked);
        end
    end

endmodule
