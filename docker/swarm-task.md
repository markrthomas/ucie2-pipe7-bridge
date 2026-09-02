Implement **increment 2** of `docs/phase_f_env_enhancements.md` (line-coverage
gate), and nothing beyond it.

1. Read `docs/phase_f_env_enhancements.md` in full — honor its Hard invariants
   (the byte-identical cross-check is sacred; new tiers are additive, behind their
   own make target, OUTSIDE the existing gate; no OSS CAD Suite) — then build
   **increment 2 only**: a `make coverage` target that does a Verilator
   `--coverage` build of the **directed round-trip** and emits a coverage report
   plus an overall line-coverage %. Print a `[COV] line=NN.N%` banner. Keep the
   floor **advisory** (report-only) for this PR; do not fail the build on a
   threshold yet — note in docs that a `>= NN%` gate is set once the baseline is
   known.
2. Additive only. `make coverage` is a NEW target; it MUST NOT be folded into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`, must not touch the trace emitters
   (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`, `dv/pyuvm/test_roundtrip.py`), the fixed
   clock/reset/stimulus schedule, or any existing gate recipe. Do not perturb the
   `--coverage`-free builds. If coverage needs its own obj dir, use a separate one.
3. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the
   RoundtripTest / 3-way cross-check PASS) yourself and confirm they are unchanged.
   Run `make coverage` and capture the `[COV] line=NN.N%` banner it prints. Have
   the infra-agent add a CI step that runs `make coverage` **after** the existing
   gate (never inside a timed DV run) and confirm the workflow still loads.
4. Document it: `README.md` / `PLAN.md` / `docs` + a `make help` line. Keep
   measured-vs-target coverage numbers honest (report the real baseline %).
5. Branch `swarm/phaseF-coverage-gate`, commit (co-author + Claude-Session
   trailers), push, and open a PR titled for increment 2. A human merges.
   Increments 3–4 are separate later runs — do not start them.
6. Report: what you added (file:line), the `[COV]` baseline %, the local
   `[lint]`/pyuvm banners (unchanged), and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 2; if the
coverage build would require perturbing the sacred gate or the trace emitters,
report it for a human instead of guessing.
