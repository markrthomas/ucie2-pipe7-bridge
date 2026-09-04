"""Full-duplex B2B "external UCIe" test (PLAN H3).

TOPLEVEL = dv/harness/b2b_ucie_pcie_ucie_fd.sv. Both directions run at once over
the joined PIPE link:
  forward : a_lp (FDI into A) -> A.tx -> B.rx -> b_pl (FDI out of B)
  reverse : b_lp (FDI into B) -> B.tx -> A.rx -> a_pl (FDI out of A)
Both ends drive the shared vector and both recovered streams must equal it, with
both bridges reaching lock and no sync_error. Scoreboard-only (no trace gate).
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
import pyuvm
from pyuvm import uvm_test

import gen_vectors as gv
from agents.fdi_agent import _i

FDI_ACTIVE   = 1
BRINGUP_LCLK = 8
RUN_PCLK = int(os.environ.get("RUN_PCLK", "200"))
VEC_FILE = os.environ.get("VEC") or os.path.join(
    os.path.dirname(__file__), "..", "common", "vectors", "fdi_flits_ramp8.vec")


@pyuvm.test()
class B2bUcieFdTest(uvm_test):
    def build_phase(self):
        self.payloads = gv.read_vec(VEC_FILE)

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top
        cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
        cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

        for n in ("a_lp_data", "a_lp_valid", "a_lp_irdy", "a_lp_state_req", "a_lp_stallack",
                  "b_lp_data", "b_lp_valid", "b_lp_irdy", "b_lp_state_req", "b_lp_stallack"):
            getattr(dut, n).value = 0
        dut.pclk_rst_n.value = 0
        dut.lclk_rst_n.value = 0
        await Timer(11, units="ns")
        dut.pclk_rst_n.value = 1
        dut.lclk_rst_n.value = 1

        fwd, rev = [], []
        cocotb.start_soon(self._stall(dut, "a"))
        cocotb.start_soon(self._stall(dut, "b"))
        cocotb.start_soon(self._mon(dut, "b", fwd))   # forward recovers at B
        cocotb.start_soon(self._mon(dut, "a", rev))   # reverse recovers at A
        cocotb.start_soon(self._drive(dut, "a"))      # forward drives into A
        cocotb.start_soon(self._drive(dut, "b"))      # reverse drives into B

        for _ in range(RUN_PCLK):
            await RisingEdge(dut.pclk)
        self.drop_objection()
        self._check(fwd, rev)

    async def _drive(self, dut, p):
        getattr(dut, f"{p}_lp_state_req").value = FDI_ACTIVE
        for _ in range(BRINGUP_LCLK):
            await RisingEdge(dut.lclk)
        for data in self.payloads:
            getattr(dut, f"{p}_lp_data").value  = data
            getattr(dut, f"{p}_lp_valid").value = 1
            getattr(dut, f"{p}_lp_irdy").value  = 1
            while True:
                await RisingEdge(dut.lclk)
                if _i(getattr(dut, f"{p}_pl_trdy")):
                    break
        getattr(dut, f"{p}_lp_valid").value = 0
        getattr(dut, f"{p}_lp_irdy").value  = 0

    async def _stall(self, dut, p):
        while True:
            await RisingEdge(dut.lclk)
            getattr(dut, f"{p}_lp_stallack").value = _i(getattr(dut, f"{p}_pl_stallreq"))

    async def _mon(self, dut, p, out):
        while True:
            await RisingEdge(dut.lclk)
            if _i(getattr(dut, f"{p}_pl_valid")):
                out.append(_i(getattr(dut, f"{p}_pl_data")))

    def _check(self, fwd, rev):
        driven = self.payloads
        n = len(driven)
        dut = cocotb.top
        errors = []
        for name, rec in (("forward A->B", fwd), ("reverse B->A", rev)):
            if rec[:n] != driven:
                k = min(len(rec), n)
                first = next((i for i in range(k) if rec[i] != driven[i]), k)
                errors.append(f"{name} mismatch: {len(rec)} recovered vs {n} driven; "
                              f"first diff at flit #{first}")
        if _i(dut.a_sync_error) or _i(dut.b_sync_error):
            errors.append("a bridge raised sync_error")
        self.logger.info(f"[B2B-UCIe-FD] driven={n} fwd={len(fwd)} rev={len(rev)}")
        assert not errors, "B2B UCIe full-duplex check failed:\n  " + "\n  ".join(errors)
