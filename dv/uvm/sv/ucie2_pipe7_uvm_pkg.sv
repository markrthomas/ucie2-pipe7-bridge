// -----------------------------------------------------------------------------
// ucie2_pipe7_uvm_pkg — SV UVM environment (PLAN item 13).
//
// A real multi-agent UVM env laid out UVM-Cookbook style — one class per file,
// pulled into this single package via ordered `include (the Cookbook's own
// idiom). The tree under dv/uvm/sv/:
//   fdi_agent/  fdi_flit_item, fdi_sequencer, fdi_seq_lib, fdi_driver,
//               fdi_monitor, fdi_agent  (controller-facing agent + stall_ack)
//   pipe_agent/ pipe_monitor (tx), phy_loopback, pipe_agent  (MAC/PHY-facing)
//   env/        bridge_scoreboard, bridge_env
//   test/       ucie2_roundtrip_test
// mirroring the PyUVM tier (dv/pyuvm/{agents,seq_lib,env}.py).
//
// ONE package keeps every shared type (fdi_flit_item, the localparams below, the
// virtual interface) in one compilation unit, so the split is a pure textual
// reorganization: same tokens, same order, same compilation unit -> the emitted
// per-cycle trace is byte-identical and tools/trace_compare.py stays green. The
// component timing tasks are forked by ucie2_roundtrip_test (not via auto
// run_phases) precisely to preserve that fork order.
//
// Include order respects type dependencies: item -> sequencer -> sequence ->
// driver/monitor -> agent, both agents before env, env before test.
// -----------------------------------------------------------------------------
package ucie2_pipe7_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ucie2_pipe7_pkg::*;

  localparam int unsigned N_FLITS      = 8;
  localparam int unsigned BRINGUP_LCLK = 8;
  localparam int unsigned RUN_PCLK     = 200;
  localparam int unsigned PW           = PIPE_WIDTH_DEFAULT;
  localparam int unsigned FDIW         = FDI_DW;

  // FDI controller-facing agent
  `include "fdi_agent/fdi_flit_item.sv"
  `include "fdi_agent/fdi_sequencer.sv"
  `include "fdi_agent/fdi_seq_lib.sv"
  `include "fdi_agent/fdi_driver.sv"
  `include "fdi_agent/fdi_monitor.sv"
  `include "fdi_agent/fdi_agent.sv"
  // PIPE MAC/PHY-facing agent
  `include "pipe_agent/pipe_monitor.sv"
  `include "pipe_agent/phy_loopback.sv"
  `include "pipe_agent/pipe_agent.sv"
  // Environment
  `include "env/bridge_scoreboard.sv"
  `include "env/bridge_env.sv"
  // Test (the sacred per-cycle trace emitter)
  `include "test/ucie2_roundtrip_test.sv"

endpackage : ucie2_pipe7_uvm_pkg
