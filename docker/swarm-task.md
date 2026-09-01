Implement **increment 1** of `docs/phase_f_env_enhancements.md` (bound SVA), and
nothing beyond it.

1. Read `docs/phase_f_env_enhancements.md` in full — honor its Hard invariants
   (the byte-identical cross-check is sacred; new tiers are additive/behind their
   own make target; no OSS CAD Suite) — then build **increment 1 only**: a
   bind-based SVA module on the `ucie2_pipe7_bridge` boundary asserting the safe
   always-true properties listed there. No RTL logic edits — assertions + a bind.
2. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   (if a UVM Verilator is present) `uvm` (elaborate); run `make lint` and
   `make lint-uvm …` yourself. Confirm `[lint] RTL OK` and
   `[lint-uvm] SV UVM env elaborates OK`. Have the infra-agent confirm CI still
   installs/loads the SVA sources.
3. Do NOT change the trace emitters, the fixed clock/reset/stimulus schedule, or
   any existing gate target. The authoritative `--binary` UVM run (which now also
   checks the assertions) + byte-identical `trace_compare` run in CI on your PR.
4. Branch `swarm/phaseF-bound-sva`, commit (co-author + Claude-Session trailers),
   push, and open a PR titled for increment 1. A human merges. Increments 2–4 are
   separate later runs — do not start them.
5. Report: what you added (file:line), the local banners, and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 1; if a
property is ambiguous or would need an RTL change, report it for a human instead
of guessing.
