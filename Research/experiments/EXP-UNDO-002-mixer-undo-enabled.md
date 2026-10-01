# EXP-UNDO-002: Undo with 「パラメータの変更を含める: ミキサー」 enabled

| Field | Value |
|---|---|
| Date | 2026-10-01 14:12–14:16 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Test project | ~/Music/Logic/LogicCLI-Test.logicx |
| Setting | The user enabled 「ミキサー」 in Edit > 取り消し履歴… (panel needs Logic frontmost) |
| Readback | `logicctl state` (MCU) and Accessibility track-header values; they agreed in every step |
| Undo/Redo | Edit menu via Accessibility, Logic in background |

## Steps
| # | Action | Result (track 2 vol via AX unless noted) |
|---|---|---|
| 1 | `logicctl track mute 1 on` → Undo | Track 1 **stays muted**. Instead track 3 pan 0 → −16 (reverts `track pan 3 0` from EXP-CLI-001, made before the setting was enabled). |
| 2 | Redo | Track 3 pan back to 0. |
| 3 | `logicctl track mute 1 off`; `logicctl track volume 2 -6` → Undo | Track 2 vol → 0.0 **and** track 3 pan → −16. |
| 4 | Redo | Track 3 pan 0; track 2 vol stays 0.0 (not re-applied). |
| 5 | GUI rename track 4 "Synth" → "SynthY" (recorded step); `logicctl track volume 2 -6` → Undo | Name stays "SynthY"; track 2 vol → **−11.4 dB** (never requested). |
| 6 | `track volume 2 0`, 1 s pause, `track volume 2 -6` → Undo | 0.0 dB (correct previous value). |
| 7 | `track volume 2 -6` → Undo | 0.0 dB (correct). |
| 8 | `track volume 2 -3`, `track volume 2 -12` back to back → Undo | **0.0 dB** (both writes undone in one step). |
| 9 | Undo again | **−11.4 dB** again. |
| cleanup | `track volume 2 0`; GUI rename back to "Synth" | All tracks 0.0 dB / pan 0 / unmuted; LCD name updated to "Synth" (a GUI rename does refresh the LCD, unlike the undone rename in EXP-UNDO-001). |

Undo History entries glimpsed while Logic was momentarily active (the panel
hides on deactivate): `Master : ボリューム`, `13 Piano : ボリューム`,
`14 Bass : Pan`, `15 Bass : Pan`, `16 Piano : ボリューム`, `17 Piano : ボリューム`.
The newest entries were scrolled out of view; not read.

## Conclusions
Hypothesis: Mute changes are never Undo steps, with or without the mixer setting.
Confidence: high (EXP-UNDO-001 + step 1 here).

Hypothesis: With the mixer setting on, MCU volume and pan writes are recorded
(pan already recorded before the setting was enabled, step 1), but consecutive
writes to the same parameter coalesce into one step when they are close in time
(step 8: <1 s apart merged; step 6: 1 s pause stayed separate).
Confidence: medium (n=1 for each spacing).

Hypothesis: Undo of an MCU volume write can restore a value that was never
requested (−11.4 dB, steps 5 and 9). Origin unknown — possibly an intermediate
value Logic recorded at an earlier step boundary.
Confidence: low on the cause; the observation itself reproduced twice.

Counterexamples: step 3's double revert (volume + pan in one Undo) is not
explained by any of the above.

Next validation experiment: read the full Undo History list (needs Logic
frontmost) after a single `logicctl track volume` write; vary the pause between
writes (0, 0.5, 1, 2 s) to find the coalescing window.

## Consequence for logicctl
Logic's Undo is not a dependable way to revert logicctl writes: mute/solo are
never recorded, volume writes may coalesce, and Undo may land on unrequested
values. If logicctl offers "revert", it must replay its own recorded
before-values and verify them.
