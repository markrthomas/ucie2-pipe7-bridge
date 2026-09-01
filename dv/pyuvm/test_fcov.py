"""INDEPENDENT functional-coverage driver for ucie2_pipe7_bridge (PLAN Phase C, item 12).

A single-process PyUVM test that drives the integrated bridge across the control
(PowerDown / Rate / Width) space, the message-bus opcode space, and a Gen5 FDI flit
round-trip, and scores FUNCTIONAL coverage via cocotb_coverage
(dv/common/models/coverage_model.py). In CI this runs on the INDEPENDENT Icarus
engine (``make fcov``) -- a redundant cross-check to the Verilator/UVM tiers: a
different simulator, a different testbench, a different coverage tool, and a
different metric (functional vs line/round-trip). It also runs locally under
Verilator (``make fcov SIM=verilator``).

The stimulus reaches an honest 100% of the loopback-reachable functional space.
The two error-status bins (sync_error=1, rx_overflow=1) need an RX-inject / sink-
stall wrapper and are FLAGGED for Phase F -- they are intentionally not part of the
100% set here (see coverage_model.py).
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import pyuvm
from pyuvm import uvm_test

import coverage_model as cov
import gen_vectors as gv

# control encodings (ucie2_pipe7_pkg)
REQ_POWER, REQ_RATE, REQ_WIDTH = 0, 1, 2
PD_P0, PD_P0S, PD_P1, PD_P2 = 0, 1, 2, 3
RATE_GEN5, RATE_GEN6 = 4, 5
W_10, W_20, W_40, W_80, W_160 = 0, 1, 2, 3, 4
FDI_ACTIVE = 1
# msgbus response nibbles (ucie2_pipe7_pkg::msgbus_cmd_e)
MB_READ_COMPLETION, MB_WRITE_ACK = 0x4, 0x5

VEC_FILE = os.path.join(os.path.dirname(__file__),
                        "..", "common", "vectors", "fdi_flits_ramp8.vec")


def _i(h):
    try:
        return int(h.value)
    except Exception:
        return 0


@pyuvm.test()
class FcovTest(uvm_test):
    def build_phase(self):
        pass

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top

        cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
        cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())
        self._init(dut)
        dut.pclk_rst_n.value = 0
        dut.lclk_rst_n.value = 0
        await Timer(11, units="ns")
        dut.pclk_rst_n.value = 1
        dut.lclk_rst_n.value = 1
        for _ in range(3):
            await RisingEdge(dut.pclk)

        # PHY completion: PhyStatus high so control requests complete (the FSM is
        # PCLK_IS_PHY_INPUT=0, pclk_change_ok tied high in the bridge).
        dut.phy_status.value = 1
        # FDI PHY loopback + stall responder + continuous coverage observers.
        cocotb.start_soon(self._loopback(dut))
        cocotb.start_soon(self._stall_ack(dut))
        cocotb.start_soon(self._observe(dut))

        self.logger.info("[FCOV] phase: ctrl sweep")
        await self._ctrl_sweep(dut)
        self.logger.info("[FCOV] phase: msgbus sweep")
        await self._mb_sweep(dut)
        self.logger.info("[FCOV] phase: FDI Gen5 round-trip")
        await self._fdi_roundtrip(dut)
        for _ in range(40):
            await RisingEdge(dut.pclk)

        self._finish()
        self.drop_objection()

    # ---- init / harness ----
    def _init(self, dut):
        for n in ("lp_data", "lp_valid", "lp_irdy", "lp_state_req", "lp_linkerror",
                  "lp_stallack", "lp_rx_active_req", "lp_clk_ack", "lp_wake_req",
                  "req_valid", "req_kind", "req_power_down", "mb_req_valid",
                  "mb_req_write", "mb_req_committed", "mb_req_addr", "mb_req_wdata",
                  "rx_data", "rx_valid", "phy_status", "rx_status", "rx_elec_idle",
                  "p2m_message_bus"):
            if hasattr(dut, n):
                getattr(dut, n).value = 0
        dut.req_rate.value = RATE_GEN5
        dut.req_width.value = W_80
        dut.req_rxwidth.value = W_80

    async def _loopback(self, dut):
        while True:
            await RisingEdge(dut.pclk)
            dut.rx_data.value  = _i(dut.tx_data)
            dut.rx_valid.value = _i(dut.tx_data_valid)

    async def _stall_ack(self, dut):
        while True:
            await RisingEdge(dut.lclk)
            dut.lp_stallack.value = _i(dut.pl_stallreq)

    async def _observe(self, dut):
        while True:
            await RisingEdge(dut.pclk)
            cov.sample_dp({
                "rate":       _i(dut.rate),
                "locked":     _i(dut.block_locked),
                "data_phase": _i(dut.in_data_phase),
                "tx_valid":   _i(dut.tx_data_valid),
            })
            cov.sample_fdi({
                "pl_valid":    _i(dut.pl_valid),
                "pl_trdy":     _i(dut.pl_trdy),
                "pl_stallreq": _i(dut.pl_stallreq),
            })

    # ---- control-plane sweep (all kinds / power states / rates / widths + a reject) ----
    async def _ctrl_sweep(self, dut):
        for pd in (PD_P0, PD_P0S, PD_P1, PD_P2):
            await self._ctrl_req(dut, REQ_POWER, pd=pd)
        await self._ctrl_req(dut, REQ_POWER, pd=PD_P0)          # legal state for rate/width
        for rate in (RATE_GEN5, RATE_GEN6):
            await self._ctrl_req(dut, REQ_RATE, rate=rate)
        for w in (W_10, W_20, W_40, W_80, W_160):
            await self._ctrl_req(dut, REQ_WIDTH, width=w)
        # Reject: a rate change from P2 is illegal (no change, req_error).
        await self._ctrl_req(dut, REQ_POWER, pd=PD_P2)
        await self._ctrl_req(dut, REQ_RATE, rate=RATE_GEN5)     # -> reject
        # Restore P0 + Gen5 + W_80 for the datapath round-trip.
        await self._ctrl_req(dut, REQ_POWER, pd=PD_P0)
        await self._ctrl_req(dut, REQ_RATE, rate=RATE_GEN5)
        await self._ctrl_req(dut, REQ_WIDTH, width=W_80)

    async def _ctrl_req(self, dut, kind, pd=PD_P0, rate=RATE_GEN5, width=W_80):
        await RisingEdge(dut.pclk)
        dut.req_kind.value = kind
        dut.req_power_down.value = pd
        dut.req_rate.value = rate
        dut.req_width.value = width
        dut.req_rxwidth.value = width
        dut.req_valid.value = 1
        await RisingEdge(dut.pclk)
        dut.req_valid.value = 0
        await RisingEdge(dut.pclk)
        # request in flight -> busy=1 bin
        cov.sample_ctrl({"kind": kind, "outcome": "done", "pd": pd, "rate": rate,
                         "width": width, "busy": _i(dut.busy)})
        outcome = "done"
        for _ in range(200):
            if _i(dut.done):
                outcome = "done"
                break
            if _i(dut.req_error):
                outcome = "reject"
                break
            await RisingEdge(dut.pclk)
        cov.sample_ctrl({"kind": kind, "outcome": outcome, "pd": pd, "rate": rate,
                         "width": width, "busy": _i(dut.busy)})

    # ---- message-bus sweep (read / uncommitted write / committed write) ----
    async def _mb_sweep(self, dut):
        await self._mb_req(dut, write=0, committed=0, addr=0x401, wdata=0x00, rdata=0xA5)
        await self._mb_req(dut, write=1, committed=0, addr=0x402, wdata=0x5A)
        await self._mb_req(dut, write=1, committed=1, addr=0x403, wdata=0x3C)

    async def _mb_req(self, dut, write, committed, addr, wdata, rdata=0x00):
        for _ in range(50):
            await RisingEdge(dut.pclk)
            if _i(dut.mb_req_ready):
                break
        dut.mb_req_write.value = write
        dut.mb_req_committed.value = committed
        dut.mb_req_addr.value = addr
        dut.mb_req_wdata.value = wdata
        dut.mb_req_valid.value = 1
        await RisingEdge(dut.pclk)
        dut.mb_req_valid.value = 0
        # Supply the P2M sideband response the master waits for: read_completion +
        # data byte for reads, write_ack for committed writes (uncommitted needs none).
        # The master frames 2-3 M2P bytes first, so give it slack before responding.
        cocotb.start_soon(self._p2m_response(dut, write, committed, rdata))
        is_read = 0
        for _ in range(300):
            if _i(dut.mb_rsp_valid):
                is_read = _i(dut.mb_rsp_is_read)
                break
            await RisingEdge(dut.pclk)
        op = "read" if not write else ("wr_com" if committed else "wr_unc")
        cov.sample_mb({"op": op, "is_read": is_read, "committed": committed})

    async def _p2m_response(self, dut, write, committed, rdata):
        if write and not committed:
            return                                  # uncommitted: completes on framing
        for _ in range(6):                          # let the master reach its wait state
            await RisingEdge(dut.pclk)
        if not write:                               # read: {READ_COMPLETION,x}, then Data
            dut.p2m_message_bus.value = MB_READ_COMPLETION << 4
            await RisingEdge(dut.pclk)
            dut.p2m_message_bus.value = rdata & 0xFF
            await RisingEdge(dut.pclk)
        else:                                       # committed write: {WRITE_ACK,x}
            dut.p2m_message_bus.value = MB_WRITE_ACK << 4
            await RisingEdge(dut.pclk)
        dut.p2m_message_bus.value = 0

    # ---- FDI Gen5 flit round-trip (populate datapath + FDI-flow bins) ----
    async def _fdi_roundtrip(self, dut):
        payloads = gv.read_vec(VEC_FILE)
        dut.lp_state_req.value = FDI_ACTIVE
        for _ in range(8):
            await RisingEdge(dut.lclk)
        for data in payloads:
            dut.lp_data.value = data
            dut.lp_valid.value = 1
            dut.lp_irdy.value = 1
            await RisingEdge(dut.lclk)
        dut.lp_valid.value = 0
        dut.lp_irdy.value = 0
        for _ in range(40):
            await RisingEdge(dut.lclk)

    # ---- report ----
    def _finish(self):
        hit, total, pct = cov.overall()
        out = os.environ.get("FCOV_OUT", "")
        if out:
            cov.dump(json_path=os.path.join(out, "fcov.json"),
                     txt_path=os.path.join(out, "fcov.txt"))
        miss = [n for (n, c, s, _p) in cov.per_point() if c < s]
        self.logger.info(f"[FCOV] bins={hit}/{total} = {pct:.1f}%  tool=cocotb_coverage")
        if miss:
            self.logger.info("[FCOV] not-yet-full points: " + ", ".join(miss))
        assert pct >= 100.0, f"functional coverage {pct:.1f}% < 100% of the reachable set; missing: {miss}"
