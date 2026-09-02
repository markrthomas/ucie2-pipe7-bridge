// -----------------------------------------------------------------------------
// pipe7_mac_ctrl_fsm_formal -- formal (BMC) wrapper for rtl/pipe7_mac_ctrl_fsm.sv.
//
// Phase F increment 3. Read ONLY by the formal tier (`make formal` -> SymbiYosys);
// it is not part of lint / pyuvm / fcov / uvm / trace-compare and it does not
// modify the DUT. Every DUT input is left FREE (unconstrained), so the properties
// below hold for ALL input sequences up to the BMC depth.
//
// Everything is stated on the module BOUNDARY (yosys' Verilog frontend does not
// resolve hierarchical references, so no DUT internal is poked at).
//
// Properties -- the PIPE 7.1 s8.4.1 rate/width legality rule the RTL enforces with
// rw_legal(), plus request/completion handshake well-formedness:
//
//   C1  done and req_error never pulse in the same cycle.
//   C2  done implies !busy (a completion always drops busy in the same cycle).
//   C3  done only ever follows an in-flight request (previous cycle was busy).
//   C4  busy only ever rises on an accepted req_valid.
//   C5  LEGALITY: Rate/Width/RxWidth (the applied PIPE command signals) can only
//       change value out of a cycle in which the FSM was busy, TxElecIdle was
//       asserted on all lanes, and PowerDown was P0 or P1 -- i.e. an illegal
//       power-state rate/width request is NEVER applied (PIPE 7.1 s8.4.1).
//   C6  PowerDown can only change value out of an idle cycle carrying a
//       REQ_POWER request -- no other path moves the P-state.
//   C7  TxElecIdle is held asserted on all four lanes (this block's documented
//       control-plane-only scope).
//   C8  with PCLK_IS_PHY_INPUT=0, PclkChangeAck is never asserted; with
//       PCLK_IS_PHY_INPUT=1, PclkChangeAck only rises the cycle after
//       PclkChangeOk was seen.
//
// Both PCLK handshake parameterizations are proved at once from the same free
// stimulus: u_out = PCLK-as-PHY-output (default), u_in = PCLK-as-PHY-input.
// TIMEOUT_CYCLES is shrunk to 8 so the completion-watchdog path is reachable
// inside a short BMC; the RTL default (1024) is the same logic, wider counter.
// -----------------------------------------------------------------------------
module pipe7_mac_ctrl_fsm_formal #(
    parameter int TIMEOUT_CYCLES = 8
) (
    input logic       pclk,

    // Free (unconstrained) DUT stimulus.
    input logic       req_valid,
    input ucie2_pipe7_pkg::ctrl_req_e req_kind,
    input logic [3:0] req_power_down,
    input logic [3:0] req_rate,
    input logic [2:0] req_width,
    input logic [2:0] req_rxwidth,
    input logic       phy_status,
    input logic       pclk_change_ok
);

    // ---- Reset sequencer: Reset# low in cycle 0, released for ever after. -----
    logic past_valid = 1'b0;
    logic reset_n    = 1'b0;

    always_ff @(posedge pclk) begin
        reset_n    <= 1'b1;
        past_valid <= reset_n;
    end

    // ---- DUT: both PCLK handshake flavours, same free stimulus. ---------------
    logic       busy_o, done_o, err_o, ack_o, rsb_o;
    logic [3:0] pd_o, rate_o, tei_o;
    logic [2:0] w_o, rxw_o;

    pipe7_mac_ctrl_fsm #(
        .PCLK_IS_PHY_INPUT (1'b0),
        .TIMEOUT_CYCLES    (TIMEOUT_CYCLES)
    ) u_out (
        .pclk (pclk), .reset_n (reset_n),
        .req_valid (req_valid), .req_kind (req_kind),
        .req_power_down (req_power_down), .req_rate (req_rate),
        .req_width (req_width), .req_rxwidth (req_rxwidth),
        .busy (busy_o), .done (done_o), .req_error (err_o),
        .power_down (pd_o), .rate (rate_o), .width (w_o), .rx_width (rxw_o),
        .tx_elec_idle (tei_o), .rx_standby (rsb_o), .pclk_change_ack (ack_o),
        .phy_status (phy_status), .pclk_change_ok (pclk_change_ok)
    );

    logic       busy_i, done_i, err_i, ack_i, rsb_i;
    logic [3:0] pd_i, rate_i, tei_i;
    logic [2:0] w_i, rxw_i;

    pipe7_mac_ctrl_fsm #(
        .PCLK_IS_PHY_INPUT (1'b1),
        .TIMEOUT_CYCLES    (TIMEOUT_CYCLES)
    ) u_in (
        .pclk (pclk), .reset_n (reset_n),
        .req_valid (req_valid), .req_kind (req_kind),
        .req_power_down (req_power_down), .req_rate (req_rate),
        .req_width (req_width), .req_rxwidth (req_rxwidth),
        .busy (busy_i), .done (done_i), .req_error (err_i),
        .power_down (pd_i), .rate (rate_i), .width (w_i), .rx_width (rxw_i),
        .tx_elec_idle (tei_i), .rx_standby (rsb_i), .pclk_change_ack (ack_i),
        .phy_status (phy_status), .pclk_change_ok (pclk_change_ok)
    );

    // ---- Previous-cycle shadows (change detection, no $past). -----------------
    logic       busy_o_q, busy_i_q, ack_o_q, ack_i_q;
    logic       req_valid_q, pwr_req_q, ok_q;
    logic [3:0] pd_o_q, pd_i_q, rate_o_q, rate_i_q, tei_o_q, tei_i_q;
    logic [2:0] w_o_q, w_i_q, rxw_o_q, rxw_i_q;

    always_ff @(posedge pclk) begin
        busy_o_q <= busy_o;  busy_i_q <= busy_i;
        ack_o_q  <= ack_o;   ack_i_q  <= ack_i;
        pd_o_q   <= pd_o;    pd_i_q   <= pd_i;
        rate_o_q <= rate_o;  rate_i_q <= rate_i;
        w_o_q    <= w_o;     w_i_q    <= w_i;
        rxw_o_q  <= rxw_o;   rxw_i_q  <= rxw_i;
        tei_o_q  <= tei_o;   tei_i_q  <= tei_i;
        req_valid_q <= req_valid;
        pwr_req_q   <= req_valid && (req_kind == ucie2_pipe7_pkg::REQ_POWER);
        ok_q        <= pclk_change_ok;
    end

    // Did the applied PIPE rate/width command set move this cycle?
    wire cmd_moved_o = (rate_o != rate_o_q) || (w_o != w_o_q) || (rxw_o != rxw_o_q);
    wire cmd_moved_i = (rate_i != rate_i_q) || (w_i != w_i_q) || (rxw_i != rxw_i_q);

    // Was the previous cycle a legal cycle in which to move them (PIPE 7.1 s8.4.1)?
    wire cmd_ok_o = busy_o_q && (tei_o_q == 4'hF)
                 && ((pd_o_q == ucie2_pipe7_pkg::PD_P0) || (pd_o_q == ucie2_pipe7_pkg::PD_P1));
    wire cmd_ok_i = busy_i_q && (tei_i_q == 4'hF)
                 && ((pd_i_q == ucie2_pipe7_pkg::PD_P0) || (pd_i_q == ucie2_pipe7_pkg::PD_P1));

    always_ff @(posedge pclk) begin
        if (reset_n) begin
            // C1 -- completion pulses are mutually exclusive.
            assert (!(done_o && err_o));
            assert (!(done_i && err_i));

            // C2 -- a completion always drops busy.
            assert (!(done_o && busy_o));
            assert (!(done_i && busy_i));

            // C7 -- TxElecIdle held asserted on all lanes.
            assert (tei_o == 4'hF);
            assert (tei_i == 4'hF);

            // C8a -- no PclkChangeAck in the PCLK-as-PHY-output build.
            assert (!ack_o);
        end

        if (past_valid) begin
            // C3 -- done only follows an in-flight request.
            assert (!done_o || busy_o_q);
            assert (!done_i || busy_i_q);

            // C4 -- busy only rises on a req_valid.
            assert (!(busy_o && !busy_o_q) || req_valid_q);
            assert (!(busy_i && !busy_i_q) || req_valid_q);

            // C5 -- LEGALITY: Rate/Width only move out of a legal (busy, TxElecIdle,
            //       P0/P1) cycle. This is the PIPE 7.1 s8.4.1 rule.
            assert (!cmd_moved_o || cmd_ok_o);
            assert (!cmd_moved_i || cmd_ok_i);

            // C6 -- PowerDown only moves out of an idle cycle with a REQ_POWER.
            assert ((pd_o == pd_o_q) || (!busy_o_q && pwr_req_q));
            assert ((pd_i == pd_i_q) || (!busy_i_q && pwr_req_q));

            // C8b -- PclkChangeAck only rises after PclkChangeOk.
            assert (!(ack_i && !ack_i_q) || ok_q);
        end
    end

endmodule
