# Verification plan — ucie2-pipe7-bridge

Two independently-authored testbenches drive the same DUT and are held to a
**cycle-accurate** cross-check (PLAN §5).

## Tiers

| Tier | Where | Simulator | Runs locally? |
|------|-------|-----------|---------------|
| RTL lint | `make lint` | apt Verilator `-Wall` | yes |
| PyUVM-on-cocotb | `dv/pyuvm/` | apt Verilator (or Icarus) | yes |
| SV UVM lint | `make lint-uvm` | from-source Verilator ≥ 5.050 | yes (lint only) |
| SV UVM run | `dv/uvm/vlt` (`make uvm`) | from-source Verilator `--binary` | **CI/Railway only** |
| SV UVM (VCS mirror) | `dv/uvm/vcs` | VCS/Xcelium | authored, not run here |

No OSS CAD Suite anywhere in the reproducible flow.

## Cycle-accurate cross-check

- **Contract:** `dv/common/models/trace_format.py` — the canonical per-cycle CSV
  column order. Both TBs emit one row per PCLK; the SV UVM emitter mirrors the
  same columns and must be kept in sync.
- **Gate:** `tools/trace_compare.py` diffs the PyUVM trace against the SV UVM
  trace and fails on the first divergent cycle. Run in CI as
  `make trace-compare`.
- **Shared golden model + vectors** (`dv/common/`) additionally self-check each TB
  so a common-mode bug in one cannot hide (built out in Phase C).

## Coverage / formal (later phases)

- Functional coverage cross-check via `cocotb_coverage` (Icarus) — Item 12
  (CI-only; `cocotb_coverage` is not installed locally).
- Formal (SymbiYosys) on a from-source toolchain — Phase F.

## Per-commit green gate (this environment)

`make lint` · `make pyuvm` · `make lint-uvm`. CI/Railway add `make uvm` and
`make trace-compare`.
