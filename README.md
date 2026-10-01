# logicctl

CLI (`logicctl`) and daemon (`logicd`) for controlling Logic Pro on macOS
from AI agents, with JSON output and verify-after-write.

```
agent → logicctl → Unix socket → logicd → backend
                                          ├─ Native IPC / XPC
                                          ├─ Logic Remote
                                          ├─ MCU / CoreMIDI
                                          └─ Accessibility / CGEvent
```

## Status
Scaffold only. Phase A (external surface discovery) has not been run.

## Phase A
On the Mac, with Logic Pro running:

```sh
./scripts/discover.sh
```

Output goes to `Research/raw/` (gitignored). Summarize findings in
`Research/architecture.md`.

## Build
```sh
swift build
swift test
```
Requires macOS 13+ and Swift 5.9+.

## License
MIT. See `LICENSE`.
