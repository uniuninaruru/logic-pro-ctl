[日本語](EXP-CA-009-plugin-replacement-target.md) | [English](EXP-CA-009-plugin-replacement-target.en.md)

# EXP-CA-009: which plug-in does CC 23 move after the plug-in is replaced, re-created or duplicated? (PLAN-CA-005 T3)

| Item | Value |
|---|---|
| Date | 2026-10-21 00:16–00:25 UTC |
| Logic version | 12.4 (build 6707), pid 7274 |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | New untitled project "名称未設定 6" (not saved) |
| Initial state | Ballad: Channel EQ (preset "カスタム"), ChromaVerb, ChromaGlow. Master Gain 240 / 0.0 dB; all 26 sliders saved (`T3-baseline.json`). Pickup on. Row CC 23 → Master Gain on `logicctl-gen`, selected track, saved descriptor IDs 0x454d4147 / 0 / 0xec, ordinal 0, no pin (+0x1a0 empty) |
| One operation per sub-test | One change to the channel strip's plug-ins, then CC 23 sends, read by Accessibility |
| Expected change | [ASSIGN-IDENTITY-001](../notes/assignment-identity-callbacks-001.en.md) I6 + AI071–AI075: the target is the first plug-in, in slot order, whose three IDs equal the saved ones (predictions written before each step in `Research/raw/ca007/prediction-T3*.txt`) |
| Repetitions | 5 sub-tests |

## What Apple's official guide says

- Add, remove, move and copy plug-ins (lgcpbc218a22, guide 12.3, checked 2026-10-21): replace through the arrows that appear on the right of a slot; "No Plug-in" removes; click an empty slot to add; Option-click a slot bypasses it (avoided); plug-in edits can be undone.

## Observation

| Test | Change (UTC) | CC 23 sent | Result (AX) | Prediction |
|---|---|---|---|---|
| T3a | 00:17 slot 1 Channel EQ → **Linear Phase EQ** (Stereo); its settings carried over, Gain 0.0 | 100, 30 | none of 26 sliders changed | no match: ✔ |
| T3b | 00:19 slot 1 → "No Plug-in", then a **new Channel EQ** in slot 1 ("デフォルトプリセット", flat, 0.0 dB) | 70, 40 | new instance 265 (+2.5), 151 (−8.9) | new instance controlled: ✔ |
| T3c | 00:20 add a second Channel EQ in the empty slot after ChromaGlow (slot 4) | 44 | slot 1 166 (−7.4); slot 4 stays 240 | upper (slot 1) controlled: ✔ |
| T3d | 00:23 slot 1 → "No Plug-in" (slot 4 is the only Channel EQ) | 70 | slot 4 265 (+2.5) | follows to slot 4: ✔ |
| T3e | 00:23 add a new Channel EQ in slot 1 again | 60 | slot 1 227 (−1.3); slot 4 stays 265 | moves to the new upper one: ✔ |

- O1: choosing the plug-in already in the slot ("Channel EQ > Stereo" with its check mark) did nothing and added no undo step, so T3b used remove + add.
- O2: a press that landed on the empty slot below opened the plug-in menu while the button was held; Escape closed it before release, and the undo list showed no change.
- O3: T3a was checked with a crossing value (30 crosses the target's 63.5 in CC units), so Pickup cannot explain the lack of change. After undoing T3a, 64 moved the restored Channel EQ to +0.2 dB again.
- O4: two plug-in windows with the same title "Ballad" were read separately by position with `Tools/research-scripts/ax-value-read.swift` (now reads every window with the title).
- Restore: the Undo History window listed steps 1–5 (09:19:24–09:23:33 local); all were undone; slot 1 is the original Channel EQ ("カスタム"), all 26 sliders equal the baseline after Option-click reset of Master Gain (00:25:25Z). The probe was stopped.
- Raw data (not in Git): `Research/raw/ca007/` (`T3*.json`, `prediction-T3*.txt`, `probe.log`).

## Verification stages

1. MIDI sent: TX lines in `probe.log`.
2. Assignment: unchanged row on `logicctl-gen` (EXP-CA-006).
3. Value: AX slider values of each instance after each send.

## Hypothesis

Hypothesis: for an unpinned plug-in parameter assignment, Logic resolves the target on every message as the first plug-in, in slot order on the selected track, with the saved IDs; it does not stick to an instance and ignores the saved instance UUID. Confidence: high for this row (5 of 5 predictions), medium in general (one plug-in type, one track).
Next: the same with a pinned (0xb000) assignment, where the instance UUID path and the fix-up pass (I13) should apply.
