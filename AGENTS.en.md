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
