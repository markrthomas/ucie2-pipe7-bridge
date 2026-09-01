"""Directed Gen5 FDI round-trip, PyUVM env edition (PLAN Phase C, item 11).

Drives the shared FDI vector sequence (dv/common/vectors) through the whole bridge
with a PHY loopback and cross-checks it three ways in a real PyUVM env
(env.BridgeEnv + BridgeScoreboard): recovered flits == driven, DUT TxData ==
independent framing model, and independent deframe of the DUT stream == driven.

The stimulus is a FIXED, driver-led cycle schedule (both domains share one 2 ns
period, so the whole bridge is synchronous and deterministic) and this test emits
the canonical per-cycle trace concurrently from reset deassert -- the SV UVM TB
mirrors the same schedule so tools/trace_compare.py holds the two TBs in
cycle-lockstep. The trace generation here is intentionally identical to the proven
B4 loop (read registered/observed signals right after the pclk edge, where cocotb
returns settled post-edge values).
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, Event
import pyuvm
from pyuvm import uvm_test, ConfigDB

import trace_format as tf
import gen_vectors as gv

from env import BridgeEnv
from seq_lib.fdi_seq_lib import FdiFlitSeq
from agents.fdi_agent import _i

PIPE_WIDTH = 80
RUN_PCLK   = 200        # cycles to trace / drain (from reset deassert)
VEC_FILE   = os.path.join(os.path.dirname(__file__),
                          "..", "common", "vectors", "fdi_flits_ramp8.vec")


@pyuvm.test()
class RoundtripTest(uvm_test):
    def build_phase(self):
        self.env = BridgeEnv("env", self)
        # Shared stimulus: load the committed vector file (single source of truth).
        self.payloads = gv.read_vec(VEC_FILE)
        self.start_ev = Event("reset_deassert")
        ConfigDB().set(None, "*", "START_EV", self.start_ev)
        ConfigDB().set(None, "*", "N_FLITS", len(self.payloads))

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top

        # One period on both domains -> synchronous, deterministic across simulators.
        cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
        cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

        self._init_inputs(dut)
        dut.pclk_rst_n.value = 0
        dut.lclk_rst_n.value = 0
        await Timer(11, units="ns")
        dut.pclk_rst_n.value = 1
        dut.lclk_rst_n.value = 1

        # Responders + driver all start at reset deassert (matches the SV TB).
        cocotb.start_soon(self._loopback(dut))
        cocotb.start_soon(self._stall_ack(dut))
        self.start_ev.set()
        seq = FdiFlitSeq("seq", flits=self.payloads)
        cocotb.start_soon(seq.start(self.env.agent.seqr))

        # Canonical per-cycle trace (identical loop to B4; cross-check producer).
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

        self.drop_objection()   # -> check_phase runs the 3-way scoreboard

    # ---- TB harness (PHY + stall responders), timing-critical: kept explicit ----
    def _init_inputs(self, dut):
        for n in ("lp_data", "lp_valid", "lp_irdy", "lp_state_req", "lp_linkerror",
                  "lp_stallack", "lp_rx_active_req", "lp_clk_ack", "lp_wake_req",
                  "req_valid", "req_kind", "req_power_down", "req_rate", "req_width",
                  "req_rxwidth", "mb_req_valid", "mb_req_write", "mb_req_committed",
                  "mb_req_addr", "mb_req_wdata", "rx_data", "rx_valid", "phy_status",
                  "rx_status", "rx_elec_idle", "p2m_message_bus"):
            if hasattr(dut, n):
                getattr(dut, n).value = 0

    async def _loopback(self, dut):
        """PHY loopback: rx follows tx by one pclk."""
        while True:
            await RisingEdge(dut.pclk)
            dut.rx_data.value  = _i(dut.tx_data)
            dut.rx_valid.value = _i(dut.tx_data_valid)

    async def _stall_ack(self, dut):
        """Auto-complete the FDI stall handshake."""
        while True:
            await RisingEdge(dut.lclk)
            dut.lp_stallack.value = _i(dut.pl_stallreq)
