"""PyUVM FDI-side agent + PIPE monitor for the integrated-bridge cross-check
(PLAN Phase C, item 11).

Mirrors the SV/UVM taxonomy (sequence_item / driver / monitor / sequencer / agent)
so the two envs share test intent 1:1 and the cycle-accurate cross-check
(tools/trace_compare.py) stays meaningful. The active agent drives 128-bit FDI
flits into ``ucie2_pipe7_bridge`` (cocotb.top) on the FDI TX port and monitors the
recovered flits on the FDI RX port; a separate PIPE monitor captures the raw PIPE
TxData word stream and the deframer health signals.

Timing is a FIXED, driver-led cycle schedule anchored to reset deassert (both clock
domains share one 2 ns period, so the whole bridge is synchronous), identical to
the SV UVM TB's stimulus -- this is what keeps the two traces in cycle lockstep.
Because the schedule is driven entirely by the driver's own edge waits (not by when
the sequence coroutine happens to be scheduled), it reproduces the B4 directed
``stimulus()`` cycle-for-cycle. Registered/observed signals are read right after the
clock edge, where cocotb returns settled (post-edge) values -- the cocotb-side
equivalent of the SV emitter's ``#0.1`` post-edge sampling.
"""
import cocotb
from cocotb.triggers import RisingEdge
from pyuvm import (uvm_sequence_item, uvm_driver, uvm_monitor, uvm_agent,
                   uvm_sequencer, uvm_analysis_port, ConfigDB)

FDI_ACTIVE   = 1     # ucie2_pipe7_pkg::FDI_ACTIVE
BRINGUP_LCLK = 8     # fixed cycles to let the link reach ACTIVE (matches SV TB)


def _i(handle):
    """Settled int read of a DUT handle (X/Z -> 0), matching the SV #0.1 reads."""
    try:
        return int(handle.value)
    except Exception:
        return 0


class FdiFlit(uvm_sequence_item):
    """One 128-bit FDI transfer (a data block; is_os is FLAGGED -> always data)."""
    def __init__(self, name="FdiFlit", data=0, is_os=False):
        super().__init__(name)
        self.data = data
        self.is_os = is_os

    def __str__(self):
        return f"FdiFlit(data=0x{self.data:032x}, is_os={int(self.is_os)})"


class FdiDriver(uvm_driver):
    """Drives flits into the FDI TX port on the fixed schedule the SV TB mirrors:
    at reset deassert request FDI_ACTIVE, wait BRINGUP_LCLK lclk cycles for the link
    to come up, then drive one flit per lclk cycle back-to-back and idle. Publishes
    each driven flit as the 'expected' stream for the scoreboard. The flit count is
    taken from config (N_FLITS) so the deassert lands on the exact cycle the SV TB
    uses."""
    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)

    async def run_phase(self):
        dut = cocotb.top
        start_ev = ConfigDB().get(self, "", "START_EV")
        n_flits  = ConfigDB().get(self, "", "N_FLITS")
        await start_ev.wait()                 # resumes at reset-deassert time (no edge consumed)

        dut.lp_state_req.value = FDI_ACTIVE
        for _ in range(BRINGUP_LCLK):
            await RisingEdge(dut.lclk)

        for _ in range(n_flits):
            flit = await self.seq_item_port.get_next_item()   # driver-led: returns in-delta
            dut.lp_data.value  = flit.data
            dut.lp_valid.value = 1
            dut.lp_irdy.value  = 1
            # FDI flow control: a flit transfers only when lp_valid & lp_irdy &
            # pl_trdy (blk_ready & link_active). Hold it until pl_trdy is high so a
            # burst longer than the internal FIFO never drops flits. For short
            # bursts pl_trdy is always high, so the schedule is unchanged.
            while True:
                await RisingEdge(dut.lclk)
                if _i(dut.pl_trdy):
                    break
            self.ap.write((flit.data, bool(flit.is_os)))
            self.seq_item_port.item_done()

        dut.lp_valid.value = 0
        dut.lp_irdy.value  = 0


class FdiRxMonitor(uvm_monitor):
    """Samples the recovered FDI flits on the RX port (post-edge on lclk) and
    publishes each recovered payload for the round-trip check."""
    def build_phase(self):
        self.ap = uvm_analysis_port("ap", self)

    async def run_phase(self):
        dut = cocotb.top
        while True:
            await RisingEdge(dut.lclk)
            if _i(dut.pl_valid):
                self.ap.write(_i(dut.pl_data))


class PipeTxMonitor(uvm_monitor):
    """PIPE-side monitor: captures each valid PIPE TxData word (post-edge on pclk)
    for the framer cross-check and tracks deframer health (sync_error / block_locked)."""
    def build_phase(self):
        self.stream_ap = uvm_analysis_port("stream_ap", self)
        self.sync_errors = 0
        self.saw_lock = False

    async def run_phase(self):
        dut = cocotb.top
        while True:
            await RisingEdge(dut.pclk)
            if _i(dut.tx_data_valid):
                self.stream_ap.write(_i(dut.tx_data))
            if _i(dut.sync_error):
                self.sync_errors += 1
            if _i(dut.block_locked):
                self.saw_lock = True


class FdiAgent(uvm_agent):
    def build_phase(self):
        self.seqr    = uvm_sequencer("seqr", self)
        self.driver  = FdiDriver("driver", self)
        self.rx_mon  = FdiRxMonitor("rx_mon", self)
        ConfigDB().set(None, "*", "FDI_SEQR", self.seqr)

    def connect_phase(self):
        self.driver.seq_item_port.connect(self.seqr.seq_item_export)
