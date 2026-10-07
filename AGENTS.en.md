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

## Highest research priority: GUI to internal route

- Pick a visible operation; record target, conditions and before/after changes,
  then map it to command IDs, actions, selectors and functions. Decompile only
  functions relevant to that operation.
- For right-click menus, record cursor hit zone, target type, region type and
  selection before/after. Capture labels, enabled states and observed order;
  never identify an operation or feature by a fixed menu index.
- Prioritize generic MIDI key-command/parameter assignments and feedback,
  Apple Loops, Session Players and Pattern Regions. Candidate IDs or function
  names alone do not prove applicability or effects.
- Claude leads GUI/live observations; Codex matches observations to internal
  routes. Give each other concrete next tasks; share file ownership, GUI/build/
  shared-Ghidra use, results, usage limits and handoffs. Adjust roles to the
  latest human instructions and each other's situation.
- When GUI is unavailable, analyze existing observations or do independent
  offline work. Mark unobserved operations pending; do not replace observation
  with indiscriminate expansion of candidate function bodies.

## Keep work and token use bounded

- Read changes only. Use `python3 Tools/research-scripts/board_new.py --reader codex`
  (`claude` for Claude) for up to 1000 unread characters; continue if more remain.
- Save large logs/JSON to files. Aim for 1200 tokens per routine tool output and
  10 lines per agent report; expand when evidence or failures require it.
- Run affected tests. Batch full suites once for shared contracts, dependency
  changes or release milestones. Docs need diff/link/evidence checks only.
- Reuse unchanged sources/conditions/hash checks. Recheck new claims, changes,
  failures and concerns; do not duplicate the same evidence across artifacts.
- Batch small edits directly. Delegate concrete independent work with minimal
  context; omit full-history forks, multiple routine reviews and unchanged-status
  reports. Prioritize independent reproduction of important bugs.
- Use compact English, IDs and structured data internally; explain to the user in Japanese. New research notes may use canonical English evidence with a short Japanese summary.
