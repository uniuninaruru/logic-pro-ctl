[日本語](EXP-CA-008-row-selection-no-reset.md) | [English](EXP-CA-008-row-selection-no-reset.en.md)

# EXP-CA-008: selecting the row in the Controller Assignments window does not make the next CC be ignored (PLAN-CA-005 T2, prediction failed)

| Item | Value |
|---|---|
| Date | 2026-10-21 00:14–00:15 UTC |
| Logic version | 12.4 (build 6707), pid 7274 |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | New untitled project "名称未設定 6" (not saved) |
| Initial state | Pickup on. Master Gain 367 (+12.7 dB = CC 97), stored value 97. Controller Assignments window open on "(No zone)" |
| One operation | Select the CC 23 row (after first selecting the note-26 row), then send CC 23 |
| Expected change | PICKUP-CONSUMER-001 F4/F6: the first message after `syncSelection:` is ignored once (`Research/raw/ca007/prediction-T2.txt`) |
| Repetitions | 1 sequence (2 controls, 2 test sends) |

## Observation

| Step | Time (UTC) | Action | Master Gain (AX) |
|---|---|---|---|
| prep | 00:14:4x | select the note-26 row (no MIDI) | — |
| c1 | 00:14:53.600 | 95 | 359, +11.9 dB (applied) |
| c2 | 00:14:55.216 | 93 | 351, +11.1 dB (applied) |
| select | 00:15:03 | select the CC 23 row (selection confirmed on screen) | — |
| t1 | 00:15:03.567 | 91 | 344, +10.4 dB (**applied**; predicted ignored) |
| t2 | 00:15:05.178 | 89 | 336, +9.6 dB (applied) |

- O1: the first message after selecting the row was applied. The prediction failed.
- Raw data (not in Git): `Research/raw/ca007/` (`T2-*.json`).

## Hypothesis

Hypothesis: `ControllerAssignmentsController::syncSelection:` is not called by selecting a row in the list; it may sync the window to Logic's track or parameter selection instead. Alternatively the reset in `FUN_00aba7d4` applies only when its 16-bit field matches, which did not hold here. Confidence: low.
Next: change the selected track (or touch another parameter) with the window open, then send CC 23.
