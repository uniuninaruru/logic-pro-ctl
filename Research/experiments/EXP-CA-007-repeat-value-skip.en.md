[日本語](EXP-CA-007-repeat-value-skip.md) | [English](EXP-CA-007-repeat-value-skip.en.md)

# EXP-CA-007: a repeated CC value is skipped even when the target was moved in between (PLAN-CA-005 T1)

| Item | Value |
|---|---|
| Date | 2026-10-21 00:13–00:14 UTC |
| Logic version | 12.4 (build 6707), pid 7274 |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | New untitled project "名称未設定 6" (user approved; not saved) |
| Initial state | Ballad selected, Channel EQ slot 1, Master Gain 240 / 0.0 dB. Row CC 23 → Master Gain on `logicctl-gen` ([EXP-CA-006](EXP-CA-006-learn-on-new-port.en.md)). **Pickup off** (Settings > Control Surfaces > General, unchecked 00:13:08Z; AX value 0) |
| One operation | Send the same value twice, moving the target with the GUI in between |
| Expected change | PICKUP-CONSUMER-001 F2: a value equal to the stored one is skipped (written before sending, `Research/raw/ca007/prediction-T1.txt`) |
| Repetitions | 1 sequence |

## What Apple's official guide says

- General control-surface settings (lgcp1fe673ef): Pickup mode (turned off here to remove it from the test).

## Observation

| Step | Time (UTC) | Action | Master Gain (AX) |
|---|---|---|---|
| s1 | 00:13:21.896 | `B0 17 60` (96) | 363, +12.3 dB |
| GUI | 00:13:55 | Option-click Master Gain (reset) | 240, 0.0 dB |
| s2 | 00:13:56.477 | `B0 17 60` (96) again | 240, 0.0 dB (**skipped**, as predicted) |
| s3 | 00:13:58.083 | `B0 17 61` (97) | 367, +12.7 dB |

- O1: the second 96 did nothing although the target had moved to 0.0 dB, so the comparison is with the value stored on the assignment, not with the target's current value. 97 was applied at once.
- Pickup was turned back on at 00:14:24Z (AX value 1).
- Raw data (not in Git): `Research/raw/ca007/` (`probe.log`, `T1-*.json`).

## Hypothesis

Hypothesis: with Pickup off, a Scale-mode assignment skips a message whose value equals the last value it stored, regardless of the target's value (F2). Confidence: medium-high (one sequence; matches EXP-CA-004 #1).
Next: repeat with a different parameter class (pan or volume).
