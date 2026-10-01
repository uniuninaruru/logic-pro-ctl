[日本語](AGENTS.md) | [English](AGENTS.en.md)

# AGENTS.md

Rules for agents working in this repo. The full brief is in the project
history; these are the ones that bite.

- Research is an experiment log. Record observations with their source file;
  mark guesses as `Hypothesis` with a confidence. Never promote a guess to fact
  without a recorded experiment (`Research/experiments/TEMPLATE.md`).
- One variable per experiment. Validate a field with several values and
  several tracks before calling it known.
- Only touch the dedicated test project `LogicCLI-Test.logicx`. Never run
  experiments on real music projects.
- Do not modify the Logic binary, disable SIP, break code signatures, or use
  `sudo` without stating why and asking first.
- Product code (Swift, `Sources/`) never depends on `Research/` or `Tools/`.
  Research tooling may be Python.
- CLI: JSON on stdout, diagnostics on stderr. No write without readback;
  report `verified: false` when readback is impossible.
- `Research/raw/` is gitignored; commit curated results only.
- Logic 12.x bundle ID is `com.apple.mobilelogic` and the app name may carry an
  edition suffix ("Logic Pro Creator Studio"). Never hardcode either.
