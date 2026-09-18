// -----------------------------------------------------------------------------
// b2b_ucie_fd_scoreboard — full-duplex round-trip identity (Phase I I8).
//
// Both directions must round-trip the shared FDI vector in order:
//   forward : flits recovered out of B == flits driven into A;
//   reverse : flits recovered out of A == flits driven into B;
// and both bridges must reach block lock with no sync_error (read from the two
// monitors). Mirrors the PyUVM test_b2b_ucie_fd check. Scoreboard-only -- the
// byte-identical B2B trace gate is a later I8 increment.
// The `uvm_analysis_imp_decl macros must precede the class.
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_b2bufd_efwd)
`uvm_analysis_imp_decl(_b2bufd_erev)
`uvm_analysis_imp_decl(_b2bufd_rfwd)
`uvm_analysis_imp_decl(_b2bufd_rrev)

class b2b_ucie_fd_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_b2bufd_efwd#(bit [FDIW-1:0], b2b_ucie_fd_scoreboard) exp_fwd_ap;
  uvm_analysis_imp_b2bufd_erev#(bit [FDIW-1:0], b2b_ucie_fd_scoreboard) exp_rev_ap;
  uvm_analysis_imp_b2bufd_rfwd#(bit [FDIW-1:0], b2b_ucie_fd_scoreboard) rx_fwd_ap;
  uvm_analysis_imp_b2bufd_rrev#(bit [FDIW-1:0], b2b_ucie_fd_scoreboard) rx_rev_ap;

  bit [FDIW-1:0]        exp_fwd_q[$], exp_rev_q[$];
  bit [FDIW-1:0]        rx_fwd_q[$],  rx_rev_q[$];
  b2b_ucie_fd_monitor   fwd_mon;   // at B (forward)  -- for saw_lock / sync_errors
  b2b_ucie_fd_monitor   rev_mon;   // at A (reverse)

  `uvm_component_utils(b2b_ucie_fd_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_fwd_ap = new("exp_fwd_ap", this);
    exp_rev_ap = new("exp_rev_ap", this);
    rx_fwd_ap  = new("rx_fwd_ap",  this);
    rx_rev_ap  = new("rx_rev_ap",  this);
  endfunction

  function void write_b2bufd_efwd(bit [FDIW-1:0] d); exp_fwd_q.push_back(d); endfunction
  function void write_b2bufd_erev(bit [FDIW-1:0] d); exp_rev_q.push_back(d); endfunction
  function void write_b2bufd_rfwd(bit [FDIW-1:0] d); rx_fwd_q.push_back(d);  endfunction
  function void write_b2bufd_rrev(bit [FDIW-1:0] d); rx_rev_q.push_back(d);  endfunction

  function void check_dir(string tag, ref bit [FDIW-1:0] exp_q[$], ref bit [FDIW-1:0] rx_q[$]);
    if (exp_q.size() == 0)
      `uvm_error("B2BUFD", $sformatf("%s: no flits driven (empty run)", tag))
    if (rx_q.size() < exp_q.size())
      `uvm_error("B2BUFD", $sformatf("%s: only %0d flits recovered (< %0d driven)",
                                     tag, rx_q.size(), exp_q.size()))
    else
      for (int i = 0; i < exp_q.size(); i++)
        if (rx_q[i] !== exp_q[i])
          `uvm_error("B2BUFD", $sformatf("%s: round-trip mismatch [%0d]: got %h exp %h",
                                         tag, i, rx_q[i], exp_q[i]))
  endfunction

  virtual function void check_phase(uvm_phase phase);
    check_dir("forward A->B", exp_fwd_q, rx_fwd_q);
    check_dir("reverse B->A", exp_rev_q, rx_rev_q);
    if (fwd_mon == null || rev_mon == null)
      `uvm_error("B2BUFD", "monitor handle(s) not set")
    else begin
      if (fwd_mon.sync_errors != 0)
        `uvm_error("B2BUFD", $sformatf("bridge B raised sync_error %0d time(s)", fwd_mon.sync_errors))
      if (rev_mon.sync_errors != 0)
        `uvm_error("B2BUFD", $sformatf("bridge A raised sync_error %0d time(s)", rev_mon.sync_errors))
      if (!fwd_mon.saw_lock) `uvm_error("B2BUFD", "bridge B never reached block lock")
      if (!rev_mon.saw_lock) `uvm_error("B2BUFD", "bridge A never reached block lock")
    end
    `uvm_info("B2BUFD", $sformatf("fwd driven %0d recovered %0d | rev driven %0d recovered %0d",
              exp_fwd_q.size(), rx_fwd_q.size(), exp_rev_q.size(), rx_rev_q.size()), UVM_LOW)
  endfunction
endclass
