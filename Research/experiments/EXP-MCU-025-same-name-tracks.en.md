[日本語](EXP-MCU-025-same-name-tracks.md) | [English](EXP-MCU-025-same-name-tracks.en.md)

# EXP-MCU-025: How `name_unique` and `--expect-name` behave when two tracks share a name

| Item | Value |
|---|---|
| Date | 2026-10-05 |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (12 strips). Not saved |
| Tools | `logicctl track list`, `track mute --expect-name`, renaming in Logic's track header |
| Initial state | All track names differ (`name_unique` is `true` everywhere). No mute or solo |
| One operation | Rename track 7 from `Trk07` to `Trk06` (the name of track 6) and commit. Nothing else changes |
| Expected change | Tracks 6 and 7 display the same name, and both `identity.name_unique` become `false` |
| Repetitions | 1 (change → check → restore) |

## Observations

| Step | Observation |
|---|---|
| Before | `track list` (complete): all 12 strips `name_unique: true` |
| LCD after (bank not moved) | `Trk05  Trk06  Trk06  Trk08  Trk09  Trk10  St Out Master ` |
| `track list` after | Complete. Tracks 6 and 7 both `name: "Trk06"`, **both `name_unique: false`**. The others `true` |
| `track mute 7 on --expect-name Trk07` | `target_mismatch` (track 7 now displays `Trk06`). Nothing sent |
| `track mute 7 on --expect-name Trk06` | **Succeeds**, `verified: true`. Only track 7 was muted (checked in the list) |
| Unmute and rename back to `Trk07` | `track list`: all 12 strips `name_unique: true`, nothing muted |

- Typing a name alone did not change the name in Logic. It changed after double-clicking the name field to enter edit mode, typing, and committing with a click on empty space (behaviour of the input tool).

## Hypothesis

Hypothesis: two tracks that display the same name cannot be told apart by `--expect-name`. `name_unique: false` says so in advance.
Confidence: high (both the list's judgement and the behaviour of the check were confirmed on the real Logic).
Evidence: the table above. It also agrees with the unit tests (`theListMarksDisplayedNamesThatAreNotUnique`, `aNameCheckCannotTellTwoTracksWithTheSameDisplayedNameApart`).
Counterexamples: none.
Not verified: swapping two tracks with the same name (a reorder could not be produced), and three or more tracks with the same name.

## Consequence for logicctl

- When tracks share a name, `--expect-name` only guarantees that "the name at that position is as expected". It cannot tell which `Trk06` it is.
- `--expect-session` only confirms the **connection generation**. It cannot detect two same-named tracks being swapped inside one connection, so the identity of a same-named track cannot be guaranteed by the current contract.
- For a track whose `identity.name_unique` is `false`, an agent has to write right after choosing the position, or arrange a check other than the name (a person's confirmation, for example). It must not rely on the name-and-position check alone.
- No change in behaviour. The "not guaranteed" item of the contract now says it was confirmed on the real Logic.
