"""Directed is_os round-trip test (Phase I item I2).

Drives a mix of ordered-set and data FDI flits through the bridge (PHY
self-loopback) and checks that BOTH the payload and the recovered flit-type
(pl_is_os) come back correct per flit. This exercises the is_os path the default
round-trip does not: lp_is_os -> framer OS/data sync header -> deframer recovery ->
pl_is_os. It is a directed data-plane test (its own top-level test module); it
writes no build/bridge.trace, so it does not touch the sacred cross-check.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

BRINGUP_LCLK = 8
FDI_ACTIVE   = 1
N_FLITS      = 8
DRAIN_PCLK   = 200   # generous drain for all flits to loop back and recover


def _i(handle):
    try:
        return int(handle.value)
    except Exception:
        return 0


async def _loopback(dut):
    """PHY self-loopback: rx follows tx by one pclk (same as the round-trip TB)."""
    while True:
        await RisingEdge(dut.pclk)
        dut.rx_data.value  = _i(dut.tx_data)
        dut.rx_valid.value = _i(dut.tx_data_valid)


async def _stall_responder(dut):
    while True:
        await RisingEdge(dut.lclk)
        dut.lp_stallack.value = _i(dut.pl_stallreq)


async def _rx_monitor(dut, recovered):
    """Capture (pl_data, pl_is_os) on every valid FDI RX beat."""
    while True:
        await RisingEdge(dut.lclk)
        if _i(dut.pl_valid):
            recovered.append((_i(dut.pl_data), _i(dut.pl_is_os)))


@cocotb.test()
async def is_os_roundtrip(dut):
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

    # Bring the link up.
    dut.lp_state_req.value = FDI_ACTIVE
    for _ in range(BRINGUP_LCLK):
        await RisingEdge(dut.lclk)

    # Drive N flits with alternating flit-type: even = data, odd = ordered-set.
    driven = []
    for i in range(N_FLITS):
        data  = (0xA5A5_0000_0000_0000_0000_0000_0000_0000 | i)
        is_os = i & 1
        dut.lp_data.value  = data
        dut.lp_valid.value = 1
        dut.lp_irdy.value  = 1
        dut.lp_is_os.value = is_os
        while True:
            await RisingEdge(dut.lclk)
            if _i(dut.pl_trdy):
                break
        driven.append((data, is_os))
    dut.lp_valid.value = 0
    dut.lp_irdy.value  = 0
    dut.lp_is_os.value = 0

    for _ in range(DRAIN_PCLK):
        await RisingEdge(dut.pclk)

    # Scoreboard: same count, same payload, same recovered flit-type per flit.
    assert len(recovered) == len(driven), \
        f"recovered {len(recovered)} flits, expected {len(driven)}"
    n_os = 0
    for idx, (exp, got) in enumerate(zip(driven, recovered)):
        assert got[0] == exp[0], \
            f"flit #{idx} data mismatch: got {got[0]:#034x} exp {exp[0]:#034x}"
        assert got[1] == exp[1], \
            f"flit #{idx} is_os mismatch: got {got[1]} exp {exp[1]}"
        n_os += got[1]
    assert n_os > 0, "test drove no ordered-set flits — is_os path not exercised"
    dut._log.info(f"[is_os] PASS: {len(driven)} flits round-tripped, "
                  f"{n_os} ordered-set + {len(driven) - n_os} data, is_os exact")
