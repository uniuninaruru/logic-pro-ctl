# logicctl

[日本語](README.md) · **English**

**PRs and issues welcome** — Japanese and English are both welcome. [Contribution guide](CONTRIBUTING.en.md).
For hands-on Logic testing, start with the [manual validation procedure](docs/manual-validation.en.md).

CLI (`logicctl`) and daemon (`logicd`) for controlling Logic Pro on macOS
from AI agents. Every command prints one JSON object on stdout; every write
reads Logic's state back and says whether it matched.

```
agent → logicctl → Unix socket → logicd → backend → Logic Pro
                                          ├─ MCU over virtual MIDI   (v0.1, working)
                                          ├─ Private AppleEvent      (play/stop, opt-in; MCU readback)
                                          ├─ Logic Remote            (research)
                                          ├─ Native IPC / XPC        (none found)
                                          └─ Accessibility / CGEvent (research)
```

## Status: v0.1
Tested against Logic Pro 12.3.1 (6682, "Logic Pro Creator Studio") on macOS 27.0;
transcript in `Research/experiments/EXP-CLI-001-v0.1-dod-transcript.txt`.

v0.1 talks to Logic as a Mackie Control surface on a virtual CoreMIDI port
pair named `logicctl-mcu`. Logic detects the port and installs the surface by
itself — no setup in Logic is needed. Readback comes from the surface
feedback Logic sends (LEDs, fader echo, LCD text with dB / pan values).
An explicit `--backend appleevent` selects native play/stop for the validated
Logic 12.3.1 build 6682 profile. Its state verification still uses the persistent
MCU connection owned by `logicd`.

## Build
```sh
swift build -c release
.build/release/logicctl status
```
Requires macOS 13+ and Swift 5.9+. `logicctl` starts `logicd` (from the same
directory, or `$LOGICD_PATH`) on first use; its log is
`~/Library/Logs/logicctl/logicd.log`.

## Commands
```
logicctl status                       daemon, Logic version, surface connection, transport
logicctl state                        transport + selected track + all tracks
logicctl transport play|stop
logicctl transport play|stop --backend appleevent
logicctl transport cycle|click on|off   (LED readback; fake-Logic tests only, live behavior unverified)
logicctl track list
logicctl track get <n>
logicctl track select <n>
logicctl track mute <n> on|off
logicctl track solo <n> on|off
logicctl track arm <n> on|off         (REC LED readback; checked once on the real Logic, EXP-MCU-028)
logicctl track volume <n> <dB|-inf> [--tolerance <dB>]   (default tolerance 0.1)
logicctl track pan <n> <-1…1>         (Logic pan -64…+63 = value × 64)
logicctl daemon stop
logicctl debug mcu <hex>[; <hex>…]   research: raw MCU messages, returns the surface state
```
`--json` is accepted and ignored: output is always JSON.
Help and human-readable messages are Japanese; JSON keys, commands and error
identifiers keep their stable English names. English documentation is retained
alongside the Japanese primary pages.
`--backend mcu|appleevent` is accepted anywhere. Omitting it uses MCU.
AppleEvent supports only `transport play` and `transport stop`; other commands
with that selection return a usage error before contacting the daemon.

Exit status: 0 ok, 1 command failed (including failed verification),
64 usage error. Connection failures currently also exit 1; exit 3 is not used.

### Response
```json
{"ok":true,"verified":true,"command":"track.volume","backend":"mcu",
 "requested":{"track":1,"volume_db":-6},
 "observed":{"track":1,"volume_db":-6,"fader_value":9874}}
```
```json
{"ok":false,"verified":false,"error":"verification_failed",
 "requested":{"track":1,"volume_db":-6.05},"observed":{"track":1,"volume_db":-6.1}}
```
- `verified: true` only when the readback matched `requested`.
- A write that is already satisfied sends nothing and says so in `message`.
- Errors: `invalid_argument`, `usage`, `logic_not_running`,
  `surface_not_connected`, `surface_conflict`, `bank_unknown`, `no_such_track`,
  `verification_failed`, `readback_unavailable`, `daemon_unavailable`.

### Native transport

```sh
.build/release/logicctl transport play --backend appleevent
.build/release/logicctl transport stop --backend appleevent
```

The daemon sends `aUeV/Spt2` with exact 32-bit integer parameters `sPmo=6`
and `sPkc=-3` (play) or `-5` (stop) to the running Logic PID. It does not launch
Logic. It prepares independent MCU readback before sending and waits for
Logic's play/record LEDs afterward. Stop requires both playing and recording
to be off. A matching state already received from Logic is a verified no-op.

The response separates delivery, acknowledgment, and observed state:

```json
{"ok":true,"verified":true,"command":"transport.play",
 "backend":"appleevent","readback_backend":"mcu",
 "requested":{"playing":true},"observed":{"playing":true,"recording":false},
 "result":{"sent":true,"command_id":3,"event_class":"aUeV","event_id":"Spt2",
           "appleevent_send_status":0,"appleevent_reply_received":true,
           "appleevent_reply_error":null,"logic_version":"12.3.1","logic_build":"6682"}}
```

`appleevent_reply_error: null` means the reply omitted that field; it is not
an invented zero. A successful send and valid reply alone cannot make a write
verified. Missing initial LED feedback, a replaced Logic process, or lost
readback prevents verification. A timeout/error reports any trustworthy final
state without retrying the write. Explicit AppleEvent requests never fall
back to MCU writes.

`status.result.capabilities.appleevent_transport` advertises daemon support;
the current Logic version and MCU connection are reported separately. The CLI
checks that capability before sending an AppleEvent write, so an old daemon
cannot ignore the backend field and run the request through MCU. If it returns
`daemon_upgrade_required`, run `logicctl daemon stop` with the new build and
then rerun your command. The new daemon starts automatically.

Additional native errors include `unsupported_logic_version`,
`logic_instance_changed`, `appleevent_permission_denied`, `appleevent_timeout`,
`appleevent_not_handled`, `appleevent_send_failed`, `appleevent_reply_failed`,
`appleevent_invalid_reply`, `no_project`, and `backend_mismatch`.

## Limitations (v0.1)
- Private AppleEvent transport is enabled only for Logic 12.3.1 build 6682.
  It requires MCU feedback; native state reads and native mixer writes remain
  research work. See EXP-AE-002 for the verified CLI integration.
- Track *n* is the *n*-th channel strip in Logic's mixer order, which ends
  with Stereo Out and Master; check `name`. logicd moves the MCU bank to reach
  any strip and re-homes whenever Logic moves the bank itself (EXP-MCU-020).
  After a track is added, deleted or moved, the same number points at another
  track, so a write can carry the name `track list` returned as `--expect-name`
  ([target contract](docs/target-contract.en.md)).
- Only Logic 12.3.1 (6682) on macOS 27.0 has actually been checked; `compatibility`
  in `status` says whether the running pair was ([compatibility](docs/compatibility.en.md)).
- Names come from the MCU LCD: cut to 6 characters, ASCII only
  ("オーディオ 2" shows as "2").
- While any track is soloed, `mute` reads as `null` for tracks whose mute LED
  Logic blinks; mute *writes* are still verified from Logic's LCD message.
- Selecting a track moves record-arm with it when Logic's auto rec-arm is on.
- Volume uses Logic's 0.1 dB display resolution; values in between cannot be
  verified more precisely than that.
- Reads that depend on the LCD wait up to ~3 s after a write for Logic to
  restore the display.
- Do not rely on Logic's Undo to revert logicctl writes. With the default
  Undo History setting no mixer change is undoable; with 「ミキサー」 enabled,
  volume/pan writes are recorded but may coalesce, Undo can land on values
  never requested, and mute is never recorded (EXP-UNDO-001, EXP-UNDO-002).
- Track names on the MCU LCD can be stale: undoing a rename did not update
  them until logicd reconnected (EXP-UNDO-001).
- If Logic's Control Surfaces setup has two Mackie Control units on the same
  port (`logicctl-mcu`, e.g. "Mackie Control #2"), their displays mix and the
  track list cannot be read correctly. `status` shows `mcu.surface_conflict: true`
  and other commands stop with `surface_conflict`. Remove the extra unit, then
  run `logicctl daemon stop` (EXP-MCU-029).

## Understand the system and research

| What you want to read | Starting point |
|---|---|
| Commands, JSON results, and errors | [Specification](docs/specification.en.md) |
| What each component does | [Architecture with diagrams](docs/architecture.en.md) |
| Findings so far and what to investigate next | [Research guide](Research/README.md) (Japanese) |
| The plan for broad agent control | [Research and development roadmap](Research/plans/agent-ready-roadmap.en.md) · [Task dependencies and acceptance criteria](Research/plans/agent-ready-backlog.tsv) (Japanese) |
| Evidence for the connection routes | [Detailed architecture research](Research/architecture.en.md) |
| Live AppleEvent results | [EXP-AE-001](Research/experiments/EXP-AE-001-private-command-dispatch.en.md) · [EXP-AE-002](Research/experiments/EXP-AE-002-cli-backend.en.md) |
| Candidates and limits for native state reads | [SA-AE-STATE-002](Research/static-analysis/SA-AE-STATE-002-native-transport-state.en.md) |

## Development
```sh
./scripts/test.sh        # swift test; also works with Command Line Tools only
python3 Tests/integration/test_cli_backend_compat.py .build/release/logicctl
```
Research lives in `Research/` (start at `Research/architecture.md`);
research tools in `Tools/`. See `AGENTS.md` for the rules.

The [research and development roadmap](Research/plans/agent-ready-roadmap.en.md)
maps the next Ghidra targets, experiments, API contracts, and release gates for
broad agent control. The [22-task backlog](Research/plans/agent-ready-backlog.tsv)
records dependencies and acceptance criteria in Japanese with stable task IDs.

### Private AppleEvent research

The 2026-10-01 investigation identified Logic 12.3.1's explicitly registered
`aUeV/Spt2` handler. `sPmo=6, sPkc=-3` dispatches play; `sPkc=-5` dispatches
stop. Ghidra results were checked against ARM64 instructions and a 14-case
native-send experiment with independent MCU readback. Details, limitations,
and reproduction commands are in
[`EXP-AE-001`](Research/experiments/EXP-AE-001-private-command-dispatch.md).
The CLI and daemon now expose this validated transport path through the
explicit backend option; integration checks and live results are recorded in
[`EXP-AE-002`](Research/experiments/EXP-AE-002-cli-backend.md).
Research tools retain dedicated `LogicCLI-Test.logicx` guards. Ongoing Ghidra
analysis starts from known registrations, selectors, and message routes;
findings and unvalidated candidates are kept in `Research/static-analysis/`.

## PRs and issues are welcome

Contributions can include typo and documentation fixes, Swift changes, tests,
Ghidra analysis, and live verification in a dedicated test project.
You can contribute without owning Logic Pro. Japanese and English are both welcome.
Send small changes as a PR; start an issue for a large feature or experiment.
Draft PRs are welcome, too.

The [contribution guide](CONTRIBUTING.en.md) explains where to start, relevant
checks, and how to share research findings.

## License
MIT. See `LICENSE`.
