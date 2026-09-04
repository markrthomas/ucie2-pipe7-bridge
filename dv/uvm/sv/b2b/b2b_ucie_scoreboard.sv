// -----------------------------------------------------------------------------
// b2b_ucie_scoreboard — round-trip identity across the B2B UCIe pair (PLAN H1).
//
// Mirrors the PyUVM B2B UCIe check: flits recovered out of bridge B == flits
// driven into bridge A, in order; the middle PIPE word count is tracked for the
// report; and bridge B must reach block lock with no sync_error (read from the
// mid monitor). Scoreboard-only (no byte-identical trace gate for B2B yet).
// The `uvm_analysis_imp_decl macros must precede the class.
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_b2bu_exp)
`uvm_analysis_imp_decl(_b2bu_rx)
`uvm_analysis_imp_decl(_b2bu_mid)

class b2b_ucie_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_b2bu_exp#(bit [FDIW-1:0], b2b_ucie_scoreboard) exp_ap;
  uvm_analysis_imp_b2bu_rx #(bit [FDIW-1:0], b2b_ucie_scoreboard) rx_ap;
  uvm_analysis_imp_b2bu_mid#(bit [PW-1:0],   b2b_ucie_scoreboard) mid_ap;

  bit [FDIW-1:0]        exp_q[$];
  bit [FDIW-1:0]        rx_q[$];
  int unsigned          mid_words;
  b2b_ucie_mid_monitor  mid;   // for saw_lock / sync_errors

  `uvm_component_utils(b2b_ucie_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_ap = new("exp_ap", this);
    rx_ap  = new("rx_ap",  this);
    mid_ap = new("mid_ap", this);
  endfunction

  function void write_b2bu_exp(bit [FDIW-1:0] d); exp_q.push_back(d); endfunction
  function void write_b2bu_rx (bit [FDIW-1:0] d); rx_q.push_back(d);  endfunction
  function void write_b2bu_mid(bit [PW-1:0]   d); mid_words++;        endfunction

  virtual function void check_phase(uvm_phase phase);
    if (exp_q.size() == 0)
      `uvm_error("B2BU", "no flits driven (empty run)")
    if (rx_q.size() < exp_q.size())
      `uvm_error("B2BU", $sformatf("only %0d flits recovered out of B (< %0d driven)",
                                   rx_q.size(), exp_q.size()))
    else
      for (int i = 0; i < exp_q.size(); i++)
        if (rx_q[i] !== exp_q[i])
          `uvm_error("B2BU", $sformatf("round-trip mismatch [%0d]: got %h exp %h",
                                       i, rx_q[i], exp_q[i]))
    if (mid == null)
      `uvm_error("B2BU", "mid monitor handle not set")
    else begin
      if (mid.sync_errors != 0)
        `uvm_error("B2BU", $sformatf("bridge B raised sync_error %0d time(s)",
                                     mid.sync_errors))
      if (!mid.saw_lock)
        `uvm_error("B2BU", "bridge B never reached block lock")
    end
    `uvm_info("B2BU", $sformatf("driven %0d, link words %0d, recovered %0d",
              exp_q.size(), mid_words, rx_q.size()), UVM_LOW)
  endfunction
endclass
