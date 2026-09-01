Finalize the ucie2-pipe7-bridge DV work and keep the gate green.

1. Run and review every runnable DV tier by dispatching one dv-env-tester each,
   in parallel (respect HOST CAPACITY): `lint`, `fcov`, and — where the toolchain
   is present — `pyuvm` and `uvm` (elaborate-only).
2. For any tier that fails, make the minimal fix in the RTL/TB and re-test that
   tier until it is green.
3. Have the infra-agent confirm the Docker image builds and the CI / Railway /
   prebuild config is sound; apply any minimal infra fix.
4. Run the local gate yourself: `make lint && make fcov FCOV_SIM=icarus` (and
   `make pyuvm`, `make lint-uvm …` where those tools are present) and confirm the
   banners.
5. If — and only if — the gate is green, create a `swarm/…` branch, commit your
   changes (with the co-author + session trailers), push, and open a PR. A human
   merges; CI (uvm-verilator.yml) validates the authoritative `--binary` UVM +
   byte-identical `trace_compare` on the PR.
6. Report a concise summary: per-tier results, the fixes you made (file:line), the
   gate result, and the PR URL.

Do not push to or commit on main. Do not perturb the per-cycle trace emitters or
the fixed clock/reset/stimulus schedule (the cross-check must stay byte-identical).
Make the smallest change that fixes each problem; if a fix is risky or ambiguous,
report it for a human instead of guessing.
