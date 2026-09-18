"""Directed management/sideband register-access test (Phase I item I4).

Exercises the UCIe-2.0 management/sideband transport (ucie2_mgmt_sideband) that
the bridge routes controller register-access requests to by address. The shared
mb_req_* port carries the request; addresses in the management window
(REG_MGMT_BASE .. +MGMT_SPACE_SPAN) are serialised into a sideband packet,
completed against the management register file, and answered on mb_rsp_*. This is
a CONTROL-PLANE test only — it drives no flits and writes no build/bridge.trace,
so it is completely independent of the sacred byte-identical round-trip. Runs in
the PyUVM tier (`make mgmt`) and CI.

Checks:
  1. write-then-read to each backing management register (0x010..0x017) returns
     exactly what was written, with rsp_error == 0 (status OK);
  2. a read to an in-space-but-unbacked address (0x018) returns rsp_error == 1
     (the completer reports a status-ERR completion — address hit no register);
  3. REGRESSION: a PHY-space access (0x401) still routes to the PIPE 7.1 message
     bus (answered by a P2M responder), proving the address demux left the
     existing MAC<->PHY config plane untouched.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Management register space (ucie2_pipe7_pkg.sv §F, Phase I I4).
REG_MGMT_BASE = 0x010
NUM_MGMT_REGS = 8            # 0x010..0x017 are backed by a register
MGMT_SPACE_SPAN = 16         # 0x010..0x01F route to the sideband transport
# PIPE 7.1 msgbus response nibbles (msgbus_cmd_e) for the PHY-space regression.
MB_READ_COMPLETION = 0x4
TIMEOUT = 120                # pclk cycles for a management completion


def _i(handle):
    try:
        return int(handle.value)
    except Exception:
        return 0


async def _mgmt(dut, write, addr, wdata=0x00):
    """Issue one management register access on mb_req_*; return (rdata, error)."""
    for _ in range(50):
        await RisingEdge(dut.pclk)
        if _i(dut.mb_req_ready):
            break
    dut.mb_req_write.value = write
    dut.mb_req_committed.value = 0
    dut.mb_req_addr.value = addr
    dut.mb_req_wdata.value = wdata
    dut.mb_req_valid.value = 1
    await RisingEdge(dut.pclk)
    dut.mb_req_valid.value = 0
    for _ in range(TIMEOUT):
        if _i(dut.mb_rsp_valid):
            return _i(dut.mb_rsp_rdata), _i(dut.mb_rsp_error)
        await RisingEdge(dut.pclk)
    raise AssertionError(f"management access to 0x{addr:03x} never completed")


async def _phy_read(dut, addr, rdata):
    """Issue a PHY-space msgbus read; drive the P2M completion; return rdata seen."""
    for _ in range(50):
        await RisingEdge(dut.pclk)
        if _i(dut.mb_req_ready):
            break
    dut.mb_req_write.value = 0
    dut.mb_req_committed.value = 0
    dut.mb_req_addr.value = addr
    dut.mb_req_wdata.value = 0
    dut.mb_req_valid.value = 1
    await RisingEdge(dut.pclk)
    dut.mb_req_valid.value = 0
    cocotb.start_soon(_p2m_read_response(dut, rdata))
    for _ in range(TIMEOUT):
        if _i(dut.mb_rsp_valid):
            return _i(dut.mb_rsp_rdata)
        await RisingEdge(dut.pclk)
    raise AssertionError(f"PHY-space read of 0x{addr:03x} never completed")


async def _p2m_read_response(dut, rdata):
    for _ in range(6):                       # let the master frame M2P + reach its wait
        await RisingEdge(dut.pclk)
    dut.p2m_message_bus.value = MB_READ_COMPLETION << 4
    await RisingEdge(dut.pclk)
    dut.p2m_message_bus.value = rdata & 0xFF
    await RisingEdge(dut.pclk)
    dut.p2m_message_bus.value = 0


@cocotb.test()
async def mgmt_sideband(dut):
    cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
    cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

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
    await Timer(11, units="ns")
    dut.pclk_rst_n.value = 1
    dut.lclk_rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.pclk)

    # 1) Write then read each backing management register; expect exact readback, OK.
    patterns = [(REG_MGMT_BASE + i, (0xA0 + i) & 0xFF) for i in range(NUM_MGMT_REGS)]
    for addr, data in patterns:
        _, werr = await _mgmt(dut, write=1, addr=addr, wdata=data)
        assert werr == 0, f"write 0x{addr:03x} reported error"
    for addr, data in patterns:
        rdata, rerr = await _mgmt(dut, write=0, addr=addr)
        assert rerr == 0, f"read 0x{addr:03x} reported error"
        assert rdata == data, \
            f"mgmt reg 0x{addr:03x}: read 0x{rdata:02x}, expected 0x{data:02x}"
    dut._log.info(f"[mgmt] {NUM_MGMT_REGS} registers write/read-back verified (0x{REG_MGMT_BASE:03x}..)")

    # Re-read the first register to confirm the later writes did not disturb it.
    rdata, rerr = await _mgmt(dut, write=0, addr=REG_MGMT_BASE)
    assert rerr == 0 and rdata == patterns[0][1], "first mgmt reg corrupted by later writes"

    # 2) Error path: an in-space address with no backing register -> status ERR.
    unbacked = REG_MGMT_BASE + NUM_MGMT_REGS          # 0x018, still within the decode span
    assert unbacked < REG_MGMT_BASE + MGMT_SPACE_SPAN
    _, rerr = await _mgmt(dut, write=0, addr=unbacked)
    assert rerr == 1, f"read 0x{unbacked:03x} (unbacked) should report a status error"
    dut._log.info(f"[mgmt] unbacked address 0x{unbacked:03x} correctly returned a status error")

    # 3) Regression: a PHY-space access still uses the PIPE 7.1 message bus.
    seen = await _phy_read(dut, addr=0x401, rdata=0xA5)
    assert seen == 0xA5, f"PHY-space msgbus read returned 0x{seen:02x}, expected 0xA5"
    dut._log.info("[mgmt] PHY-space read still routed to the PIPE msgbus (demux intact)")

    dut._log.info("[mgmt] PASS: UCIe-2.0 management/sideband register access verified")
