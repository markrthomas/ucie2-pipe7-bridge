"""Directed Gen6 end-to-end round-trip test (Phase I item I6).

Item B4 proved only a Gen5 round-trip. Gen6 (Rate=5, 64 GT/s PAM4 FLIT) is a raw
WIDE pass-through with NO 128b/130b sync header (crosscheck D): the framer/deframer
are bypassed and the datapath carries the block as one wide PIPE word. This test
runs the bridge at the wide Gen6 width (PW=160, built via -GPW=160), switches the
rate to Gen6 through the mac_ctrl_fsm PhyStatus handshake, then drives FDI flits
and checks they round-trip through the Gen6 datapath (PHY self-loopback).

Own top module (no build/bridge.trace), so it is independent of the sacred Gen5
cross-check. Requires PW>=128 (the Gen6 raw path carries the 128-bit block whole).
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# ucie2_pipe7_pkg encodings
FDI_ACTIVE = 1
RATE_GEN5  = 4
RATE_GEN6  = 5
REQ_RATE   = 1     # ctrl_req_e
BRINGUP_LCLK = 8
N_FLITS      = 8
DRAIN_PCLK   = 200


def _i(handle):
    try:
        return int(handle.value)
    except Exception:
        return 0


async def _loopback(dut):
    """PHY self-loopback: rx follows tx by one pclk (wide Gen6 word)."""
    while True:
        await RisingEdge(dut.pclk)
        dut.rx_data.value  = _i(dut.tx_data)
        dut.rx_valid.value = _i(dut.tx_data_valid)


async def _stall_responder(dut):
    while True:
        await RisingEdge(dut.lclk)
        dut.lp_stallack.value = _i(dut.pl_stallreq)


async def _rx_monitor(dut, out):
    while True:
        await RisingEdge(dut.lclk)
        if _i(dut.pl_valid):
            out.append(_i(dut.pl_data))


@cocotb.test()
async def gen6_roundtrip(dut):
    cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
    cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

    dut.pclk_rst_n.value = 0
    dut.lclk_rst_n.value = 0
    for name in ("lp_data", "lp_valid", "lp_irdy", "lp_is_os", "lp_state_req",
                 "lp_linkerror", "lp_stallack", "lp_rx_active_req", "lp_clk_ack",
                 "lp_wake_req", "req_valid", "req_kind", "req_power_down", "req_rate",
                 "req_width", "req_rxwidth", "mb_req_valid", "mb_req_write",
                 "mb_req_committed", "mb_req_addr", "mb_req_wdata", "rx_data",
                 "rx_valid", "phy_status", "rx_status", "rx_elec_idle",
                 "p2m_message_bus"):
        if hasattr(dut, name):
            getattr(dut, name).value = 0
    await Timer(10, units="ns")
    dut.pclk_rst_n.value = 1
    dut.lclk_rst_n.value = 1

    cocotb.start_soon(_loopback(dut))
    cocotb.start_soon(_stall_responder(dut))
    recovered = []
    cocotb.start_soon(_rx_monitor(dut, recovered))

    assert _i(dut.rate) == RATE_GEN5, "bridge should reset into Gen5"

    # Bring the FDI link up.
    dut.lp_state_req.value = FDI_ACTIVE
    for _ in range(BRINGUP_LCLK):
        await RisingEdge(dut.lclk)

    # Switch Rate to Gen6 via the mac_ctrl_fsm handshake (req -> apply -> PhyStatus).
    # Hold req_valid until the FSM accepts (busy rises): a single-cycle pulse can be
    # missed given cocotb's write latency, and holding it is what a controller does.
    while _i(dut.busy):
        await RisingEdge(dut.pclk)
    dut.req_kind.value  = REQ_RATE
    dut.req_rate.value  = RATE_GEN6
    dut.req_valid.value = 1
    for _ in range(20):
        await RisingEdge(dut.pclk)
        if _i(dut.busy):
            break
    dut.req_valid.value = 0
    assert _i(dut.busy), "control FSM did not accept the rate-change request"
    # In S_RW_APPLY_WAIT now; hold PhyStatus until the FSM completes (busy drops).
    dut.phy_status.value = 1
    for _ in range(20):
        await RisingEdge(dut.pclk)
        if not _i(dut.busy):
            break
    dut.phy_status.value = 0
    await RisingEdge(dut.pclk)
    assert _i(dut.rate) == RATE_GEN6, f"rate did not switch to Gen6 (got {_i(dut.rate)})"
    assert _i(dut.busy) == 0, "control FSM still busy after the rate change"

    # Drive flits; in Gen6 they pass through the raw wide datapath (no framing).
    driven = []
    for i in range(N_FLITS):
        data = (0xC6C6_0000_0000_0000_0000_0000_0000_0000 | i)
        dut.lp_data.value  = data
        dut.lp_valid.value = 1
        dut.lp_irdy.value  = 1
        while True:
            await RisingEdge(dut.lclk)
            if _i(dut.pl_trdy):
                break
        driven.append(data)
    dut.lp_valid.value = 0
    dut.lp_irdy.value  = 0

    for _ in range(DRAIN_PCLK):
        await RisingEdge(dut.pclk)

    assert _i(dut.sync_error) == 0, "Gen6 must not raise the Gen5 deframer sync_error"
    assert recovered == driven, (
        f"Gen6 round-trip mismatch\n  got {[hex(x) for x in recovered]}"
        f"\n  exp {[hex(x) for x in driven]}")
    dut._log.info(f"[gen6] PASS: rate switched Gen5->Gen6; {len(driven)} flits "
                  f"round-tripped through the raw wide datapath")
