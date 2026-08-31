// UVM macro include shim for the open-source (Verilator) UVM flow. REQUIRED,
// TRACKED — do not delete (a fresh checkout fails lint without it).
//
// The env sources `include "uvm_macros.svh", which under a commercial simulator
// resolves to $UVM_HOME/src/uvm_macros.svh. This flow instead compiles the
// Accellera library as the single monolithic header
// uvm_pkg_all_v2020_3_1_dpi.svh (listed first on the tool command line), which
// already defines every `uvm_* macro. This stub only satisfies the `include so
// the same sources compile unchanged; it deliberately defines nothing. It is on
// the open-source flow's +incdir only (see dv/uvm/vlt/Makefile) — a VCS/Xcelium
// flow uses the real header from UVM_HOME and never sees this file.
//
// (First comment word avoids "verilator", which the tool parses as a pragma.)
