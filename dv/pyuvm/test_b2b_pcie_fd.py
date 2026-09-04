"""Full-duplex B2B "external PCIe" test (PLAN H3).

TOPLEVEL = dv/harness/b2b_pcie_ucie_pcie_fd.sv. Both directions run at once over
the joined FDI seam:
  forward : a_rx (PIPE into A) -> A.pl -> B.lp -> b_tx (PIPE out of B)
  reverse : b_rx (PIPE into B) -> B.pl -> A.lp -> a_tx (PIPE out of A)
Both ends inject the shared pre-framed word stream; each far PIPE output must
equal the injected words (A recovers exactly, the far bridge re-frames exactly),
with both bridges reaching lock and no sync_error. Scoreboard-only.
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

PIPE_WIDTH = 80
RUN_PCLK = int(os.environ.get("RUN_PCLK", "200"))
VEC_FILE = os.environ.get("VEC") or os.path.join(
    os.path.dirname(__file__), "..", "common", "vectors", "fdi_flits_ramp8.vec")
WARMUP = 4


@pyuvm.test()
class B2bPcieFdTest(uvm_test):
    def build_phase(self):
        self.payloads = gv.read_vec(VEC_FILE)
        words_vec = os.environ.get("VEC_WORDS")
        self.words = (gv.read_vec(words_vec) if words_vec
                      else fm.frame_stream([(d, False) for d in self.payloads], PIPE_WIDTH))

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top
        cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
        cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

        for n in ("a_rx_data", "a_rx_valid", "b_rx_data", "b_rx_valid"):
            getattr(dut, n).value = 0
        dut.pclk_rst_n.value = 0
        dut.lclk_rst_n.value = 0
        await Timer(11, units="ns")
        dut.pclk_rst_n.value = 1
        dut.lclk_rst_n.value = 1

        fwd, rev = [], []
        cocotb.start_soon(self._mon(dut, "b", fwd))   # forward out at B
        cocotb.start_soon(self._mon(dut, "a", rev))   # reverse out at A
        cocotb.start_soon(self._drive(dut, "a"))      # forward inject at A
        cocotb.start_soon(self._drive(dut, "b"))      # reverse inject at B

        for _ in range(RUN_PCLK):
            await RisingEdge(dut.pclk)
        self.drop_objection()
        self._check(fwd, rev)

    async def _drive(self, dut, p):
        for _ in range(WARMUP):
            await RisingEdge(dut.pclk)
        for w in self.words:
            getattr(dut, f"{p}_rx_data").value  = w
            getattr(dut, f"{p}_rx_valid").value = 1
            await RisingEdge(dut.pclk)
        getattr(dut, f"{p}_rx_valid").value = 0
        getattr(dut, f"{p}_rx_data").value  = 0

    async def _mon(self, dut, p, out):
        while True:
            await RisingEdge(dut.pclk)
            if _i(getattr(dut, f"{p}_tx_data_valid")):
                out.append(_i(getattr(dut, f"{p}_tx_data")))

    def _check(self, fwd, rev):
        w = self.words
        m = len(w)
        dut = cocotb.top
        errors = []
        for name, out in (("forward A->B", fwd), ("reverse B->A", rev)):
            if out[:m] != w:
                k = min(len(out), m)
                first = next((i for i in range(k) if out[i] != w[i]), k)
                errors.append(f"{name} word mismatch: {len(out)} vs {m} injected; "
                              f"first diff at word #{first}")
        if _i(dut.a_sync_error) or _i(dut.b_sync_error):
            errors.append("a bridge raised sync_error")
        self.logger.info(f"[B2B-PCIe-FD] words={m} fwd={len(fwd)} rev={len(rev)}")
        assert not errors, "B2B PCIe full-duplex check failed:\n  " + "\n  ".join(errors)
