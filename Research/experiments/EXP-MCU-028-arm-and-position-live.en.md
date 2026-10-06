[日本語](EXP-MCU-028-arm-and-position-live.md) | [English](EXP-MCU-028-arm-and-position-live.en.md)

# EXP-MCU-028: check `track arm` and `state`'s `position` on the real Logic

| Item | Value |
|---|---|
| Date and time | 2026-10-07 01:03 to 01:10 (JST) |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0, arm64 |
| Test project | LogicCLI-Test.logicx (window title "LogicCLI-Test - トラック" checked on screen; while another song was open earlier, nothing was done) |
| Initial state | 8 strips (Piano, Synth, Ballad, Trk08, Audio, Amped Up, Bass, Trk10). Stopped. Ballad (3) selected and record-enabled automatically (`rec_armed: true`) |
| The one operation | Record-enable Piano (1) with the MCU REC button, then turn it off |
| Expected change | Only Piano is armed, and it returns to its state when turned off |
| Repetitions | 1 |
| Approval | The user said "全て許可" (all allowed) directly in this chat |

> **Correction (2026-10-07, [EXP-MCU-029](EXP-MCU-029-two-units-on-one-port.en.md)):** during this experiment Logic had **two** Mackie Control units on the same port ("Mackie Control #2"). The song has **14 strips** (outputs and Master included), and `state`'s "8 strips, complete" was **only the 8 that the first unit shows** (the second unit shows the rest, so the bank did not move and the scan took that for the end). Read "8 strips" below that way. The arm result holds because Piano was the first strip of the first unit (`--expect-name Piano` matched the LCD name and the lit R was checked on screen). But the two units use the same REC LED numbers, so the evidence travelled on a channel shared with the second unit.

## Observations

- `logicctl track arm 1 on --expect-name Piano` → `ok: true`, `verified: true`, `observed.rec_armed: true`. Piano's R on screen **blinked red** (a screenshot can catch the off phase of the blink, so three were taken).
- `logicctl track arm 1 off --expect-name Piano` → `verified: true`. The same `off` again → verified without a press ("already as requested; nothing sent").
- **An unexpected side effect**: when Piano was armed, **the automatic record-enable of the selected track, Ballad, went off** (`track get 3` gave `rec_armed: false`). Turning Piano off did not bring it back.
- Restoring: moving the selection to Synth and back to Ballad re-armed Ballad automatically. The final `logicctl state` matched the baseline on all 8 strips (volume, pan, mute, solo, record-enable, selection).
- `state`'s `position` while stopped: `{"display": "  1 2 3226", "mode": "beats", "bar": 1, "beat": 2, "division": 3, "tick": 226}`, matching Logic's time display "1 2". This is the second real value (the first was `  1 3 2 29` in the EXP-MCU-024 log).
- The list did not include the outputs and Master this time (because of the second unit; see the correction above), so "a strip that cannot be armed fails verification" was not checked. No audible playback at night, so `position` while playing is unchecked.
- Nothing was saved. Raw records: `Research/raw/live-arm/` (not tracked by Git).

## Hypothesis

Hypothesis: **arming another track through the MCU makes Logic drop the automatic record-enable of the selected track.**
Confidence: medium (once; software instruments only).
Evidence: the observation above.
Counter-example: it does not happen with audio tracks, or it is not specific to the MCU path.
Next experiment: compare with arming Piano by its R button on screen.

For the product: `track arm` does not necessarily change only the named track. `verified: true` means the named track's REC LED was checked; **it does not check that no other track's record-enable changed**. The specification says so.
