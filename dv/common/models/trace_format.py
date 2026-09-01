"""Canonical per-cycle trace format — the single source of truth for the
cycle-accurate cross-check (PLAN Section 5).

BOTH testbenches emit one line per PCLK to a ``*.trace`` file using exactly this
column order. ``tools/trace_compare.py`` diffs the PyUVM trace against the SV UVM
trace and fails on the first divergent cycle. The SV UVM emitter
(dv/uvm/sv) mirrors this column order by hand and MUST be kept in sync with the
list below — if you add/reorder a column here, update the SV emitter too.

Observable DUT boundary only: sampled outputs the two environments must agree on.
"""

# Ordered column names. Column 0 is the free-running PCLK cycle index.
# Observable DUT outputs on the frozen (Item 0) boundary.
TRACE_COLUMNS = [
    "cycle",
    "pl_state_sts",    # FDI link state reported to protocol layer (fdi_state_e)
    "pl_valid",        # FDI RX data valid
    "pl_trdy",         # FDI TX ready
    "pl_stallreq",     # FDI stall request
    "pl_flit_cancel",  # FDI flit cancel
    "tx_data_valid",   # PIPE TxDataValid
    "tx_data",         # hex, no 0x prefix, zero-padded to PIPE_WIDTH/4 nibbles
    "rate",            # PIPE Rate[3:0]
    "power_down",      # PIPE PowerDown[3:0]
]

TRACE_HEADER = ",".join(TRACE_COLUMNS)


def format_row(cycle, sig, pipe_width=80):
    """Return one CSV trace line. ``sig`` maps column name -> int value."""
    nib = pipe_width // 4
    cells = [str(cycle)]
    for col in TRACE_COLUMNS[1:]:
        val = int(sig.get(col, 0))
        cells.append(format(val, "0{}x".format(nib)) if col == "tx_data" else str(val))
    return ",".join(cells)
