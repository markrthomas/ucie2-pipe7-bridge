"""B2B config (forward): PCIe -> [bridge A] -> UCIe == UCIe -> [bridge B] -> PCIe.

TOPLEVEL = dv/harness/b2b_pcie_ucie_pcie.sv (two ucie2_pipe7_bridge joined at
their FDI ports). A PCIe/PIPE word stream driven into bridge A's PIPE RX is
deframed to a UCIe/FDI flit, crosses a real FDI seam (A.pl_data -> B.lp_data),
and is re-framed by bridge B into a PCIe/PIPE word stream on B.tx_data.
UNIDIRECTIONAL (A->B). The external stimulus is a legal, block-aligned PIPE word
stream produced by the independent Python framer -- the same words the DUT's own
framer emits (the single-bridge scoreboard proves framer==model), so injecting
them directly exercises A's deframer exactly as the proven PHY loopback does.

PyUVM scoreboard cross-check (no two-TB byte-identical trace gate yet):
  1. seam identity   : flits recovered at the UCIe seam (A.pl -> B.lp) == driven.
  2. end-to-end PCIe : an independent Python deframe of bridge B's own PCIe output
                       == the driven flits, and every recovered sync header legal.
  3. deframer health : bridge A reaches block lock and never raises sync_error.

Uses the shared stimulus vector (VEC env) so LEN/SEED/PROFILE knobs apply.
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

PIPE_WIDTH = 80    # ucie2_pipe7_bridge PW default (PIPE_WIDTH_DEFAULT)
RUN_PCLK = int(os.environ.get("RUN_PCLK", "200"))
VEC_FILE = os.environ.get("VEC") or os.path.join(
    os.path.dirname(__file__), "..", "common", "vectors", "fdi_flits_ramp8.vec")
LINK_WARMUP_PCLK = 4    # let both bridges' internal FDI links reach ACTIVE first


@pyuvm.test()
class B2bPcieTest(uvm_test):
    def build_phase(self):
        self.payloads = gv.read_vec(VEC_FILE)

    async def run_phase(self):
        self.raise_objection()
        dut = cocotb.top

        cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
        cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

        self._init_inputs(dut)
        dut.pclk_rst_n.value = 0
        dut.lclk_rst_n.value = 0
        await Timer(11, units="ns")
        dut.pclk_rst_n.value = 1
        dut.lclk_rst_n.value = 1

        seam_flits, b_words = [], []
        stats = {"sync_errors": 0, "saw_lock": False}
        cocotb.start_soon(self._mon_seam(dut, seam_flits))
        cocotb.start_soon(self._mon_btx(dut, b_words, stats))
        cocotb.start_soon(self._drive_rx(dut))

        for _ in range(RUN_PCLK):
            await RisingEdge(dut.pclk)

        self.drop_objection()
        self._check(seam_flits, b_words, stats)

    # ---- stimulus + monitors (timing-critical; kept explicit) ----------------
    def _init_inputs(self, dut):
        for n in ("a_rx_data", "a_rx_valid"):
            getattr(dut, n).value = 0

    async def _drive_rx(self, dut):
        """Replay the block-aligned PIPE word stream into bridge A's PIPE RX.

        Prefer the shared framed-word vector (VEC_WORDS env) so the PyUVM and SV
        UVM tiers inject the identical stream (single source of truth); fall back
        to framing in-process via the same model when it is not provided."""
        words_vec = os.environ.get("VEC_WORDS")
        if words_vec:
            words = gv.read_vec(words_vec)
        else:
            words = fm.frame_stream([(d, False) for d in self.payloads], PIPE_WIDTH)
        for _ in range(LINK_WARMUP_PCLK):
            await RisingEdge(dut.pclk)
        for w in words:
            dut.a_rx_data.value  = w
            dut.a_rx_valid.value = 1
            await RisingEdge(dut.pclk)
        dut.a_rx_valid.value = 0
        dut.a_rx_data.value  = 0

    async def _mon_seam(self, dut, out):
        """Flits recovered by bridge A and handed across the FDI seam (lclk)."""
        while True:
            await RisingEdge(dut.lclk)
            if _i(dut.mid_pl_valid):
                out.append(_i(dut.mid_pl_data))

    async def _mon_btx(self, dut, out, stats):
        """Bridge B's re-framed PCIe output + bridge A deframer health (pclk)."""
        while True:
            await RisingEdge(dut.pclk)
            if _i(dut.b_tx_data_valid):
                out.append(_i(dut.b_tx_data))
            if _i(dut.a_sync_error):
                stats["sync_errors"] += 1
            if _i(dut.a_block_locked):
                stats["saw_lock"] = True

    # ---- three-way cross-check -----------------------------------------------
    def _check(self, seam_flits, b_words, stats):
        driven = self.payloads
        n = len(driven)
        errors = []

        # 1. seam identity: flits recovered across the UCIe seam == driven.
        if seam_flits[:n] != driven:
            k = min(len(seam_flits), n)
            first = next((i for i in range(k) if seam_flits[i] != driven[i]), k)
            errors.append(f"seam mismatch: {len(seam_flits)} recovered vs {n} "
                          f"driven; first diff at flit #{first}")

        # 2. end-to-end PCIe->PCIe: independent deframe of B's own output == driven.
        out = fm.deframe_stream(b_words, PIPE_WIDTH, n)
        out_data = [d for (d, _o, _s) in out]
        if out_data[:n] != driven:
            errors.append(f"end-to-end PCIe mismatch: deframed {len(out_data)} vs "
                          f"{n} driven (B emitted {len(b_words)} words)")
        for (_d, _o, s) in out:
            if not fm.sync_is_legal(s):
                errors.append(f"illegal sync header 0b{s:02b} in bridge B output")
                break

        # 3. deframer health at bridge A.
        if stats["sync_errors"]:
            errors.append(f"bridge A raised sync_error {stats['sync_errors']} time(s)")
        if not stats["saw_lock"]:
            errors.append("bridge A never reached block lock")
        if n == 0:
            errors.append("no flits driven (empty run)")

        self.logger.info(f"[B2B-PCIe] driven={n} seam_recovered={len(seam_flits)} "
                         f"b_words={len(b_words)}")
        assert not errors, \
            "B2B PCIe-UCIe-PCIe cross-check failed:\n  " + "\n  ".join(errors)
