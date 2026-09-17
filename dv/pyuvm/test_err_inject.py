"""Directed RX error-injection + recovery test (Phase I item I5).

Drives the bridge's PIPE RX directly to exercise the deframer's error path, which
the round-trip only ever asserts NEVER fires:

  1. lock       : a legal block-aligned PIPE word stream -> block_locked, flits out.
  2. corrupt    : a run of illegal-sync-header words -> sync_error AND loss of lock.
  3. recover    : a fresh legal stream -> re-lock, and the flits come back correct.

Verifies the DUT reacts (sync_error raised, block_locked dropped) AND recovers
(re-locks, no silent data corruption, no rx_overflow, no hang). Directed
data-plane test (own top module, no build/bridge.trace), so it is independent of
the sacred round-trip cross-check.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

import framing_model as fm

PIPE_WIDTH   = 80    # ucie2_pipe7_bridge PW default
BRINGUP_LCLK = 8
FDI_ACTIVE   = 1
WARMUP_PCLK  = 4
DRAIN_PCLK   = 80
N_GARBAGE    = 24    # illegal-header words: enough to slip through a block and drop lock

# 8 flits = 8*130 = 1040 bits = exactly 13*80-bit PIPE words, so frame_stream emits
# no trailing partial word and every flit is fully injected.
PAYLOAD_A = [0x1111_0000_0000_0000_0000_0000_0000_0000 | i for i in range(8)]
PAYLOAD_B = [0x2222_0000_0000_0000_0000_0000_0000_0000 | i for i in range(8)]


def _i(handle):
    try:
        return int(handle.value)
    except Exception:
        return 0


async def _stall_responder(dut):
    while True:
        await RisingEdge(dut.lclk)
        dut.lp_stallack.value = _i(dut.pl_stallreq)


async def _health_monitor(dut, st):
    """Track deframer health on pclk: sync_error, lock rise/drop/re-lock, overflow."""
    while True:
        await RisingEdge(dut.pclk)
        lk = _i(dut.block_locked)
        if _i(dut.sync_error):
            st["sync_errors"] += 1
        if _i(dut.rx_overflow):
            st["rx_overflow"] = 1
        if lk:
            st["locked_seen"] = True
        if st["locked_seen"] and st["prev_lk"] and not lk:
            st["lock_dropped"] = True
        if st["lock_dropped"] and lk:
            st["relocked"] = True
        st["prev_lk"] = lk


async def _flit_monitor(dut, out):
    """Capture recovered FDI RX flits (lclk)."""
    while True:
        await RisingEdge(dut.lclk)
        if _i(dut.pl_valid):
            out.append(_i(dut.pl_data))


async def _inject(dut, words):
    for w in words:
        dut.rx_data.value  = w
        dut.rx_valid.value = 1
        await RisingEdge(dut.pclk)
    dut.rx_valid.value = 0
    dut.rx_data.value  = 0


async def _drain(dut, n=DRAIN_PCLK):
    for _ in range(n):
        await RisingEdge(dut.pclk)


@cocotb.test()
async def err_inject(dut):
    cocotb.start_soon(Clock(dut.pclk, 2, units="ns").start())
    cocotb.start_soon(Clock(dut.lclk, 2, units="ns").start())

    dut.pclk_rst_n.value = 0
    dut.lclk_rst_n.value = 0
    for name in ("lp_data", "lp_valid", "lp_irdy", "lp_is_os", "lp_state_req",
                 "lp_linkerror", "lp_stallack", "lp_rx_active_req", "lp_clk_ack",
                 "lp_wake_req", "req_valid", "req_kind", "req_power_down", "req_rate",
                 "req_width", "req_rxwidth", "mb_req_valid", "mb_req_write",
                 "mb_req_committed", "mb_req_addr", "mb_req_wdata", "rx_data",
                 "rx_valid", "phy_status", "rx_status", "rx_elec_idle",
                 "p2m_message_bus"):
        if hasattr(dut, name):
            getattr(dut, name).value = 0
    await Timer(10, units="ns")
    dut.pclk_rst_n.value = 1
    dut.lclk_rst_n.value = 1

    st = {"sync_errors": 0, "rx_overflow": 0, "locked_seen": False,
          "lock_dropped": False, "relocked": False, "prev_lk": 0}
    recovered = []
    cocotb.start_soon(_stall_responder(dut))
    cocotb.start_soon(_health_monitor(dut, st))
    cocotb.start_soon(_flit_monitor(dut, recovered))

    # Bring the FDI link up so the egress presents recovered flits on pl_data.
    dut.lp_state_req.value = FDI_ACTIVE
    for _ in range(BRINGUP_LCLK):
        await RisingEdge(dut.lclk)
    await _drain(dut, WARMUP_PCLK)

    # 1) LOCK: legal framed stream -> block_locked, flits recovered.
    await _inject(dut, fm.frame_stream([(d, False) for d in PAYLOAD_A], PIPE_WIDTH))
    await _drain(dut)
    assert st["locked_seen"], "deframer never reached block_locked on a legal stream"
    assert st["sync_errors"] == 0, "sync_error fired on a legal stream"

    # 2) CORRUPT: illegal sync-header words (all zero -> header 00) -> sync_error + lose lock.
    await _inject(dut, [0] * N_GARBAGE)
    await _drain(dut)
    assert st["sync_errors"] >= 1, "corrupt stream did not raise sync_error"
    assert st["lock_dropped"], "corrupt stream did not drop block_locked"

    # 3) RECOVER: fresh legal stream -> re-lock and correct flits.
    await _inject(dut, fm.frame_stream([(d, False) for d in PAYLOAD_B], PIPE_WIDTH))
    await _drain(dut)
    assert st["relocked"], "deframer did not re-lock after the error"
    assert st["rx_overflow"] == 0, "unexpected rx_overflow in this scenario"

    # Data integrity, phase 1: A recovered exactly and cleanly before the error.
    pre = recovered[:len(PAYLOAD_A)]
    assert pre == PAYLOAD_A, (
        f"pre-error flits corrupted\n  got {[hex(x) for x in pre]}"
        f"\n  exp {[hex(x) for x in PAYLOAD_A]}")
    # Data integrity, phase 3: after the error the deframer re-hunts for alignment,
    # so it may drop B's leading block(s), but whatever it recovers must be CORRECT
    # (a contiguous suffix of B) -- no silent corruption, no foreign values.
    post = recovered[len(PAYLOAD_A):]
    assert len(post) >= 1, "no flits recovered after the error (recovery incomplete)"
    assert post == PAYLOAD_B[len(PAYLOAD_B) - len(post):], (
        f"post-error flits are not a clean suffix of B (corruption)\n"
        f"  got {[hex(x) for x in post]}\n  B   {[hex(x) for x in PAYLOAD_B]}")

    dut._log.info(
        f"[err-inject] PASS: lock -> {st['sync_errors']} sync_error(s) + lock drop "
        f"-> re-lock; {len(pre)}/{len(PAYLOAD_A)} pre + {len(post)}/{len(PAYLOAD_B)} "
        f"post flits recovered, all intact")
