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

## Keep work and token use bounded

- Read changes and new messages after the first read. Narrow searches to relevant
  files and lines. Save large logs, JSON and hash inventories to files; return
  findings, counts and failures in the conversation.
- Run affected tests for ordinary code changes. Batch a full suite once for
  changes to shared contracts or dependencies, or at a publication milestone.
  Documentation-only changes need diff, link and evidence checks, not builds or
  full test suites.
- Share and reuse tests, analysis and reviews for unchanged sources and conditions.
  Repeat when changes, failures or unresolved concerns justify it. Matching hashes
  of previously checked binaries and evidence do not require unrelated full
  reanalysis. Verify the evidence needed for each new claim.
- Delegate concrete independent tasks with only the context, file ownership and
  short result they need. Avoid full-history forks and multiple reviews for routine
  edits; prioritize independent reproduction of important bugs.
