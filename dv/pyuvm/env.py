"""PyUVM environment + three-way scoreboard for the integrated ucie2_pipe7_bridge
cross-check (PLAN Phase C, item 11).

The scoreboard performs a three-way cross-check on each run, so a common-mode
framing bug cannot pass silently:

  1. round-trip identity    : DUT recovered FDI flits == driven flits, in order.
  2. framer vs Python model : the DUT's raw PIPE TxData word stream == frame_stream
                              of the driven payloads (bit-exact, independent model).
  3. Python deframe vs DUT  : deframe_stream of the DUT's own TxData stream == the
                              driven payloads (+ every sync header legal).

Any disagreement localizes the bug to exactly one of {DUT, SV-TB(shared model),
Python-TB}. It also folds in the PIPE monitor invariants (no sync_error, deframer
reached block lock).
"""
from pyuvm import (uvm_env, uvm_scoreboard, uvm_tlm_analysis_fifo, ConfigDB)

from agents.fdi_agent import FdiAgent, PipeTxMonitor
import framing_model as fm

PIPE_WIDTH = 80   # matches ucie2_pipe7_bridge PW default (PIPE_WIDTH_DEFAULT)


def _drain(fifo):
    out = []
    while fifo.can_get():
        ok, item = fifo.try_get()
        if not ok:
            break
        out.append(item)
    return out


class BridgeScoreboard(uvm_scoreboard):
    def build_phase(self):
        self.exp_fifo    = uvm_tlm_analysis_fifo("exp_fifo", self)     # driven (data, is_os)
        self.act_fifo    = uvm_tlm_analysis_fifo("act_fifo", self)     # recovered data
        self.stream_fifo = uvm_tlm_analysis_fifo("stream_fifo", self)  # TxData words
        self.errors = []

    def check_phase(self):
        driven = _drain(self.exp_fifo)                # [(data, is_os), ...]
        recovered = _drain(self.act_fifo)            # [data, ...]
        stream = _drain(self.stream_fifo)            # [word, ...]

        exp_data = [d for (d, _o) in driven]
        n = len(driven)

        # 1. round-trip identity
        if recovered[:n] != exp_data:
            k = min(len(recovered), n)
            first = next((i for i in range(k) if recovered[i] != exp_data[i]), k)
            self.errors.append(
                f"round-trip mismatch: {len(recovered)} recovered vs {n} driven; "
                f"first diff at flit #{first}")

        # 2. DUT framer stream == independent Python framer (bit-exact over the overlap)
        model_stream = fm.frame_stream(driven, PIPE_WIDTH)
        k = min(len(stream), len(model_stream))
        if k == 0:
            self.errors.append("no TxData words captured")
        elif stream[:k] != model_stream[:k]:
            first = next((i for i in range(k) if stream[i] != model_stream[i]), k)
            self.errors.append(
                f"framer/model stream mismatch: first diff at word #{first} "
                f"(DUT {len(stream)} vs model {len(model_stream)} words)")

        # 3. independent Python deframe of the DUT's own stream == driven payloads
        model_out = fm.deframe_stream(stream, PIPE_WIDTH, n)
        model_data = [d for (d, _o, _s) in model_out]
        if model_data[:n] != exp_data:
            self.errors.append(
                f"python-deframe vs driven mismatch: {len(model_data)} vs {n}")
        for (_d, _o, s) in model_out:
            if not fm.sync_is_legal(s):
                self.errors.append(f"illegal sync header 0b{s:02b} in DUT stream")
                break

        # Monitor-derived invariants (scoreboard is a leaf; pyuvm runs check_phase
        # top-down, so all pass/fail assertions live here).
        mon = ConfigDB().get(self, "", "PIPE_MON")
        if mon.sync_errors != 0:
            self.errors.append(f"DUT raised sync_error {mon.sync_errors} time(s)")
        if not mon.saw_lock:
            self.errors.append("deframer never reached block lock")
        if n == 0:
            self.errors.append("no flits driven (empty run)")

        self.logger.info(
            f"[SB] driven={n} recovered={len(recovered)} "
            f"stream_words={len(stream)} model_words={len(model_stream)}")

        assert not self.errors, \
            "integrated-bridge cross-check failed:\n  " + "\n  ".join(self.errors)

    def report_phase(self):
        if not self.errors:
            self.logger.info("[SB] integrated-bridge cross-check PASS (3-way agreement)")


class BridgeEnv(uvm_env):
    def build_phase(self):
        self.agent    = FdiAgent("agent", self)
        self.pipe_mon = PipeTxMonitor("pipe_mon", self)
        self.sb       = BridgeScoreboard("sb", self)

    def connect_phase(self):
        self.agent.driver.ap.connect(self.sb.exp_fifo.analysis_export)
        self.agent.rx_mon.ap.connect(self.sb.act_fifo.analysis_export)
        self.pipe_mon.stream_ap.connect(self.sb.stream_fifo.analysis_export)
        # Expose the PIPE monitor so the scoreboard can check sync_error / lock.
        ConfigDB().set(None, "*", "PIPE_MON", self.pipe_mon)
