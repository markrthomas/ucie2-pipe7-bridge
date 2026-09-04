// -----------------------------------------------------------------------------
// b2b_pcie_scoreboard — end-to-end check across the B2B PCIe pair (PLAN H2).
//
// Mirrors the PyUVM B2B PCIe check. It knows the expected FDI flits from +VEC (the
// same flit vector the framed +VEC_WORDS was generated from) and the expected
// bridge-B output from the driver's injected-word reference (A recovers the flits
// exactly and B re-frames them identically, so B's output == the injected words):
//   1. seam identity : flits recovered at the UCIe seam (mid_pl) == the +VEC flits.
//   2. end-to-end    : bridge B's PCIe output words == the injected words.
//   3. deframer health: bridge A reaches block lock with no sync_error.
// Scoreboard-only (no byte-identical trace gate for B2B yet, PLAN H3).
// The `uvm_analysis_imp_decl macros must precede the class.
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_b2bp_ref)
`uvm_analysis_imp_decl(_b2bp_seam)
`uvm_analysis_imp_decl(_b2bp_btx)

class b2b_pcie_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_b2bp_ref #(bit [PW-1:0],   b2b_pcie_scoreboard) ref_ap;
  uvm_analysis_imp_b2bp_seam#(bit [FDIW-1:0], b2b_pcie_scoreboard) seam_ap;
  uvm_analysis_imp_b2bp_btx #(bit [PW-1:0],   b2b_pcie_scoreboard) btx_ap;

  bit [FDIW-1:0]           exp_q[$];    // expected flits (from +VEC)
  bit [PW-1:0]             ref_q[$];    // injected words (driver reference)
  bit [FDIW-1:0]           seam_q[$];   // flits recovered at the seam
  bit [PW-1:0]             btx_q[$];    // bridge B output words
  b2b_pcie_btx_monitor     btx;         // for saw_lock / sync_errors

  `uvm_component_utils(b2b_pcie_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    ref_ap  = new("ref_ap",  this);
    seam_ap = new("seam_ap", this);
    btx_ap  = new("btx_ap",  this);
  endfunction

  // Load the expected flit sequence from +VEC (same file gen_vectors framed into
  // +VEC_WORDS), so the seam check knows what bridge A should recover.
  virtual function void build_phase(uvm_phase phase);
    int unsigned      n_flits;
    string            vec;
    logic [FDIW-1:0]  mem [int];
    super.build_phase(phase);
    if (!$value$plusargs("N_FLITS=%d", n_flits)) n_flits = N_FLITS;
    if ($value$plusargs("VEC=%s", vec)) begin
      $readmemh(vec, mem);
      for (int i = 0; i < n_flits; i++) exp_q.push_back(mem[i]);
    end else begin
      for (int i = 0; i < n_flits; i++)
        exp_q.push_back((128'(16'h1000 + i) << 64) | 128'(32'hABCD0000 + i));
    end
  endfunction

  function void write_b2bp_ref (bit [PW-1:0]   d); ref_q.push_back(d);  endfunction
  function void write_b2bp_seam(bit [FDIW-1:0] d); seam_q.push_back(d); endfunction
  function void write_b2bp_btx (bit [PW-1:0]   d); btx_q.push_back(d);  endfunction

  virtual function void check_phase(uvm_phase phase);
    if (exp_q.size() == 0)
      `uvm_error("B2BP", "no flits expected (empty run)")
    // 1. seam identity
    if (seam_q.size() < exp_q.size())
      `uvm_error("B2BP", $sformatf("only %0d flits recovered at seam (< %0d expected)",
                                   seam_q.size(), exp_q.size()))
    else
      for (int i = 0; i < exp_q.size(); i++)
        if (seam_q[i] !== exp_q[i])
          `uvm_error("B2BP", $sformatf("seam mismatch [%0d]: got %h exp %h",
                                       i, seam_q[i], exp_q[i]))
    // 2. end-to-end: bridge B re-frames to exactly the injected words
    if (btx_q.size() < ref_q.size())
      `uvm_error("B2BP", $sformatf("bridge B emitted %0d words (< %0d injected)",
                                   btx_q.size(), ref_q.size()))
    else
      for (int i = 0; i < ref_q.size(); i++)
        if (btx_q[i] !== ref_q[i])
          `uvm_error("B2BP", $sformatf("end-to-end word mismatch [%0d]: got %h exp %h",
                                       i, btx_q[i], ref_q[i]))
    // 3. deframer health at bridge A
    if (btx == null)
      `uvm_error("B2BP", "btx monitor handle not set")
    else begin
      if (btx.sync_errors != 0)
        `uvm_error("B2BP", $sformatf("bridge A raised sync_error %0d time(s)",
                                     btx.sync_errors))
      if (!btx.saw_lock)
        `uvm_error("B2BP", "bridge A never reached block lock")
    end
    `uvm_info("B2BP", $sformatf("expected %0d flits, seam %0d, injected %0d words, B out %0d",
              exp_q.size(), seam_q.size(), ref_q.size(), btx_q.size()), UVM_LOW)
  endfunction
endclass
