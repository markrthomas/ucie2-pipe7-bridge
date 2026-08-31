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
