"""Independent reference for the UCIe 2.0 FDI transfer <-> internal 128b block.

Item 0 froze FDI_DW = BLOCK_PAYLOAD = 128, so an FDI transfer is exactly one
block: the mapping is the identity (is_os defaults to a data block until the
flit-type hook is added — FLAGGED, crosscheck B.1). Kept as its own model so a
future non-128 FDI width or an is_os derivation is captured in one place and the
TBs cross-check against it rather than assuming the identity inline.
"""
FDI_DW = 128
BLOCK_PAYLOAD = 128


def flit_to_block(lp_data: int, is_os: bool = False):
    """One FDI transfer -> (data128, is_os) block."""
    return (lp_data & ((1 << BLOCK_PAYLOAD) - 1), bool(is_os))


def block_to_flit(data128: int, _is_os: bool = False) -> int:
    """One recovered block -> FDI pl_data (is_os is not forwarded on FDI RX)."""
    return data128 & ((1 << FDI_DW) - 1)
