"""Per-cycle trace format for the FULL-DUPLEX B2B configs (PLAN H3b / Phase I I8c).

Twin of ``trace_format.py``, extended to the two-bridge full-duplex boundary. BOTH
full-duplex testbenches emit one line per PCLK using exactly these column orders:

  * PyUVM: dv/pyuvm/test_b2b_ucie_fd.py, dv/pyuvm/test_b2b_pcie_fd.py
  * SV UVM: dv/uvm/sv/b2b/b2b_ucie_fd_test.sv, dv/uvm/sv/b2b/b2b_pcie_fd_test.sv

``tools/trace_compare.py`` diffs the PyUVM trace against the SV UVM trace per tier
and fails on the first divergent cycle (``make trace-compare-b2b``). The SV emitters
mirror these columns/formats BY HAND -- if you add/reorder a column here, update the
matching ``$fwrite`` header + row in the SV test too.

Both bridges' observable outputs are traced (``a_*`` = bridge A, ``b_*`` = bridge B)
so a divergence in EITHER direction is caught. Sampled on the coincident 2 ns pclk
edge (lclk is coincident): cocotb post-edge settled reads == the SV ``#0.1`` reads,
exactly as for the single-bridge cross-check.
"""

# ---- external-PCIe full-duplex: both PIPE TX outputs + lock/error status -------
PCIE_FD_COLUMNS = [
    "cycle",
    "a_tx_data_valid", "a_tx_data", "a_block_locked", "a_sync_error",
    "b_tx_data_valid", "b_tx_data", "b_block_locked", "b_sync_error",
]

# ---- external-UCIe full-duplex: both FDI RX (recovered) outputs + FDI status ---
UCIE_FD_COLUMNS = [
    "cycle",
    "a_pl_valid", "a_pl_data", "a_pl_trdy", "a_pl_stallreq", "a_pl_state_sts",
    "a_block_locked", "a_sync_error",
    "b_pl_valid", "b_pl_data", "b_pl_trdy", "b_pl_stallreq", "b_pl_state_sts",
    "b_block_locked", "b_sync_error",
]


def header(columns):
    """CSV header line for the given column list."""
    return ",".join(columns)


def format_row(columns, cycle, sig, pipe_width=80, fdi_width=128):
    """Return one CSV trace line for ``columns``.

    ``*_tx_data`` -> PIPE-width hex, ``*_pl_data`` -> FDI-width hex (both zero-padded,
    no 0x prefix, matching SystemVerilog ``%h``); every other column is decimal.
    ``sig`` maps column name -> int value.
    """
    cells = [str(cycle)]
    for col in columns[1:]:
        val = int(sig.get(col, 0))
        if col.endswith("_tx_data"):
            cells.append(format(val, "0{}x".format(pipe_width // 4)))
        elif col.endswith("_pl_data"):
            cells.append(format(val, "0{}x".format(fdi_width // 4)))
        else:
            cells.append(str(val))
    return ",".join(cells)
