// -----------------------------------------------------------------------------
// fdi_seq_lib — FDI stimulus item + directed ramp sequence (PLAN item 13).
//
// Mirrors dv/pyuvm/seq_lib/fdi_seq_lib.py. The payload formula is byte-identical
// to the proven directed round-trip, so the emitted per-cycle trace and the
// recovered-flit check are unchanged (trace_compare stays green).
// Included at package scope by ucie2_pipe7_uvm_pkg.sv (sees its localparams).
// -----------------------------------------------------------------------------
class fdi_flit_item extends uvm_sequence_item;
  rand bit [FDIW-1:0] data;
  bit                 is_os;
  `uvm_object_utils(fdi_flit_item)
  function new(string name = "fdi_flit_item");
    super.new(name);
  endfunction
endclass

typedef uvm_sequencer#(fdi_flit_item) fdi_sequencer;

class fdi_flit_seq extends uvm_sequence#(fdi_flit_item);
  int unsigned n_flits = N_FLITS;
  `uvm_object_utils(fdi_flit_seq)
  function new(string name = "fdi_flit_seq");
    super.new(name);
  endfunction
  virtual task body();
    for (int i = 0; i < n_flits; i++) begin
      fdi_flit_item it;
      it = fdi_flit_item::type_id::create($sformatf("flit%0d", i));
      it.data  = (128'(16'h1000 + i) << 64) | 128'(32'hABCD0000 + i);
      it.is_os = 1'b0;
      start_item(it);
      finish_item(it);
    end
  endtask
endclass
