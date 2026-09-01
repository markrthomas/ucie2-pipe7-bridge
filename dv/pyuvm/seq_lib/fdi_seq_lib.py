"""PyUVM sequence library (PLAN Phase C, item 11).

Shares test intent with the SV/UVM sequences: a stream of 128-bit FDI flits drawn
from the shared vector file (dv/common/vectors/gen_vectors.py), so both TBs drive
the identical sequence and the cycle-accurate cross-check stays meaningful. The
vectors are passed in from the test (loaded once from the .vec) rather than
regenerated here, so the file is the single source of truth.
"""
from pyuvm import uvm_sequence

from agents.fdi_agent import FdiFlit


class FdiFlitSeq(uvm_sequence):
    """Drive a given list of 128-bit payloads (data blocks) as FDI flits, in order."""
    def __init__(self, name="FdiFlitSeq", flits=None):
        super().__init__(name)
        self.flits = list(flits or [])

    async def body(self):
        for data in self.flits:
            item = FdiFlit("flit", data=data, is_os=False)
            await self.start_item(item)
            await self.finish_item(item)
