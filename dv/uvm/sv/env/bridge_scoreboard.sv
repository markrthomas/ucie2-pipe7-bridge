// -----------------------------------------------------------------------------
// bridge_scoreboard — round-trip identity + datapath invariants (PLAN item 13).
//
// Mirrors the PyUVM BridgeScoreboard: recovered FDI flits (rx_mon) must equal the
// driven flits (driver.drv_ap), the deframer must reach block_locked with no
// sync_error, and at least N_FLITS must be recovered. TX word count is tracked
// for the report. These are exactly the proven directed test's self-checks.
// The `uvm_analysis_imp_decl macros must precede the class (they define the
// _exp/_rx/_tx analysis-imp specializations it uses).
// -----------------------------------------------------------------------------
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_tx)

class bridge_scoreboard extends uvm_scoreboard;
  uvm_analysis_imp_exp#(bit [FDIW-1:0], bridge_scoreboard) exp_ap;
  uvm_analysis_imp_rx #(bit [FDIW-1:0], bridge_scoreboard) rx_ap;
  uvm_analysis_imp_tx #(bit [PW-1:0],   bridge_scoreboard) tx_ap;

  bit [FDIW-1:0] exp_q[$];
  bit [FDIW-1:0] rx_q[$];
  int unsigned   tx_count;
  virtual ucie2_pipe7_if vif;

  `uvm_component_utils(bridge_scoreboard)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_ap = new("exp_ap", this);
    rx_ap  = new("rx_ap",  this);
    tx_ap  = new("tx_ap",  this);
  endfunction

  function void write_exp(bit [FDIW-1:0] d); exp_q.push_back(d); endfunction
  function void write_rx (bit [FDIW-1:0] d); rx_q.push_back(d);  endfunction
  function void write_tx (bit [PW-1:0]   d); tx_count++;         endfunction

  virtual function void check_phase(uvm_phase phase);
    if (vif.sync_error !== 1'b0)
      `uvm_error("SB", "deframer raised sync_error")
    if (vif.block_locked !== 1'b1)
      `uvm_error("SB", "deframer never reached block_locked")
    if (rx_q.size() < N_FLITS)
      `uvm_error("SB", $sformatf("only %0d flits recovered (< %0d)",
                                 rx_q.size(), N_FLITS))
    else
      for (int i = 0; i < N_FLITS; i++)
        if (rx_q[i] !== exp_q[i])
          `uvm_error("SB", $sformatf("round-trip mismatch [%0d]: got %h exp %h",
                                     i, rx_q[i], exp_q[i]))
    `uvm_info("SB", $sformatf("roundtrip: %0d driven, tx %0d words, recovered %0d",
              exp_q.size(), tx_count, rx_q.size()), UVM_LOW)
  endfunction
endclass
