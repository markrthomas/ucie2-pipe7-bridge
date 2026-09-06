# Railway configuration

This project defines its Railway infrastructure in code: `.railway/railway.ts`.

It runs the SV UVM-on-Verilator gate as a **batch / run-to-completion job** (no
listening port): the root `Dockerfile` builds UVM-capable Verilator from source,
and the container entrypoint runs `make uvm` (gen-vectors + lint + the `--binary`
build+run — the same seeded-random gate CI runs), exiting with the gate's status
(0 = green). `restartPolicyType: "NEVER"` is correct for a gate that exits 0 — a
normal always-on service that exits 0 is flagged "crashed".

The `--binary` UVM build needs ~6 GB+ RAM (the entrypoint preflights and fails
fast below the floor). Use a Railway instance with ~8 GB.

## Common commands

```bash
npm install railway                 # SDK (from repo root)
railway config plan                 # safe: preview, no changes
railway config apply                # previews, then asks before applying
railway config apply --yes          # non-interactive apply
```

- `railway config plan` never changes Railway. `apply` asks first unless `--yes`.
- CI should pin a plan (`railway config plan --out railway-plan.json`) and apply
  that file on merge.

## Run `make uvm` from your laptop (offload the heavy build to Railway)

The local box OOMs the `--binary` UVM build, but Railway's prod image already has
the from-source UVM Verilator and runs `make uvm`. The Makefile front-doors deploy
the **current working tree** (uncommitted edits included), stream the run, and let
you attach a controlling terminal on demand:

```bash
APPLY=1 make uvm-remote      # deploy current tree + run `make uvm`, stream the run
make uvm-attach              # open a terminal in the running container (railway ssh)
make uvm-remote-logs         # re-stream the deployment logs
make uvm-remote-status       # project / service / recent-log status
APPLY=1 make uvm-remote-down # tear the deployment down (stops billing)
```

`make uvm-remote` is **dry-run by default** (prints the exact `railway` commands,
provisions nothing); `APPLY=1` executes. It sets `KEEP_ALIVE=1` so the container
stays up **after** the gate finishes — that is what makes attach-on-demand work,
and it bills until `make uvm-remote-down`. Size the instance at ~8 GB (below the
~6 GB preflight floor the run fails fast). `RAILWAY_SVC=` overrides the service
name. Logic: `docker/remote.sh` (+ `docker/shell.sh` for the attach).

Ctrl-C during a stream stops **viewing only** — the job keeps running; reattach
with `make uvm-remote-logs` or `make uvm-attach`.

## Getting a shell in the running container

The gate exits when it finishes, so there is normally nothing to attach to. To keep
the container up and open a terminal:

```bash
railway variables set KEEP_ALIVE=1   # run the gate, then hold the container open
# or:  railway variables set DEBUG_SHELL=1   # skip the gate, hold a shell open
railway up                            # (re)deploy with the variable set
railway ssh                           # attach — same as: make shell SHELL_ARGS=railway
```

`KEEP_ALIVE` / `DEBUG_SHELL` are declared in `railway.ts` (`preserve()`) and read by
`docker/entrypoint.sh`. Inside, the toolchain is ready (`VERILATOR`/`UVM_HOME` set):
`cd /work && make lint-uvm` (or the full `make uvm`). Unset the variable and redeploy
to return to a normal run-to-completion gate.
