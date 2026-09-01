# Phase D — multi-UVM-agent SV env, built + regressed by a Railway cloud swarm

How item 13 (the SV UVM env) is restructured into a real multi-agent env, and
how a **cloud swarm on Railway** builds and regresses it — because the local
~5.7 GB WSL box OOMs the `--binary` UVM build (CLAUDE.md), so the heavy work must
run where the RAM is: Railway cloud VMs / sandboxes, GitHub Actions, or Codespaces.

## Where each tier runs (decided 2026-09-01, measured not assumed)

The heavy `--binary` UVM build needs >= ~6 GB. Measured/known ceilings:

| Env | RAM | Runs the `--binary` gate? |
|-----|-----|---------------------------|
| Local WSL host | 5.65 GB | No — OOMs (per CLAUDE.md, confirmed) |
| Agent-tool `isolation:"remote"` | = local box | No — falls back to a **local worktree**, not cloud (probed) |
| Railway **sandbox** / `ca` agent VM | ~4 GB (measured; no CLI size knob) | No — too small |
| Railway **service** | up to plan ceiling **8 GB** | Yes (one at a time; the `verilator-uvm` service already ran it `Completed`) |
| **GitHub Actions runner** | ~7 GB | **Yes — the authoritative heavy gate** |

**Decision: the heavy `--binary` + `trace_compare` gate stays in CI**
(`.github/workflows/uvm-verilator.yml`, already green, free, and parallel-capable
via a matrix). The Railway plan ceiling (8 GB) can host ONE heavy run but not a
wide *parallel* heavy swarm, so parallel regression width also comes from CI.

**Railway's role** is therefore the 4 GB tiers it fits well:
- `railway ca --claude` cloud VMs — the **AI-dev swarm** that authors the item-13
  slices, checks elaboration in-VM (`lint-uvm`, ~330 MB), then pushes → CI validates.
- `railway sandbox` — a **light elaborate smoke** + the `probe` utility.

Local host can `lint-uvm` (elaborate) via the from-source Verilator at `~/verilator`
but cannot `--binary`-run (OOM).

## The prebuild (tools boot hot, not built from source)

The root `Dockerfile` already produces the from-source UVM-capable Verilator 5.050
+ Accellera UVM image at `/opt/verilator`. Publishing it once = the prebuild:

- **CI:** `.github/workflows/prebuild-image.yml` builds + pushes it to
  `ghcr.io/markrthomas/ucie2-pipe7-uvm:{latest,<sha>}` on push to `main`.
- **Local:** `make railway-prebuild` builds the same image (docker/podman).
- Consumers (Railway swarm, CI `uvm-verilator`, Codespaces) pull it instead of
  rebuilding Verilator.

There are TWO prebuild artifacts, by tier:

- **Light-tier sandbox template `uvm`** (`make railway-template`) — apt
  verilator + iverilog + cocotb/pyuvm/cocotb_coverage, built via
  `railway sandbox template build` (fast: apt+pip, no source compile,
  content-addressed + cached). Lets a 4 GB sandbox run `make lint` + `make fcov`.
  `sandbox create --template uvm` boots with it present.
- **Heavy-tier GHCR image** (from-source UVM Verilator) — for CI and any 8 GB
  service run. Not needed by the 4 GB sandbox tier.

## Firing the swarm

`tools/railway_swarm.sh` (wrapped by `make railway-swarm[-agents]`) fans out
N-wide. **Dry-run by default** — it prints the exact `railway` commands and
touches nothing; set `SWARM_APPLY=1` to provision (spends money).

| Mode | What each worker is | Command |
|------|--------------------|---------|
| `probe` | one sandbox that reports `nproc`/mem/os then self-destroys (mechanism check) | `make railway-swarm-probe` |
| `gate` (default) | a 4 GB `railway sandbox` (from the `uvm` template) that clones REF + runs `make lint` + `make fcov` (RTL lint + functional coverage). Heavy `--binary` = CI. | `make railway-swarm` |
| `agents` | a `railway ca --claude` cloud VM (Claude Code) that authors one env slice, `lint-uvm`-checks it in-VM, then pushes → CI validates `--binary` | `make railway-swarm-agents` |

Knobs (env-style): `N=`, `SEEDS=`, `TESTS=`, `REF=`, `SWARM_TEMPLATE=`,
`SWARM_APPLY=1`. Example: `N=4 SEEDS="1 2 3 4" SWARM_APPLY=1 make railway-swarm`.

**Validated 2026-09-01:** `make railway-template` built the `uvm` template, and a
real `N=1 SWARM_APPLY=1 make railway-swarm` fire booted a 4 GB sandbox from it,
cloned the ref, and ran `make lint` (RTL OK, Verilator 5.032) + `make fcov`
(iverilog 12.0, cocotb 1.9.2, **bins=39/39 = 100.0%**), then self-destroyed.
Sandbox lifecycle (create→exec→destroy, JSON id-capture) all confirmed live.

**Fire prereqs:** `railway login` (done: markt) **and** `railway link` (or
`RAILWAY_PROJECT`/`RAILWAY_ENVIRONMENT`, or `RAILWAY_TOKEN` in CI). `agents` mode
also needs `CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY` for headless Claude.

**From GitHub:** `.github/workflows/railway-swarm.yml` (manual `workflow_dispatch`,
inputs: mode/n/ref) does the same with the `RAILWAY_TOKEN` secret.

## The integration invariant (non-negotiable)

The per-cycle trace `dv/uvm/vlt/obj/bridge.trace` MUST stay **byte-identical** to
today's output so `tools/trace_compare.py` (vs the PyUVM trace) stays green. That
pins, exactly as the current flat `ucie2_pipe7_uvm_pkg.sv`:

- single 2 ns clock; reset-deassert wait `pclk_rst_n===1`.
- **cycle 0 sampled BEFORE the forked stimulus** (matches cocotb start_soon:
  cycle 0 sees reset-state inputs, `pl_stallreq==0`).
- fork order + `#0.1` post-edge sampling on every read.
- loopback = 1-cycle shadow register → net 2-cycle `rx=tx` delay (VPI-latency match).
- stall_ack = sample N / drive N+1 → visible N+2.
- `BRINGUP_LCLK=8`, `N_FLITS=8`, `RUN_PCLK=200`, payloads
  `(16'h1000+i)<<64 | (32'hABCD0000+i)`.
- trace columns: `cycle,pl_state_sts,pl_valid,pl_trdy,pl_stallreq,pl_flit_cancel,
  tx_data_valid,tx_data(%h),rate,power_down`.

The ONLY reliable acceptance test that restructuring preserved cycle timing is a
`--binary` run + `diff` vs the committed golden — which runs in **CI**
(`uvm-verilator.yml`), the authoritative heavy gate. Elaboration (`lint-uvm`)
catches syntax/structure first, locally or in a 4 GB agent VM.

## Slice decomposition (one `agents`-mode worker per slice)

1. **FDI agent** — `dv/uvm/sv/agents/fdi_agent.svh`: `fdi_flit_item`,
   `fdi_sequencer`, `fdi_driver` (bringup: `lp_state_req=FDI_ACTIVE`; 8×`@lclk`;
   then one flit/lclk honoring the `stimulus()` timing), `fdi_rx_monitor`
   (`cap_rx`), and the `stall_ack` responder (sample N / drive N+1). Mirrors
   `dv/pyuvm/agents/fdi_agent.py`.
2. **PIPE agent** — `dv/uvm/sv/agents/pipe_agent.svh`: `pipe_tx_monitor`
   (`cap_tx` + sync_error/block_locked) and `phy_loopback` (shadow register).
   Mirrors the PyUVM `PipeTxMonitor` + `loopback`.
3. **scoreboard + seq_lib + env** — `dv/uvm/sv/{seq_lib,env}/*`: `fdi_flit_seq`
   (reads the shared `.vec`), `bridge_scoreboard` (recovered==driven + size +
   block_locked + no sync_error), `bridge_env` (wire agents + sb), thin
   `ucie2_roundtrip_test` (build env, run seq, own the trace emitter). Mirrors
   `dv/pyuvm/env.py`.

**Integration (maintainer, not a swarm slice):** the trace emitter stays a
dedicated task in the test reproducing the current run_phase loop exactly
(cycle-0-before-fork, columns, `#0.1`) — the byte-identical-critical piece —
plus `tb_ucie2_pipe7.sv` wiring and the `dv/uvm/vlt/Makefile` source list.
Local (or in-VM) `lint-uvm`, then CI's `--binary` run confirms the golden trace.

## Not blocking (Phase F follow-ups)

- SV framing model for true 3-way scoreboard parity (PyUVM already does 3-way;
  trace_compare covers framing cross-check).
- `mgmt_agent` (ctrl/msgbus) for SV ctrl-sweep tests (currently PyUVM-only).
