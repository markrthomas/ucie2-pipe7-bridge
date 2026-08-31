import { defineRailway, preserve, project, service } from "railway/iac";

// Railway Infrastructure as Code — https://docs.railway.com/infrastructure-as-code
//
// This project is a hardware DV gate, not a web service: it has no listening
// port. The container's ENTRYPOINT (docker/entrypoint.sh) runs `make -C
// dv/uvm/vlt ci` (lint + the SV UVM --binary build+run under from-source
// Verilator, UVM_ERROR-gated) and exits with the gate's status (0 = green). Run
// it as a one-off / batch job, not an always-on service.

export default defineRailway(() => {
  const uvm = service("ucie2-pipe7-uvm", {
    // Root Dockerfile (Verilator from source) is auto-detected as the builder.
    replicas: 1,

    // Batch job: a run-to-completion gate that exits 0 must NOT be restarted (a
    // normal service that exits 0 is flagged "crashed"). Do NOT set a start
    // command — it would bypass the entrypoint that injects the bundled-Verilator
    // overrides and the memory preflight.
    restartPolicyType: "NEVER",

    // Keep any Railway-level BUILD_JOBS override without writing it into source
    // (the Dockerfile already bakes ENV BUILD_JOBS=1).
    env: { BUILD_JOBS: preserve() },
  });

  return project("ucie2-pipe7-bridge", {
    resources: [uvm],
  });
});
