"""Phase-A smoke for the UCIe2->PIPE7 bridge shell (PLAN Item 11 seed).

Drives the FDI-side and PIPE-side clocks + resets, runs a handful of cycles, and
writes the canonical per-cycle trace (build/bridge.trace) using the shared
trace_format contract. This establishes the flow and the trace format that the
cycle-accurate cross-check (trace_compare.py) depends on; the full PyUVM env
(agents + scoreboard) replaces the body of this test in Item 11.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import trace_format as tf

N_CYCLES = 64
PIPE_WIDTH = 80


def _i(handle):
    """Read a signal as int, tolerating x/z during reset."""
    try:
        return int(handle.value)
    except Exception:
        return 0


@cocotb.test()
async def smoke(dut):
    # PIPE PCLK and FDI lclk (independent clocks — the real DUT has a CDC).
    cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
    cocotb.start_soon(Clock(dut.lclk, 3, units="ns").start())

    # Assert both async resets, then release.
    dut.pclk_rst_n.value = 0
    dut.lclk_rst_n.value = 0
    # Tie inputs to a defined idle so the bridge simulates deterministically.
    for name in ("lp_data", "lp_valid", "lp_irdy", "lp_state_req",
                 "lp_linkerror", "lp_stallack", "lp_rx_active_req", "lp_clk_ack",
                 "lp_wake_req", "req_valid", "req_kind", "req_power_down",
                 "req_rate", "req_width", "req_rxwidth", "mb_req_valid",
                 "mb_req_write", "mb_req_committed", "mb_req_addr", "mb_req_wdata",
                 "rx_data", "rx_valid", "phy_status", "rx_status",
                 "rx_elec_idle", "p2m_message_bus"):
        if hasattr(dut, name):
            getattr(dut, name).value = 0
    await Timer(10, units="ns")
    dut.pclk_rst_n.value = 1
    dut.lclk_rst_n.value = 1

    os.makedirs("build", exist_ok=True)
    with open("build/bridge.trace", "w") as f:
        f.write(tf.TRACE_HEADER + "\n")
        for cyc in range(N_CYCLES):
            await RisingEdge(dut.pclk)
            row = {
                "pl_state_sts":   _i(dut.pl_state_sts),
                "pl_valid":       _i(dut.pl_valid),
                "pl_trdy":        _i(dut.pl_trdy),
                "pl_stallreq":    _i(dut.pl_stallreq),
                "pl_flit_cancel": _i(dut.pl_flit_cancel),
                "tx_data_valid":  _i(dut.tx_data_valid),
                "tx_data":        _i(dut.tx_data),
                "rate":           _i(dut.rate),
                "power_down":     _i(dut.power_down),
            }
            f.write(tf.format_row(cyc, row, PIPE_WIDTH) + "\n")

    dut._log.info("smoke: wrote %d-cycle trace to build/bridge.trace" % N_CYCLES)
