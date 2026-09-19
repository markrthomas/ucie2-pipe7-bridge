// -----------------------------------------------------------------------------
// b2b_pcie_fd_scoreboard — full-duplex PCIe end-to-end identity (Phase I I8b).
//
// Both directions must re-frame the injected PIPE word stream identically (bridge
// deframes exactly, far bridge re-frames exactly), in order:
//   forward : words out of B == words injected into A;
//   reverse : words out of A == words injected into B;
// and both deframers must reach block lock with no sync_error (read from the two
// monitors). The expected words are the driver's injected reference per direction
// (no separate seam observation -- the full-duplex harness exposes only the PIPE
// boundary). Mirrors the PyUVM test_b2b_pcie_fd check. Scoreboard-only -- the
// byte-identical B2B trace gate is a later I8 increment.
// The `uvm_analysis_imp_decl macros must precede the class.
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_b2bpfd_efwd)
`uvm_analysis_imp_decl(_b2bpfd_erev)
`uvm_analysis_imp_decl(_b2bpfd_rfwd)
`uvm_analysis_imp_decl(_b2bpfd_rrev)

class b2b_pcie_fd_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_b2bpfd_efwd#(bit [PW-1:0], b2b_pcie_fd_scoreboard) exp_fwd_ap;
  uvm_analysis_imp_b2bpfd_erev#(bit [PW-1:0], b2b_pcie_fd_scoreboard) exp_rev_ap;
  uvm_analysis_imp_b2bpfd_rfwd#(bit [PW-1:0], b2b_pcie_fd_scoreboard) rx_fwd_ap;
  uvm_analysis_imp_b2bpfd_rrev#(bit [PW-1:0], b2b_pcie_fd_scoreboard) rx_rev_ap;

  bit [PW-1:0]          exp_fwd_q[$], exp_rev_q[$];   // injected words per dir
  bit [PW-1:0]          rx_fwd_q[$],  rx_rev_q[$];    // far-end output words
  b2b_pcie_fd_monitor   fwd_mon;   // forward (out at B) -- for saw_lock / sync_errors
  b2b_pcie_fd_monitor   rev_mon;   // reverse (out at A)

  `uvm_component_utils(b2b_pcie_fd_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_fwd_ap = new("exp_fwd_ap", this);
    exp_rev_ap = new("exp_rev_ap", this);
    rx_fwd_ap  = new("rx_fwd_ap",  this);
    rx_rev_ap  = new("rx_rev_ap",  this);
  endfunction

  function void write_b2bpfd_efwd(bit [PW-1:0] d); exp_fwd_q.push_back(d); endfunction
  function void write_b2bpfd_erev(bit [PW-1:0] d); exp_rev_q.push_back(d); endfunction
  function void write_b2bpfd_rfwd(bit [PW-1:0] d); rx_fwd_q.push_back(d);  endfunction
  function void write_b2bpfd_rrev(bit [PW-1:0] d); rx_rev_q.push_back(d);  endfunction

  function void check_dir(string tag, ref bit [PW-1:0] exp_q[$], ref bit [PW-1:0] rx_q[$]);
    if (exp_q.size() == 0)
      `uvm_error("B2BPFD", $sformatf("%s: no words injected (empty run)", tag))
    if (rx_q.size() < exp_q.size())
      `uvm_error("B2BPFD", $sformatf("%s: only %0d words re-framed (< %0d injected)",
                                     tag, rx_q.size(), exp_q.size()))
    else
      for (int i = 0; i < exp_q.size(); i++)
        if (rx_q[i] !== exp_q[i])
          `uvm_error("B2BPFD", $sformatf("%s: end-to-end word mismatch [%0d]: got %h exp %h",
                                         tag, i, rx_q[i], exp_q[i]))
  endfunction

  virtual function void check_phase(uvm_phase phase);
    check_dir("forward A->B", exp_fwd_q, rx_fwd_q);
    check_dir("reverse B->A", exp_rev_q, rx_rev_q);
    if (fwd_mon == null || rev_mon == null)
      `uvm_error("B2BPFD", "monitor handle(s) not set")
    else begin
      if (fwd_mon.sync_errors != 0)
        `uvm_error("B2BPFD", $sformatf("bridge A raised sync_error %0d time(s)", fwd_mon.sync_errors))
      if (rev_mon.sync_errors != 0)
        `uvm_error("B2BPFD", $sformatf("bridge B raised sync_error %0d time(s)", rev_mon.sync_errors))
      if (!fwd_mon.saw_lock) `uvm_error("B2BPFD", "bridge A never reached block lock")
      if (!rev_mon.saw_lock) `uvm_error("B2BPFD", "bridge B never reached block lock")
    end
    `uvm_info("B2BPFD", $sformatf("fwd injected %0d re-framed %0d | rev injected %0d re-framed %0d",
              exp_fwd_q.size(), rx_fwd_q.size(), exp_rev_q.size(), rx_rev_q.size()), UVM_LOW)
  endfunction
endclass
