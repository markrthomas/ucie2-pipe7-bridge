"""B2B config (reverse): UCIe -> [bridge A] -> PCIe == PCIe -> [bridge B] -> UCIe.

TOPLEVEL = dv/harness/b2b_ucie_pcie_ucie.sv (two ucie2_pipe7_bridge joined at
their PIPE ports). A UCIe/FDI flit driven into bridge A is framed, crosses a real
PIPE link (A.tx_data -> B.rx_data), and is recovered by bridge B as a UCIe/FDI
flit -- the middle self-loopback of the single-bridge round-trip is replaced by a
second bridge. UNIDIRECTIONAL (A->B).

PyUVM scoreboard cross-check (no two-TB byte-identical trace gate yet -- that is
added when the SV UVM B2B tier lands):
  1. round-trip identity : flits recovered out of B == flits driven into A, in order.
  2. framing-model check : the middle PIPE word stream == the independent Python
                           framer of the driven flits (dv/common/models).
  3. deframer health     : bridge B reaches block lock and never raises sync_error.

Shares the FDI driver schedule with the single-bridge test (request FDI_ACTIVE,
wait BRINGUP_LCLK, then one flit/lclk honoring a_pl_trdy backpressure) and the
shared stimulus vector (VEC env) so LEN/SEED/PROFILE knobs apply unchanged.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import pyuvm
from pyuvm import uvm_test

import framing_model as fm
import gen_vectors as gv
from agents.fdi_agent import _i

PIPE_WIDTH   = 80    # ucie2_pipe7_bridge PW default (PIPE_WIDTH_DEFAULT)
FDI_ACTIVE   = 1     # ucie2_pipe7_pkg::FDI_ACTIVE
BRINGUP_LCLK = 8     # cycles to let the FDI link reach ACTIVE (matches single-bridge)
RUN_PCLK = int(os.environ.get("RUN_PCLK", "200"))
VEC_FILE = os.environ.get("VEC") or os.path.join(
    os.path.dirname(__file__), "..", "common", "vectors", "fdi_flits_ramp8.vec")


@pyuvm.test()
class B2bUcieTest(uvm_test):
    def build_phase(self):
        self.payloads = gv.read_vec(VEC_FILE)

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top

        # One period on both domains -> synchronous, deterministic (as single-bridge).
        cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
        cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

        self._init_inputs(dut)
        dut.pclk_rst_n.value = 0
        dut.lclk_rst_n.value = 0
        await Timer(11, units="ns")
        dut.pclk_rst_n.value = 1
        dut.lclk_rst_n.value = 1

        recovered, mid_words = [], []
        stats = {"sync_errors": 0, "saw_lock": False}
        cocotb.start_soon(self._stall_ack(dut))
        cocotb.start_soon(self._mon_rx(dut, recovered))
        cocotb.start_soon(self._mon_mid(dut, mid_words, stats))
        cocotb.start_soon(self._drive(dut))

        for _ in range(RUN_PCLK):
            await RisingEdge(dut.pclk)

        self.drop_objection()
        self._check(recovered, mid_words, stats)

    # ---- stimulus + responders (timing-critical; kept explicit) --------------
    def _init_inputs(self, dut):
        for n in ("a_lp_data", "a_lp_valid", "a_lp_irdy",
                  "a_lp_state_req", "a_lp_stallack"):
            getattr(dut, n).value = 0

    async def _drive(self, dut):
        """Drive the shared flit vector into bridge A's FDI TX, honoring a_pl_trdy."""
        dut.a_lp_state_req.value = FDI_ACTIVE
        for _ in range(BRINGUP_LCLK):
            await RisingEdge(dut.lclk)
        for data in self.payloads:
            dut.a_lp_data.value  = data
            dut.a_lp_valid.value = 1
            dut.a_lp_irdy.value  = 1
            while True:
                await RisingEdge(dut.lclk)
                if _i(dut.a_pl_trdy):
                    break
        dut.a_lp_valid.value = 0
        dut.a_lp_irdy.value  = 0

    async def _stall_ack(self, dut):
        """Auto-complete bridge A's FDI stall handshake."""
        while True:
            await RisingEdge(dut.lclk)
            dut.a_lp_stallack.value = _i(dut.a_pl_stallreq)

    async def _mon_rx(self, dut, out):
        """Recovered FDI flits out of bridge B (post-edge on lclk)."""
        while True:
            await RisingEdge(dut.lclk)
            if _i(dut.b_pl_valid):
                out.append(_i(dut.b_pl_data))

    async def _mon_mid(self, dut, out, stats):
        """Middle PIPE word stream + bridge B deframer health (post-edge on pclk)."""
        while True:
            await RisingEdge(dut.pclk)
            if _i(dut.mid_tx_data_valid):
                out.append(_i(dut.mid_tx_data))
            if _i(dut.b_sync_error):
                stats["sync_errors"] += 1
            if _i(dut.b_block_locked):
                stats["saw_lock"] = True

    # ---- three-way cross-check -----------------------------------------------
    def _check(self, recovered, mid_words, stats):
        driven = self.payloads
        n = len(driven)
        errors = []

        # 1. round-trip identity: what B recovers == what was driven into A.
        if recovered[:n] != driven:
            k = min(len(recovered), n)
            first = next((i for i in range(k) if recovered[i] != driven[i]), k)
            errors.append(f"round-trip mismatch: {len(recovered)} recovered vs "
                          f"{n} driven; first diff at flit #{first}")

        # 2. middle PIPE stream == independent Python framer of the driven flits.
        model = fm.frame_stream([(d, False) for d in driven], PIPE_WIDTH)
        k = min(len(mid_words), len(model))
        if k == 0:
            errors.append("no middle PIPE words captured")
        elif mid_words[:k] != model[:k]:
            first = next((i for i in range(k) if mid_words[i] != model[i]), k)
            errors.append(f"framer/model mismatch: first diff at word #{first} "
                          f"(link {len(mid_words)} vs model {len(model)} words)")

        # 3. deframer health at bridge B.
        if stats["sync_errors"]:
            errors.append(f"bridge B raised sync_error {stats['sync_errors']} time(s)")
        if not stats["saw_lock"]:
            errors.append("bridge B never reached block lock")
        if n == 0:
            errors.append("no flits driven (empty run)")

        self.logger.info(f"[B2B-UCIe] driven={n} recovered={len(recovered)} "
                         f"link_words={len(mid_words)} model_words={len(model)}")
        assert not errors, \
            "B2B UCIe-PCIe-UCIe cross-check failed:\n  " + "\n  ".join(errors)
