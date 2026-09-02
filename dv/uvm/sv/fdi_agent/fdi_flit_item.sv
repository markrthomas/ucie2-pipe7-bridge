// -----------------------------------------------------------------------------
// fdi_flit_item — FDI stimulus transaction (PLAN item 13).
//
// One class per file, UVM-Cookbook style. `include`d at package scope by
// ucie2_pipe7_uvm_pkg.sv, so it sees the package localparams (FDIW). Mirrors
// dv/pyuvm/seq_lib/fdi_seq_lib.py's item. Payload is filled by fdi_flit_seq.
// -----------------------------------------------------------------------------
class fdi_flit_item extends uvm_sequence_item;
  rand bit [FDIW-1:0] data;
  bit                 is_os;
  `uvm_object_utils(fdi_flit_item)
  function new(string name = "fdi_flit_item");
    super.new(name);
  endfunction
endclass
