"""Directed pl_flit_cancel + RX-overflow test (Phase I item I3, + deferred I5/I6
overflow injection).

pl_flit_cancel was FLAGGED (crosscheck B). Model: when the RX datapath loses data
(the burst FIFO overflows), the recovered stream can no longer be trusted, so the
adapter RETRACTS each subsequently-presented flit -- pl_flit_cancel asserts with
pl_valid so the protocol layer discards it.

This test forces a real RX FIFO overflow (the producer/consumer rate mismatch that
is only reachable at a wide PIPE width): built at PW=160, a 160-bit Gen5 word
carries ~1.23 130-bit blocks, and injecting a dense back-to-back framed stream
pushes the depth-4 burst FIFO past its 1-block/PCLK drain. It then checks
rx_overflow sets and that flits are presented BOTH clean (before the overflow) and
retracted (pl_flit_cancel, after it). Own top module, no bridge.trace.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import framing_model as fm

PIPE_WIDTH   = 160    # built via -GPW=160; wide enough that RxData > 1 block/PCLK
FDI_ACTIVE   = 1
BRINGUP_LCLK = 8
N_FLITS      = 96     # dense stream, plenty to overflow the depth-4 burst FIFO
DRAIN_PCLK   = 120


def _i(handle):
    try:
        return int(handle.value)
    except Exception:
        return 0


async def _stall_responder(dut):
    while True:
        await RisingEdge(dut.lclk)
        dut.lp_stallack.value = _i(dut.pl_stallreq)


async def _rx_flit_monitor(dut, st):
    """On each presented FDI RX flit, record whether it was retracted."""
    while True:
        await RisingEdge(dut.lclk)
        if _i(dut.pl_valid):
            if _i(dut.pl_flit_cancel):
                st["cancelled"] += 1
            else:
                st["clean"] += 1


async def _ovf_monitor(dut, st):
    while True:
        await RisingEdge(dut.pclk)
        if _i(dut.rx_overflow):
            st["rx_overflow"] = 1


@cocotb.test()
async def flit_cancel(dut):
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

    st = {"clean": 0, "cancelled": 0, "rx_overflow": 0}
    cocotb.start_soon(_stall_responder(dut))
    cocotb.start_soon(_rx_flit_monitor(dut, st))
    cocotb.start_soon(_ovf_monitor(dut, st))

    # Bring the FDI link up (Gen5, the reset default).
    dut.lp_state_req.value = FDI_ACTIVE
    for _ in range(BRINGUP_LCLK):
        await RisingEdge(dut.lclk)

    # Inject a dense back-to-back framed stream: RxData valid every PCLK so the
    # recovered-block rate (>1/PCLK at PW=160) exceeds the FIFO drain.
    words = fm.frame_stream([(0xD00D_0000_0000_0000_0000_0000_0000_0000 | i, False)
                             for i in range(N_FLITS)], PIPE_WIDTH)
    for w in words:
        dut.rx_data.value  = w
        dut.rx_valid.value = 1
        await RisingEdge(dut.pclk)
    dut.rx_valid.value = 0
    dut.rx_data.value  = 0

    for _ in range(DRAIN_PCLK):
        await RisingEdge(dut.pclk)

    assert st["rx_overflow"] == 1, (
        "RX burst FIFO never overflowed — dense stream did not exceed the drain "
        f"(clean={st['clean']} cancelled={st['cancelled']})")
    assert st["clean"] >= 1, "no flit was presented cleanly before the overflow"
    assert st["cancelled"] >= 1, (
        "overflow occurred but no flit was retracted via pl_flit_cancel")
    dut._log.info(
        f"[flit-cancel] PASS: rx_overflow set; {st['clean']} flit(s) delivered clean, "
        f"{st['cancelled']} retracted via pl_flit_cancel after the overflow")
