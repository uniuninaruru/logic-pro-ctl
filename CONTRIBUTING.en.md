[日本語](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

# Pull requests and issues are welcome

`logicctl` is a work in progress for controlling Logic Pro through a CLI and AI agents.
Contributions can range from typo fixes to Swift improvements, live verification, and Ghidra analysis. You can improve documentation, diagrams, and tests without owning Logic Pro.

## Where to start

| Your interests or available environment | Welcome contributions | Starting point |
|---|---|---|
| You found an unclear explanation | Japanese / English documentation, diagrams, and instructions | [README](README.en.md), [specification](docs/specification.en.md) and [architecture](docs/architecture.en.md) |
| You use Swift or Python | Bug fixes, meaningful regression tests, and research tools | `Sources/`, `Tests/`, `Tools/` |
| You own Logic Pro | Reproduction in a dedicated test project and verification on other versions | [Manual validation](docs/manual-validation.en.md) · [Experiment template](Research/experiments/TEMPLATE.en.md) |
| You use Ghidra or analyze protocols | Cross-checking functions and messages, testing unresolved hypotheses | [Research guide](Research/README.md), [roadmap](Research/plans/agent-ready-roadmap.en.md) |

Send a PR directly for small changes. For a large feature or new experiment, an issue describing the goal, scope, and verification method helps coordinate with ongoing work. Draft PRs are welcome, too.

## Sending a PR

1. Fork the repository and create a branch for your change.
2. Focus on one purpose. Separate a documentation fix from a large feature when that makes review easier.
3. Check the changed area and describe the behavior, verification, and remaining limits in the PR.
4. Ask if anything in the review is unclear.

Issues and PRs can be written in Japanese or English. If an existing page has both languages, updating both is appreciated. If translation is difficult, submit one language and mention that in the PR.

## Development environment and checks

macOS 13+ and Swift 5.9+ are required. The current live verification baseline is Logic Pro 12.3.1 / build 6682.

Use `test-all.sh` for all offline checks, or `test.sh` for Swift tests only. Neither command needs Logic Pro to be running.

```sh
./scripts/test-all.sh   # All offline checks
./scripts/test.sh       # Swift tests only
```

`test-all.sh` runs Swift tests, Python unit tests for the research tools, and CLI integration tests against fake daemons. It also builds the debug CLI used by those integration tests.

To check the release CLI, use:

```sh
swift build -c release
python3 Tests/integration/test_cli_backend_compat.py .build/release/logicctl
```

Choose checks relevant to your change, and include the commands and results in the PR. Link and table checks are enough for a documentation-only change. If you could not perform a check requiring Logic Pro, say that it is unverified.

Product code belongs in `Sources/`, checks in `Tests/`, research notes in `Research/`, and research tools in `Tools/`. `Sources/` must not depend on `Research/` or `Tools/`.

## Sharing research findings

**Separate static code evidence from behavior actually observed in Logic.** Mark an unverified interpretation as `Hypothesis`, with its confidence, evidence, and next verification step.

| What you share | Information to include |
|---|---|
| Ghidra analysis | Logic version and build, binary, architecture, SHA-256, function names and addresses, relevant instructions or call evidence |
| Live observations | macOS / Logic versions, initial state, one operation, before / after values, reproduction count, restored state |
| MIDI / protocol interpretations | A minimal anonymized example, direction, observation scope, unresolved questions |

Distinguish the hash of a whole universal binary from the hash of an extracted architecture slice. Analyze a local copy in Ghidra; modifying the installed application is unnecessary.

Run live experiments **only in the dedicated `LogicCLI-Test.logicx` project**. Change one condition at a time and verify multiple values and tracks before assigning a field a confirmed meaning. Do not experiment on production music projects.

`Research/raw/` is excluded from Git. Share curated notes and the smallest reproduction data needed. Anonymize personal names, project names, user paths, network identifiers, and similar details in logs or screenshots. Do not include Logic / Apple application files, binaries, sound libraries, or other third-party assets in a PR.

## Handling operation results

- CLI stdout contains JSON; diagnostics go to stderr.
- Verify writes through independent state readback from Logic. Delivery alone does not justify `verified: true`.
- Use `verified: false` when state cannot be confirmed, and distinguish unknown, unavailable, zero, and off.
- After a timeout, recheck state because the operation may already have run. Do not blindly repeat the same write.

See the [specification](docs/specification.en.md), [track target contract](docs/target-contract.en.md), and [AGENTS.en.md](AGENTS.en.md) for detailed contracts and agent working rules.

## License

This repository uses the [MIT License](LICENSE). Submit code, writing, and data that you have the right to share.
