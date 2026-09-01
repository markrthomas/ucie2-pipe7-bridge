"""Independent control-plane legality model (PLAN Phase C, item 10).

Predicts, for each PowerDown / Rate / Width request, whether ``pipe7_mac_ctrl_fsm``
(rtl/pipe7_mac_ctrl_fsm.sv) should complete (``done``) or reject it (``req_error``),
and the resulting command-signal state. Written independently of the RTL FSM so a
common-mode legality assumption cannot pass silently in both DUT and checker.

Encodings mirror ``ucie2_pipe7_pkg`` exactly (verified against rtl/ucie2_pipe7_pkg.sv):
  PowerDown : PD_P0=0  PD_P0S=1  PD_P1=2  PD_P2=3      (powerdown_e)
  Rate      : RATE_GEN5=4  RATE_GEN6=5                 (rate_e, in-scope subset)
  Width     : W_80=3  W_160=4                          (width_e)
  Req kind  : REQ_POWER=0  REQ_RATE=1  REQ_WIDTH=2     (ctrl_req_e)

Legality rule (PIPE 7.1 §8.4.1, enforced by ``rw_legal()`` in the FSM): a Rate or
Width change is legal only in PowerDown P0 or P1; otherwise it is rejected with a
``req_error`` pulse and no signal change. FSM reset defaults (verified against the
RTL reset block): PowerDown=P0, Rate=GEN5, Width=W_160, RxWidth=W_160.
"""

# PowerDown (powerdown_e)
PD_P0, PD_P0S, PD_P1, PD_P2 = 0, 1, 2, 3
# Rate (rate_e, in-scope subset)
RATE_GEN5, RATE_GEN6 = 4, 5
# Width (width_e)
W_80, W_160 = 3, 4
# Request kind (ctrl_req_e)
REQ_POWER, REQ_RATE, REQ_WIDTH = 0, 1, 2

# Rate/Width may only change in P0 or P1 (matches rw_legal() in the RTL FSM).
_RW_LEGAL = (PD_P0, PD_P1)


class CtrlModel:
    """Mirror of pipe7_mac_ctrl_fsm's applied command-signal state + legality."""

    def __init__(self):
        # pipe7_mac_ctrl_fsm reset defaults.
        self.pd = PD_P0
        self.rate = RATE_GEN5
        self.width = W_160
        self.rxw = W_160

    def state(self):
        return dict(pd=self.pd, rate=self.rate, width=self.width, rxw=self.rxw)

    def predict(self, kind, pd, rate, width, rxw):
        """Return ('done'|'reject', expected_state_after_request).

        A power request always completes and updates PowerDown. A Rate/Width request
        completes and updates its signal(s) only in P0/P1, else it is rejected with
        no state change.
        """
        if kind == REQ_POWER:
            self.pd = pd
            return "done", self.state()
        if kind in (REQ_RATE, REQ_WIDTH):
            if self.pd in _RW_LEGAL:
                if kind == REQ_RATE:
                    self.rate = rate
                else:
                    self.width = width
                    self.rxw = rxw
                return "done", self.state()
            return "reject", self.state()   # illegal PowerDown: no change
        return "reject", self.state()
