"""Directed control-plane test for the FDI link state machine (Phase I item I1).

Exercises ucie2_fdi_link_fsm through the bridge's FDI state ports: fast bring-up
to ACTIVE, real multi-cycle RETRAIN (auto-return to ACTIVE), the low-power / reset
/ disabled managed states, and LINKERROR + recovery. This is a CONTROL-PLANE test
only — it drives no flits and writes no build/bridge.trace, so it is completely
independent of the sacred byte-identical round-trip cross-check. It runs in the
PyUVM tier (`make link-fsm`) and CI.

Observed via pl_state_sts (the FSM's committed state); a stall responder mirrors
pl_stallreq -> lp_stallack so host-requested transitions complete.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# fdi_state_e (pinned encoding — ucie2_pipe7_pkg.sv, crosscheck §C)
RESET, ACTIVE, L1, L2, LINKRESET, LINKERROR, RETRAIN, DISABLED = range(8)
NAMES = {RESET: "RESET", ACTIVE: "ACTIVE", L1: "L1", L2: "L2",
         LINKRESET: "LINKRESET", LINKERROR: "LINKERROR", RETRAIN: "RETRAIN",
         DISABLED: "DISABLED"}
TIMEOUT = 40   # lclk cycles to reach an expected state before failing


def _i(handle):
    try:
        return int(handle.value)
    except Exception:
        return 0


async def _stall_responder(dut):
    """Auto-complete the LPIF stall handshake (mirror pl_stallreq -> lp_stallack)."""
    while True:
        await RisingEdge(dut.lclk)
        dut.lp_stallack.value = _i(dut.pl_stallreq)


async def _await_state(dut, target, timeout=TIMEOUT):
    """Wait until pl_state_sts == target (post-edge reads); return cycles taken."""
    for cyc in range(timeout):
        await RisingEdge(dut.lclk)
        if _i(dut.pl_state_sts) == target:
            return cyc
    got = _i(dut.pl_state_sts)
    raise AssertionError(
        f"pl_state_sts never reached {NAMES[target]} within {timeout} lclk; "
        f"stuck at {NAMES.get(got, got)}")


@cocotb.test()
async def link_fsm(dut):
    cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
    cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

    # Reset both domains; tie every input to a defined idle.
    dut.pclk_rst_n.value = 0
    dut.lclk_rst_n.value = 0
    for name in ("lp_data", "lp_valid", "lp_irdy", "lp_is_os", "lp_state_req", "lp_linkerror",
                 "lp_stallack", "lp_rx_active_req", "lp_clk_ack", "lp_wake_req",
                 "req_valid", "req_kind", "req_power_down", "req_rate", "req_width",
                 "req_rxwidth", "mb_req_valid", "mb_req_write", "mb_req_committed",
                 "mb_req_addr", "mb_req_wdata", "rx_data", "rx_valid", "phy_status",
                 "rx_status", "rx_elec_idle", "p2m_message_bus"):
        if hasattr(dut, name):
            getattr(dut, name).value = 0
    await Timer(10, units="ns")
    dut.pclk_rst_n.value = 1
    dut.lclk_rst_n.value = 1

    cocotb.start_soon(_stall_responder(dut))
    await RisingEdge(dut.lclk)
    assert _i(dut.pl_state_sts) == RESET, "FSM should power up in RESET"

    # 1) Fast bring-up: request ACTIVE -> link comes up.
    dut.lp_state_req.value = ACTIVE
    n = await _await_state(dut, ACTIVE)
    dut._log.info(f"[link-fsm] bring-up: RESET -> ACTIVE in {n} lclk")

    # 2) RETRAIN: request it, see the link leave ACTIVE, train, and auto-return.
    dut.lp_state_req.value = RETRAIN
    await _await_state(dut, RETRAIN)
    assert _i(dut.pl_state_sts) != ACTIVE, "link must be down during RETRAIN"
    dut.lp_state_req.value = ACTIVE          # request up; training auto-returns
    n = await _await_state(dut, ACTIVE)
    dut._log.info(f"[link-fsm] retrain: RETRAIN -> ACTIVE auto-return in {n} lclk")

    # 3) Managed states: each drops the link, then a request to ACTIVE restores it.
    for st in (L1, L2, LINKRESET, DISABLED):
        dut.lp_state_req.value = st
        await _await_state(dut, st)
        assert _i(dut.pl_state_sts) != ACTIVE, f"link must be down in {NAMES[st]}"
        dut.lp_state_req.value = ACTIVE
        await _await_state(dut, ACTIVE)
        dut._log.info(f"[link-fsm] {NAMES[st]} entered and recovered to ACTIVE")

    # 4) LINKERROR: forced by lp_linkerror (sticky), then recovered by request.
    dut.lp_linkerror.value = 1
    await _await_state(dut, LINKERROR)
    dut.lp_linkerror.value = 0
    dut.lp_state_req.value = ACTIVE
    n = await _await_state(dut, ACTIVE)
    dut._log.info(f"[link-fsm] LINKERROR forced and recovered to ACTIVE in {n} lclk")

    dut._log.info("[link-fsm] PASS: bring-up, retrain, managed states, error recovery")
