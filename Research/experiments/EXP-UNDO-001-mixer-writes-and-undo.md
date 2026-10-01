# EXP-UNDO-001: do MCU (logicctl) mixer writes create Undo steps?

| Field | Value |
|---|---|
| Date | 2026-10-01 13:58–14:02 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | ~/Music/Logic/LogicCLI-Test.logicx (open since relaunch at 13:25, EXP-A3-001) |
| Readback | `logicctl state` (MCU) + Accessibility scan of track headers (independent) |
| Initial state | All tracks 0.0 dB, pan 0, unmuted (both channels agree). Since the 13:25 relaunch every mixer change went through MCU (EXP-MCU-*, EXP-CLI-001) except one GUI mute/unmute. |

## Steps and observations
| # | Single action | Observation |
|---|---|---|
| 1 | `logicctl track mute 1 on` (verified) | — |
| 2 | Edit > 取り消す (menu, Logic in background) | Menu item **disabled**; not pressed. Track 1 still muted (MCU and AX). |
| 3 | GUI: inspector strip ミュート AXSwitch (unmute track 1) | AX mute=0. |
| 4 | Edit > 取り消す | Still **disabled**. |
| 5 | Edit > 取り消し履歴… was opened earlier; the panel only shows while Logic is active (it hides on deactivate). Seen during a raw click: list **empty**; header 「次の位置からパラメータの変更を含める: [ミキサー] [プラグイン]」, both buttons look off. | |
| 6 | Track > トラック名を変更, track 4 "Synth" → "SynthX" | Undo History shows exactly `1 名称変更 2026/10/01 14:00:26`. |
| 7 | Edit > 取り消す (Logic in background) | **Enabled and pressed**. GUI name back to "Synth". |
| 8 | `logicctl status` 2 s and 7 s later | MCU LCD upper row still `… SynthX St Out …` — **stale**. |
| 9 | `logicctl daemon stop`, wait 3 s, `logicctl status` (re-handshake) | LCD `… Synth  St Out …` — correct again. |

Side effect: a raw click meant for the hidden panel's ミキサー button landed in the
arrange area on track 2's lane (no region there; no visible change).

## Conclusions
Hypothesis: With Logic's default Undo History setting (mixer parameter changes not
included), mute/volume/pan changes — from MCU or from the GUI — create no Undo steps.
Confidence: high for mute (MCU and GUI) and for the MCU volume/pan writes made since
13:25 (the history was empty after ~40 such writes); the setting state itself is
read from button appearance only (medium).
Counterexamples: none.
Next validation experiment: enable 「ミキサー」 in the Undo History panel (needs Logic
frontmost, i.e. the user or full-screen control), then repeat steps 1–2.

Hypothesis: Logic does not push an MCU LCD update when a track rename is undone;
names read from the MCU can be stale until the surface reconnects.
Confidence: medium (one rename, 7 s window).
Next validation experiment: rename via GUI without undo — does the LCD update? Redo?

## Consequence for logicctl
- Agents cannot rely on Logic's Undo to revert logicctl mixer writes (default settings).
  logicctl must keep its own before/after values if it ever offers "revert".
- Track names from MCU can be stale; cross-check with Accessibility or force a
  re-handshake before trusting a name for targeting.
