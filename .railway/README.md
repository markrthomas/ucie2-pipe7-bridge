# Railway configuration

This project defines its Railway infrastructure in code: `.railway/railway.ts`.

It runs the SV UVM-on-Verilator gate as a **batch / run-to-completion job** (no
listening port): the root `Dockerfile` builds UVM-capable Verilator from source,
and the container entrypoint runs `make -C dv/uvm/vlt ci`, exiting with the gate's
status (0 = green). `restartPolicyType: "NEVER"` is correct for a gate that exits
0 — a normal always-on service that exits 0 is flagged "crashed".

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
`cd /work && make -C dv/uvm/vlt lint`. Unset the variable and redeploy to return to a
normal run-to-completion gate.
