# Tutorial — working in the ucie2-pipe7-bridge environment

A hands-on, start-to-finish walkthrough of *this* development environment: what
runs where, why, and the exact commands. It complements the other docs rather
than repeating them:

- **`README.md`** — reference-style section per feature.
- **`PLAN.md`** — the full scope and phased build-out.
- **`CLAUDE.md`** — orientation + binding constraints for an AI session.
- **this file** — the guided tour you read once to understand the whole machine.

If you only remember one thing: **every gate is a `make` target, and each target
is labelled with *where* it is meant to run** (`[local]`, `[CI/Railway]`,
`[…post-gate]`, `[…off-gate]`). `make help` prints the authoritative list.

---

## 0. The mental model: three places, one Makefile

The single most important idea is that work happens in **three kinds of place**,
and the Makefile is written so the same targets behave correctly in each:

| Place | What it is | What it runs | Why |
|-------|-----------|--------------|-----|
| **Local box** | your laptop / WSL (~5.7–8 GB) | the light gates: `lint`, `pyuvm`, `fcov`, `lint-uvm`, plus all post-gate/off-gate tiers | fast iteration; fits in RAM |
| **CI** | GitHub Actions | *everything*, authoritatively — including the heavy `uvm` `--binary` build + `trace-compare` | clean toolchain, the source of truth |
| **Remote runner** | Railway container **or** a GitHub Codespace | the heavy `uvm` gate on demand, driven from your laptop | the `--binary` UVM build OOMs the local box |

The reason for the split is **RAM + toolchain**:

- The SV UVM `--binary` build needs a **from-source, UVM-capable Verilator ≥ 5.050**
  and several GB of RAM for its precompiled-header compile. That OOMs a ~5.7 GB
  WSL box. So locally you **lint/elaborate** the UVM env (RAM-safe); the full
  build+run happens in CI, or on a remote runner you fire yourself.
- The apt Verilator (5.020) **cannot elaborate UVM** at all — it is fine for the
  RTL `lint` and the PyUVM tier, but the UVM tier needs the from-source build.
- **This project does NOT depend on OSS CAD Suite.** The reproducible
  environments install apt `verilator`/`iverilog` + a from-source UVM Verilator.
  Your local box may *happen* to have oss-cad-suite on `PATH`; the Makefile works
  around that (see §2).

---

## 1. First-time setup

### 1.1 Get the toolchain

```bash
make tools-check    # report only — what's present / missing, installs nothing
make tools          # install the MISSING light-tier pieces (apt + pip)
```

`make tools` audits four tiers and installs the light ones:

- **core** — apt `verilator`/`iverilog` + pip `cocotb`/`pyuvm`/`cocotb_coverage`
  (drives `lint`, `pyuvm`, `fcov`).
- **formal** — `yosys` + `z3` + SymbiYosys (`make formal`).
- **waves** — `gtkwave` (`make wave*`).
- **heavy** — the from-source UVM Verilator (`make uvm`). **Opt-in**, because it is
  a multi-minute, hundreds-of-MB build:

```bash
make tools TOOLS_HEAVY=1   # also build Verilator >=5.050 into ~/verilator
```

`tools-check` exits non-zero **only** if a *core* tool is missing (safe as a CI
gate); optional gaps are fine. Logic lives in `tools/check_tools.sh`.

### 1.2 Understand your local Verilator situation

Run `command -v verilator`. On the maintainer's box this resolves to an
**oss-cad-suite** build (it also exports `VERILATOR_ROOT`). That is fine — the
Makefile has a **`LOCAL` autodetect** (§2) that quietly swaps in a clean
toolchain for the gate targets. You do not need to fix your `PATH`.

---

## 2. How `LOCAL` autodetect works (and when to override it)

The Makefile decides it is "local" when **both** are true:

1. oss-cad-suite is on `PATH` / in `VERILATOR_ROOT`, and
2. a from-source Verilator exists at `~/verilator`.

When `LOCAL=1`, the plain gate targets (`lint`, `pyuvm`, `fcov`, `lint-uvm`,
`coverage`) auto-wrap themselves in a clean environment: they drop
`VERILATOR_ROOT`, put `~/verilator/bin` and `/usr/bin` first on `PATH`, use
`/usr/bin/python3` (the interpreter that actually has cocotb), and point
`UVM_HOME` at the bundled UVM library. In **CI/Railway** (clean `PATH`, no
`~/verilator`) this is inert and everything runs canonically.

You rarely touch this, but two overrides exist:

```bash
make fcov LOCAL=0      # force the canonical CI toolchain on your box
make fcov-ci          # same thing, shorthand: the -ci targets pin LOCAL=0
make lint LOCAL=1     # force local mode
```

Use `-ci` variants when you want to reproduce *exactly* what CI does locally.

---

## 3. The green gate — run this every commit

Three targets, all `[local]`, all fast:

```bash
make lint       # RTL strict lint (Verilator -Wall)
make pyuvm      # PyUVM-on-cocotb tier (the default round-trip)
make lint-uvm   # elaborate-only lint of the SV UVM env (never --binary here)
```

Read the banners — each tier prints a pass line. `make lint-uvm` ends with
`[lint-uvm] SV UVM env elaborates OK`.

> **Never claim the UVM tier "passes" from a local run.** Locally you only
> *elaborate* it. The full `--binary` build+run is CI/Railway (§6). When you
> report the UVM tier green, say **where** it ran.

### 3.1 The default stimulus: seeded-random, adjustable length

`make pyuvm` drives a **seeded-random** flit sequence. Both testbenches read
**one** generated vector (`dv/common/vectors/build/fdi_flits.vec`), which is what
keeps the two independent TBs byte-identical (§5). Knobs:

```bash
make pyuvm LEN=64          # 64 random flits (default 8)
make pyuvm SEED=42        # a different fixed sequence (default seed 0xC0FFEE)
make pyuvm SEED=random    # a fresh sequence each run (prints the seed it picked)
make pyuvm PROFILE=ramp   # the directed 0x1000+i ramp instead (regression)
make gen-vectors          # (re)generate the shared vector by hand
```

The FDI driver honours `pl_trdy` backpressure, so any length round-trips without
dropping flits; `RUN_PCLK` (trace/drain cycles) auto-scales as `160 + 40*LEN`.

---

## 4. The other local tiers

```bash
make fcov       # functional coverage (cocotb_coverage; Icarus in CI, Verilator local)
make b2b        # back-to-back two-bridge configs (PyUVM): UCIe==link==UCIe and
                #   PCIe==link==PCIe. Same LEN/SEED/PROFILE knobs.
```

`make b2b` joins two `ucie2_pipe7_bridge` instances through a `dv/harness`
wrapper — it exercises the bridge against *itself*, a strong end-to-end check.

---

## 5. The heart of the DV: the cycle-accurate cross-check

This repo verifies the RTL with **two independently-authored** cycle-accurate
testbenches:

- **PyUVM-on-cocotb** (`dv/pyuvm/`) — runs locally + CI.
- **SV UVM-on-Verilator** (`dv/uvm/sv/`, Cookbook-style, one class per file) —
  full run in CI/Railway.

They are kept honest three ways:

1. a **shared golden model** (`dv/common/models/`),
2. a **shared stimulus vector** (`dv/common/vectors/build/`), and
3. a **per-cycle trace** each tier emits, diffed by `tools/trace_compare.py`.

```bash
make trace-compare   # byte-for-byte diff of the PyUVM trace vs the UVM trace
```

The SV side's `dv/uvm/sv/test/ucie2_roundtrip_test.sv` is the **sacred** trace
emitter — its `run_phase` fork order and `#0.1` sampling are exactly what make
the two traces byte-identical. **Do not restructure it.** Any observability you
add (see `PKT_TRACK`, §8) must be zero-sim-time so the trace is unchanged.

---

## 6. The heavy UVM gate — `make uvm`

`make uvm` is the **single canonical SV UVM gate**: it regenerates the shared
seeded-random vector, then runs elaborate-lint **and** the `--binary` build+run
(UVM_ERROR-gated), all reading the same vector as `make pyuvm`. It is the exact
target CI and the Railway/Docker container entrypoint run.

You have three ways to run it:

### 6.1 In CI (automatic, authoritative)

Push a branch / open a PR — the `uvm-verilator` workflow builds the from-source
Verilator and runs `make uvm` + `make trace-compare` + the B2B UVM tier. This is
the source of truth; you don't do anything special.

### 6.2 Locally (only if you have the RAM)

`make uvm` on the local box **fails fast on purpose** — it hits a `UVM_HOME`
guard, because the root target does not wire the from-source toolchain (that
build OOMs a small box). To actually run it locally you must force the toolchain
*and* have the RAM headroom:

```bash
env -u VERILATOR_ROOT PATH="$HOME/verilator/bin:$PATH" \
  make uvm VERILATOR=$HOME/verilator/bin/verilator \
           UVM_HOME=$HOME/verilator/test_regress/t/uvm
```

Prefer `make lint-uvm` locally and let the full run happen in CI or on a remote
runner.

### 6.3 On a remote runner, driven from your laptop — `make uvm-remote`

This is the ergonomic path: offload the heavy build to the cloud, **stream it
live**, and **attach a controlling terminal on demand**. Same verbs for both
backends, chosen by `RUNNER`:

```bash
# Railway (default) — deploys your CURRENT local tree (uncommitted edits included)
APPLY=1 make uvm-remote

# GitHub Codespaces — runs CS_BRANCH (a Codespace is a git clone; commit+push first)
APPLY=1 make uvm-remote RUNNER=codespace

# then, on demand (add the same RUNNER=):
make uvm-attach            # open a terminal INSIDE the running job
make uvm-remote-logs       # re-stream the run
make uvm-remote-status     # runner + run-session status
APPLY=1 make uvm-remote-down   # tear down / stop billing
```

Key behaviours:

- **Dry-run by default.** `uvm-remote` / `uvm-remote-down` with no `APPLY=1` just
  print the exact cloud commands and provision **nothing** — inspect, then fire
  with `APPLY=1`. (This mirrors the `railway-swarm` safety convention.)
- **Ctrl-C stops *viewing* only** — the job keeps running; reattach any time with
  `uvm-remote-logs` / `uvm-attach`.
- **Railway** (`docker/remote.sh`) uses the prod image, which already has the UVM
  Verilator, and sets `KEEP_ALIVE=1` so the container holds open **after** the
  gate for attach. It **bills until `uvm-remote-down`.** Size the instance ~8 GB
  (a ~6 GB preflight floor fails fast below it). `RAILWAY_SVC=` overrides the
  service.
- **Codespaces** (`docker/codespace.sh`) boots from `Dockerfile.dev` (apt
  Verilator, no UVM), so the first run **bootstraps** the from-source UVM
  Verilator (`make tools TOOLS_HEAVY=1`, ~10 min, cached) and runs `make uvm` in
  a detached `tmux` session that survives disconnects. Defaults to a 16 GB
  `standardLinux32gb` machine; `CS_REPO`/`CS_BRANCH`/`CS_MACHINE`/`CS_NAME`
  override.

Prerequisites: `railway` CLI logged in + a linked project (Railway), or `gh`
logged in with Codespaces enabled (Codespaces).

---

## 7. Post-gate tiers (additive — never fold into the gate)

These sit **outside** the green gate. They never run inside/alongside a timed DV
run, and they never fail the gate:

```bash
make coverage    # [COV] line=NN.N% (+ advisory branch=NN.N%). Set COV_MIN=NN to gate.
make formal      # [FORMAL] <job>: BMC depth N PASSED (SymbiYosys bounded model check)
make metrics     # append ONE DV-metrics row to metrics/metrics.db (advisory)
make dashboard   # regenerate metrics/dashboard.html (self-contained, no CDN)
```

- `make formal` uses apt `yosys` + SymbiYosys + `z3` (still **not** OSS CAD
  Suite); it **skips cleanly with exit 0** if `sby` is absent. Properties live in
  `formal/*_formal.sv` boundary wrappers — `rtl/` is never edited.
- `make metrics METRICS_ARGS=--once-per-sha` is idempotent (a clean tree whose
  sha+env already has a row appends nothing), so a CI job can commit the row back
  safely.

---

## 8. Debugging aids

### 8.1 Waveforms (off-gate)

```bash
make waves     # dump build/waves/test_roundtrip.fst (seeded-random default stimulus)
make wave      # dump + open in GTKWave with dv/waves/default.gtkw (needs a display)
make wave-web  # bundle the dump + vendored viewer into ONE offline .html
make wave-check   # drift-guard: every net path in every committed *.gtkw resolves
```

The dump is a **focused window** (`WAVE_PCLK = 40 + 4*LEN`) so every packet is
visible instead of collapsed into the idle drain; raise `WAVE_PCLK` to see the
drain tail. `make wave-web` is the **Codespaces/browser** path — no desktop app,
no X11 — a single self-contained HTML file.

### 8.2 Packet tracking (opt-in `[PKT]` logs)

```bash
make pyuvm PKT_TRACK=1     # or: make uvm PKT_TRACK=1
```

Adds `[PKT]` lines tracing each flit end-to-end (`DRIVE → TXWORD → RECOVER`, plus
`LOCK`/`SYNCERR`) in **both** TBs. It is zero-sim-time logging (never in the
sacred `run_phase`), so the byte-identical trace is unchanged. Off by default.

### 8.3 A shell inside a running container

```bash
make shell                            # auto-detect: railway -> docker -> local
make shell SHELL_ARGS="railway <svc>" # railway ssh into a deployment
make uvm-shell                        # run the UVM image locally, drop into bash
```

On Railway the gate is a batch job, so deploy with `KEEP_ALIVE=1` (run the gate,
then hold the container open) or `DEBUG_SHELL=1` (skip the gate, hold a shell)
before attaching. `make uvm-remote` sets `KEEP_ALIVE=1` for you.

---

## 9. The git / PR workflow

A few repo-specific rules (also in `CLAUDE.md`):

- **`origin` is SSH and SSH auth typically fails in this env — push over HTTPS:**

  ```bash
  git push https://github.com/markrthomas/ucie2-pipe7-bridge.git <branch>
  ```

- **Never commit on `main`.** Branch off `main` for a PR; a human merges.
- After a merge, sync and clean up:

  ```bash
  git checkout main
  git pull https://github.com/markrthomas/ucie2-pipe7-bridge.git main --ff-only
  git branch -d <merged-branch>
  ```

- Durable knowledge goes in **tracked docs** (`PLAN.md`, `docs/`, `README.md`,
  `CLAUDE.md`) — not a scratch file.

---

## 10. Common recipes (cheat-sheet)

```bash
# Day-to-day green gate
make lint && make pyuvm && make lint-uvm

# Reproduce a CI failure locally with the exact CI toolchain
make pyuvm-ci                     # (or lint-ci / fcov-ci / lint-uvm-ci)

# A longer random round-trip, with packet tracing and a waveform
make pyuvm LEN=64 SEED=random PKT_TRACK=1
make wave  LEN=64

# Run the full UVM gate in the cloud and watch it, without touching your RAM
APPLY=1 make uvm-remote            # Railway; then: make uvm-attach
APPLY=1 make uvm-remote RUNNER=codespace   # or a Codespace

# Post-gate snapshot
make coverage && make formal && make metrics && make dashboard

# Full tidy
make clean
```

---

## 11. Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `make uvm` locally → `Set UVM_HOME to the bundled Verilator UVM dir…` | Expected: the root target doesn't wire the from-source toolchain (it OOMs small boxes). Use `make lint-uvm`, or `make uvm-remote`, or force it per §6.2. |
| `make uvm` (forced) OOMs / hangs | The `--binary` precompiled-header compile needs several GB. Use a remote runner (§6.3) or CI. |
| A gate picks the wrong `verilator`/`python` | oss-cad-suite is shadowing them. The `LOCAL` autodetect normally fixes this; force it with `LOCAL=1`, or reproduce CI with the `-ci` variant. |
| `fatal error: lz4.h: No such file or directory` during a build | The from-source Verilator's FST writer needs `liblz4-dev`. `make waves` deliberately does **not** use the from-source Verilator for this reason; if you hit it elsewhere, `sudo apt-get install liblz4-dev`. |
| `make fcov` fails oddly on the local box | oss-cad's Icarus/Python pollute the env; run `make fcov` (LOCAL mode uses Verilator) or see the local-fcov clean-env note. |
| `make formal` "does nothing" | It skips with exit 0 when `sby` is absent. Install with `make tools` (formal tier). |
| A remote run keeps billing | You left `KEEP_ALIVE`/a codespace up. `APPLY=1 make uvm-remote-down RUNNER=…`. |

---

## Where to go next

- **`PLAN.md`** — the scope, the frozen FDI/PIPE boundary contract, and the
  phased build-out.
- **`docs/verification_plan.md`** — the DV plan in depth.
- **`docs/ucie2_pipe71_spec_crosscheck.md`** — every frozen encoding, cited.
- **`.railway/README.md`** — the Railway batch-job specifics.
- **`make help`** — the authoritative, always-current target list.
