// -----------------------------------------------------------------------------
// fdi_seq_lib — FDI flit sequence (PLAN item 13).
//
// Mirrors dv/pyuvm/seq_lib/fdi_seq_lib.py. Stimulus source is data-driven and
// selected at run time by plusargs so BOTH testbenches drive the identical
// sequence (trace_compare stays byte-identical):
//   +VEC=<path>     -> $readmemh a shared .vec (one 128b payload/line), the
//                      seeded-random or ramp file from dv/common/vectors.
//   (no +VEC)       -> the compiled-in directed ramp
//                      (payload[i] = (0x1000+i)<<64 | (0xABCD0000+i)); this keeps
//                      the self-contained EDA Playground bundle runnable.
//   +N_FLITS=<n>    -> flit count (default N_FLITS localparam = 8).
// `include`d at package scope by ucie2_pipe7_uvm_pkg.sv (sees its localparam N_FLITS).
// -----------------------------------------------------------------------------
class fdi_flit_seq extends uvm_sequence#(fdi_flit_item);
  `uvm_object_utils(fdi_flit_seq)
  function new(string name = "fdi_flit_seq");
    super.new(name);
  endfunction
  virtual task body();
    int unsigned      n_flits;
    string            vec;
    bit               have_vec;
    logic [FDIW-1:0]  mem [int];   // associative: $readmemh-compatible, unbounded
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    have_vec = $value$plusargs("VEC=%s", vec);
    if (have_vec) $readmemh(vec, mem);
    for (int i = 0; i < n_flits; i++) begin
      fdi_flit_item it;
      it = fdi_flit_item::type_id::create($sformatf("flit%0d", i));
      it.data  = have_vec ? mem[i]
                          : ((128'(16'h1000 + i) << 64) | 128'(32'hABCD0000 + i));
      it.is_os = 1'b0;
      start_item(it);
      finish_item(it);
    end
  endtask
endclass
