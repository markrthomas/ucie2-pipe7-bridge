Implement **increment 3** of `docs/phase_f_env_enhancements.md` (formal /
SymbiYosys), and nothing beyond it.

**The formal toolchain is ALREADY INSTALLED in your environment** — `yosys` (apt),
`sby` (SymbiYosys from YosysHQ/sby), and `z3` are on PATH. Do NOT build any
toolchain from source, and do NOT spend time compiling yosys/sby — that is what
timed out the previous attempt. Just author the formal setup and RUN it to verify.
This project must not depend on OSS CAD Suite; apt yosys + SymbiYosys is fine.

1. Read `docs/phase_f_env_enhancements.md` in full — honor its Hard invariants
   (the byte-identical cross-check is sacred; new tiers are additive, behind their
   own make target, OUTSIDE the existing gate) — then build **increment 3 only**:
   a `make formal` target that runs a SymbiYosys BMC on a tractable block or two
   (the Gen5 framer/deframer gearbox, and/or the msgbus/ctrl FSM). Prove the
   FLAGGED-safe properties: no illegal FSM state, gearbox sync legality. Print a
   `[FORMAL] <block>: BMC depth N PASSED` banner (say "BMC depth N", i.e. bounded,
   not "proven unbounded", unless you actually run an unbounded proof).
2. Author only these, no behavioral RTL edits:
   - the formal properties as a small formal wrapper or `bind` module
     (`.sv`/`.svh`) — safe always-true assertions on the chosen block(s);
   - the SymbiYosys `.sby` script(s) (bmc mode, `z3` solver, `read -formal`);
   - a `make formal` target that invokes `sby` and prints the `[FORMAL]` banner.
     It MUST degrade gracefully: if `command -v sby` is empty, print a clear skip
     message and exit 0 (so a host without sby stays green). In CI it IS present,
     so it actually runs and must PASS.
3. Additive only. `make formal` is a NEW target; it MUST NOT be folded into
   `lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`/`coverage`, must not touch RTL
   behavior, the trace emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`,
   `dv/pyuvm/test_roundtrip.py`), the fixed clock/reset/stimulus schedule, or any
   existing gate recipe. Use a separate work dir for the proof.
4. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (expect `[lint] RTL OK`) and `make pyuvm` (expect the
   RoundtripTest / 3-way cross-check PASS) yourself and confirm they are unchanged.
   Then run `make formal` (yosys/sby ARE installed here) and capture the `[FORMAL]`
   banner — it must PASS.
5. Have the infra-agent make the reproducible envs carry the formal tools and
   validate the proof, WITHOUT any from-source toolchain build:
   - `Dockerfile` (runtime stage): `apt-get install -y yosys` (z3 is already
     there) and install SymbiYosys via `git clone --depth 1
     https://github.com/YosysHQ/sby && make -C sby install`. Not oss-cad-suite.
   - `.github/workflows/uvm-verilator.yml`: install the same formal tools (yosys +
     SymbiYosys; z3 already installed at the "Put Verilator on PATH" step) and add
     a **post-gate** `make formal` step AFTER `trace-compare` + its artifact
     upload (mirror the existing `make coverage` advisory step; formal must PASS so
     it need not be `continue-on-error`, but keep it after the sacred gate).
   Confirm both workflows still parse.
6. Document it: `README.md` / `PLAN.md` / `docs` + a `make help` line. Name the
   block(s) proved and the properties; say the proof runs in CI (and Railway) and
   is bounded (BMC depth). Update `docs/phase_f_env_enhancements.md` increment 3 to
   "LANDED" with the real banner, like increments 1-2.
7. Branch `swarm/phaseF-formal`, commit (co-author + Claude-Session trailers),
   push, and open a PR titled for increment 3. A human merges. Increment 4
   (metrics + dashboard) is a separate later run — do not start it.
8. Report: what you added (file:line), the block(s)/properties proved and the
   `[FORMAL]` banner, the local `[lint]`/pyuvm banners (unchanged), and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 3; if the
proof would require perturbing the sacred gate, the trace emitters, or RTL
behavior, report it for a human instead of guessing.
