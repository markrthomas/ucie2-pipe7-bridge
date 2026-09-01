"""Directed Gen5 FDI round-trip — proves data flows through the whole bridge.

PLAN B4. Brings the FDI link to ACTIVE, drives N flits into the FDI TX port with a
PHY loopback (rx_data<-tx_data), and independently checks:
  1. TX framing: the DUT's TxData word stream == framing_model.frame_stream of the
     driven payloads (bit-exact, independent Python model of 128b/130b).
  2. Round-trip: the recovered FDI pl_data == the driven flits, in order.
  3. block_locked reached and no sync_error.

Stimulus is a FIXED cycle schedule (both domains share one 2 ns period, so the
whole bridge is synchronous and deterministic) — no handshake-dependent waits —
so the SV UVM TB can mirror it exactly and trace_compare holds the two TBs in
cycle-lockstep. The per-cycle trace is emitted concurrently from reset deassert.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import trace_format as tf
import framing_model as fm

PIPE_WIDTH  = 80
FDI_ACTIVE  = 1          # ucie2_pipe7_pkg::FDI_ACTIVE
N_FLITS     = 8
BRINGUP_LCLK = 8         # fixed cycles to let the link reach ACTIVE
RUN_PCLK    = 200        # cycles to trace / drain (from reset deassert)


def _i(h):
    try:
        return int(h.value)
    except Exception:
        return 0


@cocotb.test()
async def roundtrip(dut):
    # One period on both domains -> synchronous, deterministic across simulators.
    cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
    cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

    for n in ("lp_data", "lp_valid", "lp_irdy", "lp_state_req", "lp_linkerror",
              "lp_stallack", "lp_rx_active_req", "lp_clk_ack", "lp_wake_req",
              "req_valid", "req_kind", "req_power_down", "req_rate", "req_width",
              "req_rxwidth", "mb_req_valid", "mb_req_write", "mb_req_committed",
              "mb_req_addr", "mb_req_wdata", "rx_data", "rx_valid", "phy_status",
              "rx_status", "rx_elec_idle", "p2m_message_bus"):
        if hasattr(dut, n):
            getattr(dut, n).value = 0
    dut.pclk_rst_n.value = 0
    dut.lclk_rst_n.value = 0
    await Timer(11, units="ns")
    dut.pclk_rst_n.value = 1
    dut.lclk_rst_n.value = 1

    payloads = [((0x1000 + i) << 64) | (0xABCD0000 + i) for i in range(N_FLITS)]
    tx_words, recovered = [], []

    # PHY loopback: rx follows tx by one pclk.
    async def loopback():
        while True:
            await RisingEdge(dut.pclk)
            dut.rx_data.value = _i(dut.tx_data)
            dut.rx_valid.value = _i(dut.tx_data_valid)

    # Auto-complete the FDI stall handshake and capture streams.
    async def stall_ack():
        while True:
            await RisingEdge(dut.lclk)
            dut.lp_stallack.value = _i(dut.pl_stallreq)

    async def cap_tx():
        while True:
            await RisingEdge(dut.pclk)
            if _i(dut.tx_data_valid):
                tx_words.append(_i(dut.tx_data))

    async def cap_rx():
        while True:
            await RisingEdge(dut.lclk)
            if _i(dut.pl_valid):
                recovered.append(_i(dut.pl_data))

    # Fixed-schedule stimulus (anchored to reset deassert).
    async def stimulus():
        dut.lp_state_req.value = FDI_ACTIVE
        for _ in range(BRINGUP_LCLK):
            await RisingEdge(dut.lclk)
        for i in range(N_FLITS):
            dut.lp_data.value = payloads[i]
            dut.lp_valid.value = 1
            dut.lp_irdy.value = 1
            await RisingEdge(dut.lclk)
        dut.lp_valid.value = 0
        dut.lp_irdy.value = 0

    cocotb.start_soon(loopback())
    cocotb.start_soon(stall_ack())
    cocotb.start_soon(cap_tx())
    cocotb.start_soon(cap_rx())
    cocotb.start_soon(stimulus())

    os.makedirs("build", exist_ok=True)
    with open("build/bridge.trace", "w") as f:
        f.write(tf.TRACE_HEADER + "\n")
        for cyc in range(RUN_PCLK):
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

    # ---- Checks -------------------------------------------------------------
    assert _i(dut.sync_error) == 0, "deframer raised sync_error"
    assert _i(dut.block_locked) == 1, "deframer never reached block_locked"

    exp_words = fm.frame_stream([(p, False) for p in payloads], PIPE_WIDTH)
    assert tx_words[:len(exp_words)] == exp_words, (
        f"TxData framing mismatch:\n got {[hex(w) for w in tx_words[:len(exp_words)]]}"
        f"\n exp {[hex(w) for w in exp_words]}")

    assert recovered[:N_FLITS] == payloads, (
        f"round-trip mismatch:\n got {[hex(x) for x in recovered[:N_FLITS]]}"
        f"\n exp {[hex(x) for x in payloads]}")

    dut._log.info("roundtrip: %d flits OK (tx %d words, recovered %d)"
                  % (N_FLITS, len(tx_words), len(recovered)))
