// -----------------------------------------------------------------------------
// fdi_sequencer — sequencer for fdi_flit_item (PLAN item 13).
//
// A plain uvm_sequencer specialization (UVM-Cookbook style: the sequencer gets
// its own file even when it is a simple typedef). `include`d after
// fdi_flit_item.sv by ucie2_pipe7_uvm_pkg.sv.
// -----------------------------------------------------------------------------
typedef uvm_sequencer#(fdi_flit_item) fdi_sequencer;
