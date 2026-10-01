# logicctl

CLI (`logicctl`) and daemon (`logicd`) for controlling Logic Pro on macOS
from AI agents. Every command prints one JSON object on stdout; every write
reads Logic's state back and says whether it matched.

```
agent → logicctl → Unix socket → logicd → backend → Logic Pro
                                          ├─ MCU over virtual MIDI   (v0.1, working)
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
logicctl track list
logicctl track get <n>
logicctl track select <n>
logicctl track mute <n> on|off
logicctl track solo <n> on|off
logicctl track volume <n> <dB|-inf> [--tolerance <dB>]   (default tolerance 0.1)
logicctl track pan <n> <-1…1>         (Logic pan -64…+63 = value × 64)
logicctl daemon stop
```
`--json` is accepted and ignored: output is always JSON.

Exit status: 0 ok, 1 command failed (including failed verification),
3 daemon unavailable, 64 usage error.

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
  `surface_not_connected`, `track_out_of_bank`, `no_such_track`,
  `verification_failed`, `readback_unavailable`, `daemon_unavailable`.

## Limitations (v0.1)
- Tracks 1–8 only (first MCU bank). Track *n* is MCU strip *n* in Logic's
  mixer order, which also includes Stereo Out and Master strips; check `name`.
- Names come from the MCU LCD and are cut to 6 characters.
- While any track is soloed, `mute` reads as `null` for tracks whose mute LED
  Logic blinks; mute *writes* are still verified from Logic's LCD message.
- Selecting a track moves record-arm with it when Logic's auto rec-arm is on.
- Volume uses Logic's 0.1 dB display resolution; values in between cannot be
  verified more precisely than that.
- Reads that depend on the LCD wait up to ~3 s after a write for Logic to
  restore the display.
- Whether these writes add Undo steps is not verified yet.

## Development
```sh
./scripts/test.sh        # swift test; also works with Command Line Tools only
```
Research lives in `Research/` (start at `Research/architecture.md`);
research tools in `Tools/`. See `AGENTS.md` for the rules.

## License
MIT. See `LICENSE`.
