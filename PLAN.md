# PLAN.md — UCIe 2.0 ↔ PCIe PIPE 7.1 bridge

Development plan for a ground-up RTL bridge that adapts a **UCIe 2.0** die-to-die
controller interface to a **PCIe PIPE 7.1** MAC-facing interface, verified by two
independently-authored, cycle-accurate testbenches (PyUVM and SystemVerilog
UVM-on-Verilator).

Status legend: `[ ]` open · `[~]` in progress · `[x]` done. Execute as a
**numbered closure plan, one item per commit**. Nothing is built yet — this file
and `CLAUDE.md` are the first deliverable.

---

## 1. Purpose

Expose a PCIe controller's PIPE 7.1 MAC port across a UCIe 2.0 link: the bridge
presents a UCIe 2.0 controller-facing interface on one side and drives a PIPE 7.1
MAC-facing interface on the other, so PCIe transaction/data-link traffic tunnels
over the UCIe die-to-die interconnect.

This is a **successor to `~/proj/ucie_rdi_to_pcie6_pipe7`** (UCIe 1.0 RDI → PCIe
6.x / PIPE 7.1). That repo is the RTL/TB **starting point** to mine for reusable
blocks (framer/deframer gearbox, CDC elastic buffer, msgbus master, regfile,
PIPE datapath, the PyUVM env). This project moves the source side to **UCIe 2.0**
and re-does the environment per the constraints below.

## 2. Scope decisions — LOCKED (do not re-litigate)

Decided 2026-08-31. Item 0 (spec cross-check) verifies signal/encoding detail but
does **not** reopen these:

- **UCIe side:** UCIe 2.0, **FDI (Flit-Aware Die-to-Die Interface)**
  controller-facing. This is the interface between the Protocol Layer and the D2D
  Adapter — the bridge sits on the flit-aware boundary and maps protocol flits to
  and from the PIPE side. **This differs from the predecessor**, which used the
  lower **RDI** (raw) interface — so RDI ingress/egress is re-derived as FDI flit
  transmit/receive with FDI-native flow control and state-machine handshakes, not
  ported verbatim. See §3.
- **PIPE side:** PIPE 7.1 **MAC-facing** — drive MAC-owned signals, react to
  PHY-owned ones. No PHY internals (SerDes, CDR, elec-idle detect, PAM4 precode).
- **PCIe rate coverage:** Gen5 (32 GT/s, 128b/130b) **and Gen6 (64 GT/s, PAM4
  FLIT)** — both in scope. No legacy Gen1–4.
- **Config/status:** register file reachable over the UCIe 2.0 management/sideband
  transport (§3), with a bus-master + regfile loop as in the predecessor.
- **Microarchitecture:** "most logical path" is the maintainer's call per block —
  the plan fixes the boundaries and the flit/PIPE contract; internal structure is
  chosen for clarity + a clean cycle-accurate model, not dictated here.

## 3. What changes vs the UCIe-1.0-RDI predecessor

UCIe 2.0 (Aug 2024) is a superset of 1.0, and this bridge uses **FDI** where the
predecessor used RDI. The load-bearing deltas for a MAC-bridge of this shape — to
be **verified, not assumed**, in Item 0:

- **FDI vs RDI:** the controller side is flit-aware — protocol flits with FDI
  valid/credit flow control and the FDI state-machine handshake (lp_state_req /
  pl_state_sts, stallreq/ack, plit/flit framing), rather than RDI's raw
  byte-stream + rdi credit interface. Predecessor RDI blocks are a structural
  reference, not a drop-in.

- **Manageability / sideband:** UCIe 2.0 standardizes a management transport and
  register access over sideband. The bridge's config/status loop should map onto
  this rather than the ad-hoc 1.0 msgbus, if in scope.
- **Runtime health / monitoring** hooks (register-visible).
- **Module widths / multi-module** framing considerations (x8/x16).
- Everything the predecessor already froze that is **unchanged** in 2.0 is carried
  over as-is and simply re-cited to the 2.0 spec section.

Item 0 produces `docs/ucie2_pipe71_spec_crosscheck.md` — an errata/cross-check
sheet against the controlled specs, exactly as the predecessor did for PIPE 7.1
(`docs/pipe71_spec_crosscheck.md`). **No encoding in `rtl/*_pkg.sv` is frozen
until Item 0 signs off on it.**

## 4. Environment constraints (from STARTING_PLAN — binding)

1. **RTL** lives in `rtl/` (SystemVerilog).
2. **`dv/`** carries **two** testbenches that must **match and track on a
   cycle-accurate basis**:
   - `dv/pyuvm/` — PyUVM-on-cocotb (runs under apt/system Verilator).
   - `dv/uvm/` — SystemVerilog UVM under **latest UVM-capable Verilator**
     (built from source, `--binary`).
3. **No OSS CAD Suite.** Toolchain is apt `verilator` + `iverilog` for local
   lint, and a **from-source Verilator ≥ 5.050** for the UVM `--binary` flow
   (modeled on `~/proj/IP-axi-to-2apbs`, which also avoids oss-cad-suite).
4. **Railway container:** a `Dockerfile` + `.railway/railway.ts` (IaC) that runs
   the full DV gate as a run-to-completion batch job (no listening port).
5. **GitHub origin** `git@github.com:markrthomas/ucie2-pipe7-bridge.git` with a
   **Codespaces devcontainer + prebuild** config carrying all tools.
6. **This local host only lint-checks the UVM code** — no full UVM compile/run
   here (the `--binary` build OOMs an ~8 GB box). Full compile+run happens in
   **CI and the Railway container**. The PyUVM flow *does* run locally.
7. Env template is `~/proj/IP-axi-to-2apbs` (devcontainer, Dockerfiles, Railway
   IaC, entrypoint, report generator, CI workflows).

## 5. Cycle-accurate cross-check strategy

The two TBs "match on a cycle-accurate basis" via a **shared contract**, not by
comparing two hand-written checkers:

- **Shared golden model** in `dv/common/models/` (Python for PyUVM; the SV UVM
  env consumes the same vectors). One reference implementation of framing,
  credit FC, and datapath timing.
- **Shared stimulus vectors** in `dv/common/vectors/` — the identical driven
  sequence feeds both TBs.
- **Per-cycle trace format:** both TBs emit a canonical cycle-by-cycle trace of
  the DUT's observable interface (RDI + PIPE signals, one line per PCLK) to a
  `*.trace` file. A `tools/trace_compare.py` diffs the PyUVM trace against the
  UVM trace and fails on the first divergent cycle. This is the literal
  "cycle-accurate tracking" gate.
- Both TBs additionally self-check against the shared golden model (so a
  common-mode bug in one TB cannot hide).

## 6. Proposed layout

```
rtl/                      SystemVerilog RTL: bridge top + submodules + *_pkg.sv
dv/
  common/models/          shared golden reference model (framing, FC, datapath)
  common/vectors/         shared stimulus vectors (feed both TBs)
  pyuvm/                  PyUVM-on-cocotb TB (apt Verilator; local + CI)
  uvm/
    sv/                   shared SV UVM env: interfaces, agents, seq_lib, sb
    vlt/                  Verilator 5.050 --binary flow (lint local; run CI/Railway)
    vcs/                  optional VCS/Xcelium mirror (authored, not run here)
docs/                     spec cross-check, verification plan, architecture
tools/                    trace_compare.py, gen_report.py, lint wrappers
.devcontainer/            devcontainer.json + Dockerfile (Codespaces)
.github/workflows/        lint, pyuvm, uvm-verilator, docker, railway
.railway/railway.ts       Railway IaC (batch job)
Dockerfile[.dev|.ci]      container images
Makefile                  single entry point for every flow
```

## 7. Phased work items

### Phase A — foundation
- [x] **0. Spec cross-check — DONE 2026-08-31.** `docs/ucie2_pipe71_spec_crosscheck.md`
  reconciles UCIe 2.0 FDI (public research: uciedigital + D2D deep-dive) + PIPE 7.1
  (reused from predecessor, Intel Ref 643108) + PCIe 6.x. FDI signal list, PIPE
  encodings, msgbus/register map, and Gen5 framing are **frozen** in
  `rtl/ucie2_pipe7_pkg.sv` (every literal cited or `// FLAGGED`); the boundary
  (shell + SV UVM if/tb/smoke + PyUVM smoke + trace columns) matches. FDI transfer
  = 128b, mapping 1:1 onto the internal `{is_os,data128}` block. 4 FLAGGED items
  (fdi_state encoding, is_os derivation, pl_flit_cancel, UCIe-2.0 mgmt mapping).
- [x] **1. Repo scaffold + env — DONE.** `Makefile`, `.devcontainer/` + Codespaces
  prebuild, `Dockerfile`/`Dockerfile.dev`, `.railway/railway.ts`,
  `docker/entrypoint.sh`, CI workflows (lint + uvm-verilator + cross-check).
- [x] **2. `rtl/` package + top-level shell — DONE** (superseded by Item 0 freeze
  + Phase B top).

### Phase B — datapath cores (FDI-native; mine predecessor blocks where shape matches)
All delivered 2026-08-31 (commits B1–B4). Datapath blocks are drop-in from the
predecessor (only the FDI front-end + top are new).
- [x] **3. FDI TX/RX + link state-machine handshake** — `ucie2_fdi_ingress`/
  `egress` (128b transfer = 1 block) + `ucie2_fdi_link_fsm` (minimal-functional:
  lp_state_req/pl_state_sts stall handshake, rx_active/clk/wake, gates on ACTIVE).
- [x] **4. FDI-clock ↔ PCLK CDC elastic buffer** — `pipe7_cdc_elastic_buf` (reused).
- [x] **5. Gen5 128b/130b framer/deframer (gearbox) + burst FIFO** — reused.
- [x] **6. Gen6 PAM4 raw-wide datapath** — `pipe7_gen6_datapath` (reused; Gen6 TX
  drive path unexercised, mirrors predecessor — FLAGGED follow-up).
- [x] **7. Rate-aware mux + PIPE MAC control FSM** — reused.
- [x] **8. Config/status: msgbus master + register file** — reused; driven via the
  new management ports.
- [x] **9. Integrated bridge top + management ports** — `ucie2_pipe7_bridge`
  composed; controller-side control/msgbus req + status outputs added. Bound SVA
  landed in Phase F increment 1: `dv/uvm/sv/ucie2_pipe7_sva.sv` binds a
  logic-free checker onto the bridge boundary (TxDataValid vs TxElecIdle, block
  lock / `sync_error`, the `pl_stallreq` handshake, `rx_overflow`). It is
  elaborated by `make lint-uvm` and *checked* by the `--binary` `make uvm` run
  (`--assert`); it is deliberately outside `rtl/`, so `make lint`/`pyuvm`/`fcov`
  and the byte-identical trace are untouched.
- [x] **B4. Prove data flows** — directed Gen5 FDI round-trip in BOTH TBs (PHY
  loopback, N=8 flits): PyUVM checks recovered==driven **and** TxData vs
  `framing_model` bit-exact; SV UVM self-checks recovered==driven; both emit the
  cycle-accurate trace for `trace_compare`.

### Phase C — DV tier 1: PyUVM (runs here)
- [x] **10. Shared golden model + vector generator** — `dv/common/models/`
  (`framing_model`, `fdi_model`, `ctrl_plane_model`) + `dv/common/vectors/gen_vectors.py`
  emitting a `$readmemh`-compatible `.vec` both TBs load. `ramp` profile reproduces the
  B4 directed sequence bit-exactly; `random` is seeded/reproducible. Committed
  `fdi_flits_ramp8.vec` (directed 8-flit).
- [x] **11. PyUVM env**: `dv/pyuvm/{agents/fdi_agent,seq_lib/fdi_seq_lib,env}.py`
  — FDI agent (driver + RX monitor), PIPE TX monitor, and a three-way `BridgeScoreboard`
  (round-trip identity + framer-vs-model + deframe-vs-DUT, plus sync_error/lock
  invariants). `test_roundtrip` rebuilt on the env, drives the shared `.vec`, emits the
  canonical per-cycle trace **byte-identical** to the prior producer (verified — so the
  CI cross-check is unaffected). `make pyuvm` green (3-way agreement).
- [x] **12. Functional coverage** cross-check — `dv/common/models/coverage_model.py`
  (16 CoverPoints / 39 bins over control, msgbus, datapath, FDI flow) scored by
  `cocotb_coverage`; `dv/pyuvm/test_fcov.py` drives the control sweep + msgbus sweep
  (with an inline P2M sideband responder) + Gen5 FDI round-trip to an honest 100% of
  the loopback-reachable set. `make fcov` runs on Icarus in CI (independent engine);
  verified locally under Verilator (39/39 = 100%). The two error bins (sync_error=1,
  rx_overflow=1) need an RX-inject wrapper — FLAGGED for Phase F.

### Phase D — DV tier 2: SystemVerilog UVM-on-Verilator
- [ ] **13. Shared SV UVM env** (`dv/uvm/sv`): interfaces, agents, seq_lib,
  scoreboard, per-cycle trace emitter mirroring the PyUVM format.
- [ ] **14. Verilator `--binary` flow** (`dv/uvm/vlt`): `make -C dv/uvm/vlt lint`
  runs **locally**; full build+run runs in **CI + Railway** only.
- [ ] **15. `trace_compare.py` gate**: PyUVM trace ≡ UVM trace, cycle-exact.
- [ ] **16. VCS/Xcelium mirror** (`dv/uvm/vcs`): authored + review-validated, not
  run here.

### Phase E — containerization + CI + reporting
- [ ] **17. Railway image + IaC**: entrypoint runs the full gate; `railway config
  plan/apply` documented.
- [ ] **18. CI**: lint job (apt Verilator) + pyuvm job + uvm-verilator job
  (source-built 5.050, cached) + docker image + trace-compare gate.
- [ ] **19. Codespaces prebuild** validated end-to-end (`make lint`, `make pyuvm`,
  `make lint-uvm`).
- [ ] **20. Metrics report** (`tools/gen_report.py` → `report/`), modeled on the
  predecessor + template.

### Phase F — hardening
- [x] **F2. RTL line coverage (advisory)** — `make coverage` re-runs the directed
  FDI round-trip in a **separate** Verilator `--coverage-line` build
  (`dv/pyuvm/cov_build`, enabled only by `COVERAGE=1`) and scores it with
  `tools/coverage_report.py`, which merges per-instance points by `(file, line)`,
  counts **rtl/ only**, and prints `[COV] line=NN.N%` plus a per-file table into
  `build/coverage/`. Measured baseline: **63.3 % (38/60 RTL lines)** — the gaps
  are the msgbus master and the PIPE MAC control FSM, which the loopback
  round-trip does not exercise (the `fcov` tier does). The floor is **advisory**
  (report only); once the baseline is agreed, enforce it with
  `make coverage COV_MIN=NN` and add `COV_MIN` to the CI step. Additive and
  outside the gate: it runs as a post-gate step in `uvm-verilator.yml` (after
  `trace-compare`, `continue-on-error`), never inside a timed DV run.
- [ ] **21+. Coverage closure, randomized waveform suite, error-path directed
  tests, overflow/accumulator guards, formal (SymbiYosys where a from-source
  toolchain is available — not oss-cad-suite).** Enumerate once Phase E is green.

## 8. Per-commit green gate

Every commit keeps these green (the ones that run in this environment):

- `make lint` — RTL strict `-Wall` under apt Verilator.
- `make pyuvm` — PyUVM tier under apt Verilator.
- `make lint-uvm` — **lint only** of the SV UVM env (elaborate, no `--binary`).

CI/Railway additionally run the full `--binary` UVM build+run and the
`trace_compare` cycle-accurate gate.

## 9. References

- Env template: `~/proj/IP-axi-to-2apbs` (devcontainer, Dockerfiles,
  `.railway/railway.ts`, `docker/entrypoint.sh`, CI, `scripts/gen_report.py`).
- RTL/TB starting point: `~/proj/ucie_rdi_to_pcie6_pipe7` (`src/`, `test/cocotb`,
  `test/uvm`, `PLAN.md`, `docs/pipe71_spec_crosscheck.md`).
