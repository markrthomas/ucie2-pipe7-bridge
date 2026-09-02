# EDA Playground bundle

Paste-ready copies of the UCIe2→PIPE7 bridge DUT + its SV UVM testbench for
[EDA Playground](https://edaplayground.com), so the whole environment can be run
in a browser with no local toolchain.

**These files are GENERATED — do not edit them.** The source of truth is
`rtl/*.sv` + `dv/uvm/sv/*`. Regenerate with `make eda-playground`; CI/`make
eda-check` fails if a committed copy is stale.

| File | EDA Playground pane |
|------|---------------------|
| `design.sv` | **Design** — all of `rtl/` (package first). |
| `testbench.sv` | **Testbench** — bound SVA + interface + the whole UVM package (all classes inlined) + the `tb_ucie2_pipe7` top. |
| `ucie2_pipe7_bridge_top.sv` | A single all-in-one file (design + testbench concatenated) if you prefer one pane. |

The generator flattens every project `` `include "<subdir>/…sv" `` in the UVM
package inline, so the bundle needs no include search path. `` `include
"uvm_macros.svh" `` is left in place — EDA Playground's selected UVM provides it.

## How to run

1. New playground → paste `design.sv` into **Design**, `testbench.sv` into
   **Testbench** (or the all-in-one file into either pane and leave the other
   empty).
2. Pick a **UVM-capable simulator** (e.g. a Siemens/Cadence/Aldec tool) and a
   **UVM** version in the tool options.
3. Tool options: enable SystemVerilog + assertions; **Run options:**
   `+UVM_NO_RELNOTES` (top module is `tb_ucie2_pipe7`, picked up automatically).
4. Run. Expect UVM elaboration then, from the scoreboard:
   `UVM_INFO ... [SB] roundtrip: 8 driven, tx 13 words, recovered 8`
   with `UVM_ERROR : 0` / `UVM_FATAL : 0`.

## Scope / honesty

This bundle is a **portability/demo artifact**. It is **not** part of the repo's
sacred gate and **cannot** run `tools/trace_compare.py` — the byte-identical
PyUVM↔UVM cross-check runs only in CI (`make uvm` + `make trace-compare`). Use
this to explore or share the environment interactively; use the CI gate for
sign-off. It is validated locally only by elaboration (`make eda-check` for drift
+ a Verilator lint of the all-in-one); running it in EDA Playground is a manual
check.
