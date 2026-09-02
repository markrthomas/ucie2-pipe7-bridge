// -----------------------------------------------------------------------------
// ucie2_fdi_link_fsm_formal -- formal (BMC) wrapper for rtl/ucie2_fdi_link_fsm.sv.
//
// Phase F increment 3. Read ONLY by the formal tier (`make formal` -> SymbiYosys);
// no RTL is modified and nothing here is compiled by lint / pyuvm / fcov / uvm /
// trace-compare. All DUT inputs are FREE except the one assumption below, so the
// properties hold for ALL input sequences up to the BMC depth.
//
// This is the "no illegal FSM state" proof, aimed squarely at the FLAGGED item in
// ucie2_pipe7_pkg / docs/ucie2_pipe71_spec_crosscheck.md section C: the
// fdi_state_e encodings are our choice, not spec-pinned. The FSM's state IS its
// pl_state_sts output, so the property is stated on the boundary (yosys' Verilog
// frontend does not resolve hierarchical references into the DUT).
//
// Assumption (the protocol-layer contract): lp_state_req always carries a legal
// fdi_state_e encoding (0..7 = FDI_RESET..FDI_DISABLED). Everything else -- the
// stall handshake, link error, rx-active/clk/wake -- is unconstrained.
//
// Properties:
//   L1  pl_state_sts is ALWAYS a legal fdi_state_e encoding (no illegal state).
//   L2  link_active is exactly (pl_state_sts == FDI_ACTIVE) -- the datapath gate
//       can never open outside FDI_ACTIVE.
//   L3  HANDSHAKE: pl_state_sts only changes out of a cycle that either raised
//       lp_linkerror, or completed the stall handshake (pl_stallreq & lp_stallack).
//   L4  lp_linkerror forces FDI_LINKERROR on the next cycle, with pl_stallreq low.
//   L5  pl_stallreq only rises when a *different* state was actually requested.
//   L6  pl_rx_active_sts / pl_wake_ack are exact 1-cycle mirrors of their requests.
//   L7  pl_clk_req is exactly the registered (FDI_ACTIVE || pl_stallreq).
// -----------------------------------------------------------------------------
module ucie2_fdi_link_fsm_formal (
    input logic       clk,

    // Free (unconstrained, apart from the L1 assumption) DUT stimulus.
    input logic [3:0] lp_state_req,
    input logic       lp_linkerror,
    input logic       lp_stallack,
    input logic       lp_rx_active_req,
    input logic       lp_clk_ack,
    input logic       lp_wake_req
);

    // ---- Reset sequencer: reset_n low in cycle 0, released for ever after. ----
    logic past_valid = 1'b0;
    logic reset_n    = 1'b0;

    always_ff @(posedge clk) begin
        reset_n    <= 1'b1;
        past_valid <= reset_n;
    end

    logic [3:0] pl_state_sts;
    logic       pl_stallreq, pl_rx_active_sts, pl_clk_req, pl_wake_ack, link_active;

    ucie2_fdi_link_fsm u_dut (
        .clk              (clk),
        .reset_n          (reset_n),
        .lp_state_req     (lp_state_req),
        .pl_state_sts     (pl_state_sts),
        .lp_linkerror     (lp_linkerror),
        .pl_stallreq      (pl_stallreq),
        .lp_stallack      (lp_stallack),
        .lp_rx_active_req (lp_rx_active_req),
        .pl_rx_active_sts (pl_rx_active_sts),
        .pl_clk_req       (pl_clk_req),
        .lp_clk_ack       (lp_clk_ack),
        .lp_wake_req      (lp_wake_req),
        .pl_wake_ack      (pl_wake_ack),
        .link_active      (link_active)
    );

    // ---- Previous-cycle shadows (no $past). ----------------------------------
    logic [3:0] sts_q, req_q;
    logic       stallreq_q, stallack_q, linkerror_q, rxreq_q, wakereq_q, active_q;

    always_ff @(posedge clk) begin
        sts_q       <= pl_state_sts;
        req_q       <= lp_state_req;
        stallreq_q  <= pl_stallreq;
        stallack_q  <= lp_stallack;
        linkerror_q <= lp_linkerror;
        rxreq_q     <= lp_rx_active_req;
        wakereq_q   <= lp_wake_req;
        active_q    <= (pl_state_sts == ucie2_pipe7_pkg::FDI_ACTIVE) || pl_stallreq;
    end

    always_ff @(posedge clk) begin
        // The protocol layer only ever requests a legal FDI link state.
        assume (lp_state_req <= ucie2_pipe7_pkg::FDI_DISABLED);

        if (reset_n) begin
            // L1 -- no illegal FSM state.
            assert (pl_state_sts <= ucie2_pipe7_pkg::FDI_DISABLED);

            // L2 -- the datapath gate is exactly "in FDI_ACTIVE".
            assert (link_active == (pl_state_sts == ucie2_pipe7_pkg::FDI_ACTIVE));
        end

        if (past_valid) begin
            // L3 -- state only moves via link error or a completed stall handshake.
            assert ((pl_state_sts == sts_q) || linkerror_q || (stallreq_q && stallack_q));

            // L4 -- a link error forces LINKERROR and drops the stall request.
            assert (!linkerror_q || (pl_state_sts == ucie2_pipe7_pkg::FDI_LINKERROR));
            assert (!linkerror_q || !pl_stallreq);

            // L5 -- pl_stallreq only rises on a genuinely different request.
            assert (!(pl_stallreq && !stallreq_q) || (req_q != sts_q));

            // L6 -- rx-active / wake are exact registered mirrors.
            assert (pl_rx_active_sts == rxreq_q);
            assert (pl_wake_ack == wakereq_q);

            // L7 -- pl_clk_req is the registered "active or stalling".
            assert (pl_clk_req == active_q);
        end
    end

endmodule
