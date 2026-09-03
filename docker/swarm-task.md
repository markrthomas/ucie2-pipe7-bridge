Implement **increment 4** of `docs/phase_g_env_enhancements.md` (waves: a
self-contained, no-CDN browser waveform viewer), and nothing beyond it. This is
the LAST Phase G increment.

**Environment notes (read first):**
- You run on a GitHub runner that cloned ONLY this repo — build from the spec, not
  by copying any sibling repo (you do not have it).
- **Your GitHub token CANNOT write `.github/workflows/**`.** If you want any CI
  step, author it as a fenced YAML block in `docs/phase_g_env_enhancements.md`
  under a "### CI step — for maintainer to apply" heading. Touch no file under
  `.github/workflows/`. You MAY edit the `Dockerfile` and `.devcontainer/`.
- **No OSS CAD Suite, and the viewer must be strictly self-contained: no CDN, no
  external fetch, no network at runtime.** Vendor every asset (WASM/JS/CSS/fonts)
  into the repo; the page must render offline by just opening the file.

1. Read `docs/phase_g_env_enhancements.md` (Hard invariants + increment 4) in
   full, plus increment 3's wave flow which just landed (PR #12): `make waves`,
   the `-DWAVES`/`WAVES` dump path in `dv/pyuvm/Makefile`, `dv/waves/`,
   `tools/wave_check.py`. You REUSE those dumps — do NOT add a second dump path.
2. Build **increment 4 only** — ADDITIVE, off-gate:
   - **`make wave-web [TEST=<name>]`** bundles a dumped wave (the SAME `-DWAVES`
     FST/VCD from increment 3) plus a **no-CDN, all-inlined** HTML/JS (or WASM)
     viewer into a **single openable file** under `build/waves/` (e.g. a vendored
     Surfer WASM build, or a small self-contained vcd.js viewer — vendor the
     assets into the repo, never fetch at runtime). Opening that one file in a
     browser must render the waveform **offline**, with no desktop app / X11 (the
     maintainer's Codespace/browser workflow).
   - Reuse increment 3's dump exactly — **do not add a second dump path or perturb
     the gate**. The gate builds (`lint`/`pyuvm`/`fcov`/`uvm`/`trace-compare`)
     stay wave-free and **byte-identical**.
   - If a full WASM viewer is too heavy for one increment, ship a **smaller
     self-contained VCD viewer** instead and **say so honestly** in the docs — a
     working small viewer beats a half-vendored WASM one.
   - Vendored assets live in the repo (e.g. `dv/waves/viewer/` or `tools/`); the
     generated bundle under `build/waves/` is git-ignored. `[WAVES] …` banner.
3. Additive only. Do NOT fold anything into the gate, do not touch RTL, the trace
   emitters (`dv/uvm/sv/ucie2_pipe7_uvm_pkg.sv`, `dv/pyuvm/test_roundtrip.py`), or
   the fixed clock/reset/stimulus schedule. The viewer is a dev/debug artifact,
   entirely off the gate.
4. Verify locally what this host can: dispatch dv-env-testers for `lint` and
   `pyuvm`; run `make lint` (`[lint] RTL OK`) and `make pyuvm` (RoundtripTest /
   3-way PASS) and confirm they are **unchanged and equally fast**. Run
   `make waves` then `make wave-web`, and confirm a single self-contained file is
   produced under `build/waves/`. **Prove no-CDN/offline**: grep the generated
   file (and any vendored viewer source) for `http`, `https`, `<script src=`,
   `@import`, `url(`, `fetch(`, `XMLHttpRequest`, `WebSocket` and report the hit
   counts — external hosts must be **zero** (data: URIs and inline blobs are fine).
   Capture the `[WAVES]` banner. (Rendering is a browser action — say that's
   manual; the grep + file-produced check is the automatable proof.)
5. Document it: `README.md` ("Waveform debugging" → browser viewer) / `PLAN.md` /
   `docs` + `make help`; mark increment 4 "LANDED" in
   `docs/phase_g_env_enhancements.md` with the real banners, and note honestly if
   you shipped the smaller VCD viewer rather than full WASM. This closes Phase G.
6. Branch `swarm/phaseG-wave-web`, commit (co-author + Claude-Session trailers),
   push, and open a PR titled for Phase G increment 4. A human merges. There is no
   increment 5 — do not invent further work.
7. Report: what you added (file:line), how the viewer stays self-contained/offline
   (the grep proof, hit counts), that it reuses increment 3's dumps with no gate
   impact, the `make wave-web` `[WAVES]` banner, the local `[lint]`/pyuvm banners
   (unchanged), and the PR URL.

Never commit on main. Make the smallest change that satisfies increment 4; if it
would require perturbing the sacred gate or the trace emitters, report it instead
of guessing.
