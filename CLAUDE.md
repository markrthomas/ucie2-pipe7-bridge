# CLAUDE.md — ucie2-pipe7-bridge

Orientation for a Claude Code session in this repo.

## What this is

A ground-up **UCIe 2.0 ↔ PCIe PIPE 7.1** MAC-facing bridge IP in SystemVerilog,
verified by **two independently-authored, cycle-accurate testbenches** (PyUVM and
SystemVerilog UVM-on-Verilator). Full scope, decisions, and the phased build-out
are in **`PLAN.md` — read it first.** Nothing is built yet; `PLAN.md` and this
file are the initial deliverable.

- **RTL/TB starting point:** `~/proj/ucie_rdi_to_pcie6_pipe7` (UCIe 1.0 RDI → PCIe
  6.x / PIPE 7.1). Mine its `src/`, `test/cocotb`, `test/uvm` for reusable blocks;
  move the source side to UCIe 2.0.
- **Env template:** `~/proj/IP-axi-to-2apbs` (devcontainer, Dockerfiles, Railway
  IaC, entrypoint, CI, report generator).

## Binding environment constraints (from `STARTING_PLAN`)

- **RTL** in `rtl/`; **two TBs** in `dv/` (`dv/pyuvm/`, `dv/uvm/`) that **track
  cycle-accurately** — enforced by a shared golden model + shared vectors + a
  per-cycle trace that `tools/trace_compare.py` diffs (PLAN §5).
- **Do NOT use OSS CAD Suite.** Local lint uses apt `verilator` + `iverilog`. The
  UVM `--binary` flow uses a **from-source UVM-capable Verilator ≥ 5.050** (the
  apt Verilator cannot elaborate UVM), same approach as the `IP-axi-to-2apbs`
  template.
- **This host only lint-checks the UVM code** — no full UVM compile/run here (the
  `--binary` build OOMs an ~8 GB / WSL ~5.7 GB box). Full UVM compile+run happens
  in **CI and the Railway container**. The **PyUVM tier does run locally**.
- **Railway** = a run-to-completion batch job (no listening port): `Dockerfile` +
  `.railway/railway.ts` with `restartPolicyType: "NEVER"`.
- **GitHub** origin with a **Codespaces devcontainer + prebuild** carrying all
  tools.

## Green gate (run every commit, in this environment)

- `make lint` — RTL strict `-Wall` (apt Verilator).
- `make pyuvm` — PyUVM tier (apt Verilator).
- `make lint-uvm` — **lint/elaborate only** of the SV UVM env; never `--binary`
  here.

CI/Railway additionally run the full `--binary` UVM build+run and the
`trace_compare` cycle-accurate gate. Before claiming the UVM tier passes, say
where it ran (CI/Railway) — it is not run locally.

## Locked scope (decided 2026-08-31 — see PLAN §2)

- **UCIe side: FDI** (Flit-Aware D2D Interface), UCIe 2.0. Not RDI — the
  predecessor's RDI blocks are a structural reference, re-derived as FDI flit
  TX/RX with FDI flow control + state-machine handshake.
- **Gen5 + Gen6** both in scope (Gen6 = 64 GT/s PAM4 FLIT).
- **Microarchitecture is the maintainer's call** per block ("most logical path");
  the plan fixes only the FDI/PIPE boundary contract.

**Item 0 (spec cross-check) is DONE — `rtl/ucie2_pipe7_pkg.sv` encodings are FROZEN.**
Every literal is cited or `// FLAGGED` in `docs/ucie2_pipe71_spec_crosscheck.md`
(FDI signal list, PIPE 7.1 encodings reused from the predecessor, Gen5 framing,
msgbus/register map). FDI transfer = 128b, maps 1:1 to the internal `{is_os,data128}`
block. Four FLAGGED items remain (fdi_state encoding, is_os derivation,
pl_flit_cancel, UCIe-2.0 management mapping) — revisit, don't silently rely on them.

## Local toolchain reality

The `verilator`/`iverilog` on this host's PATH are **oss-cad-suite** builds. This
project must not *depend* on oss-cad-suite, so the reproducible envs
(`.devcontainer/`, `Dockerfile*`, CI) install apt `verilator`/`iverilog` + a
from-source UVM Verilator. The Makefile takes `VERILATOR`/`IVERILOG` overrides so
local runs work with whatever is on PATH. `cocotb` + `pyuvm` 4.0.1 are present
locally (PyUVM tier runs here). The functional-coverage tier (`make fcov`,
Phase C item 12) uses `cocotb_coverage` on the **independent Icarus** engine in
CI; it can also be run locally under Verilator (`make fcov FCOV_SIM=verilator`,
needs `pip install "cocotb==1.9.2" "cocotb_coverage==1.2.0" "pyuvm==4.0.1"`).
Local system Icarus is 11.0 (too old — SV package syntax); CI uses apt Icarus 12.

## Repo / workflow gotchas

- **`origin` is SSH (`git@github.com:markrthomas/ucie2-pipe7-bridge.git`) and SSH
  auth typically fails in this env.** Push over HTTPS instead (matches the sibling
  repos): `git push https://github.com/markrthomas/ucie2-pipe7-bridge.git main`.
- Only commit/push when asked. Branch off `main` if the user wants a PR.
- Durable knowledge goes in tracked docs (`PLAN.md`, `docs/`, this file), not a
  scratch NOTES file.
- End commit messages with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
