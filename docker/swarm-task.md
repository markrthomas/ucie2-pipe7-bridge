Implement **increment 3** of `docs/phase_f_env_enhancements.md` (formal /
SymbiYosys), and nothing beyond it.

1. Read `docs/phase_f_env_enhancements.md` in full — honor its Hard invariants
   (the byte-identical cross-check is sacred; new tiers are additive, behind their
   own make target, OUTSIDE the existing gate; **no OSS CAD Suite** — for formal
   use a from-source SymbiYosys/yosys, NOT oss-cad-suite) — then build
   **increment 3 only**: a `make formal` target that runs a SymbiYosys BMC on a
   tractable block or two (the Gen5 framer/deframer gearbox, and/or the
   msgbus/ctrl FSM). Prove the FLAGGED-safe properties: no illegal FSM state,
   gearbox sync legality. Print a `[FORMAL] … PASSED` banner.
2. Additive only. `make formal` is a NEW target; it MUST NOT be folded into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`, must not touch the RTL
   behavior, the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`,
   `dv/pyuvm/test_roundtrip.py`), the fixed clock/reset/stimulus schedule, or any
   existing gate recipe. The formal properties live in their own `.sv`/`.sby`
   files (a bind or a small formal wrapper) — no behavioral RTL edits. If the
   proof needs its own build/work dir, use a separate one.
3. Formal is likely CI/Railway-only (from-source yosys+sby is heavy and this host
   must not depend on oss-cad-suite). Have the infra-agent install yosys+sby from
   source in the reproducible env (Dockerfile / CI) and add a CI step that runs
   `make formal` **after** the existing gate (never inside a timed DV run), and
   confirm the workflow still loads. Document the tool install. On this host,
   verify what you can: dispatch dv-env-testers for `lint` and `pyuvm`; run
   `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the RoundtripTest
   / 3-way cross-check PASS) yourself and confirm they are unchanged. If `sby`
   isn't available locally, `make formal` should degrade gracefully (skip with a
   clear message, non-fatal) so the local gate stays green.
4. Document it: `README.md` / `PLAN.md` / `docs` + a `make help` line. Name the
   block(s) proved and the properties. Keep claims honest — say where the proof
   actually ran (CI/Railway), and mark any property as bounded (BMC depth) rather
   than unbounded if that's what it is.
5. Branch `swarm/phaseF-formal`, commit (co-author + Claude-Session trailers),
   push, and open a PR titled for increment 3. A human merges. Increment 4
   (metrics + dashboard) is a separate later run — do not start it.
6. Report: what you added (file:line), which block(s)/properties are proved and
   the `[FORMAL]` banner, where the proof ran, the local `[lint]`/pyuvm banners
   (unchanged), and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 3; if the
proof would require perturbing the sacred gate, the trace emitters, or RTL
behavior, report it for a human instead of guessing.
