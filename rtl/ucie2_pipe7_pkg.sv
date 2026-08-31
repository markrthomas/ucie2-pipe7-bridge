// -----------------------------------------------------------------------------
// ucie2_pipe7_pkg — shared parameters and types for the UCIe 2.0 (FDI) <-> PCIe
// PIPE 7.1 MAC bridge.
//
// SCAFFOLD (PLAN Item 1/2). Widths and encodings here are provisional and are
// NOT frozen: Item 0 (docs/ucie2_pipe71_spec_crosscheck.md) reconciles them
// against the controlled UCIe 2.0 / PIPE 7.1 (Intel Ref 643108) / PCIe 6.x specs
// and only then are they locked. Do not treat any literal below as spec-exact.
// -----------------------------------------------------------------------------
package ucie2_pipe7_pkg;

  // ---- FDI (Flit-Aware Die-to-Die Interface, controller-facing) -------------
  // Flit payload width presented per FDI clock. UCIe flit is 256 B; the per-clock
  // interface width is an integration parameter. Provisional.
  parameter int unsigned FDI_FLIT_W = 256;

  // ---- PIPE 7.1 (MAC-facing) ------------------------------------------------
  // PIPE parallel data width per PCLK (bits). Provisional; sub-width lane
  // selection is a later item.
  parameter int unsigned PIPE_WIDTH = 64;
  parameter int unsigned PIPE_K     = PIPE_WIDTH / 8; // control (K) bits

  // ---- PCIe rate coverage: Gen5 (128b/130b) + Gen6 (PAM4 FLIT) --------------
  typedef enum logic [2:0] {
    RATE_GEN5 = 3'd4,   // 32 GT/s, 128b/130b   (encoding provisional)
    RATE_GEN6 = 3'd5    // 64 GT/s, PAM4 FLIT   (encoding provisional)
  } pcie_rate_e;

  // PIPE PowerDown states (P0/P0s/P1/P2) — provisional encoding.
  typedef enum logic [1:0] {
    PD_P0  = 2'b00,
    PD_P0S = 2'b01,
    PD_P1  = 2'b10,
    PD_P2  = 2'b11
  } pipe_pwrdn_e;

  // FDI protocol-layer state request / status (subset) — provisional encoding.
  typedef enum logic [2:0] {
    FDI_ST_RESET      = 3'd0,
    FDI_ST_ACTIVE     = 3'd1,
    FDI_ST_L1         = 3'd2,
    FDI_ST_L2         = 3'd3,
    FDI_ST_LINKRESET  = 3'd4,
    FDI_ST_LINKERROR  = 3'd5
  } fdi_state_e;

endpackage : ucie2_pipe7_pkg
