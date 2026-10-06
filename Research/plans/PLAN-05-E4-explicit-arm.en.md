# PLAN-05 E4: change an explicit record-enable once and look at the Remote's `r`

[日本語](PLAN-05-E4-explicit-arm.md) · [English](PLAN-05-E4-explicit-arm.en.md) · [E3 plan](PLAN-05-E3-manual-selection.en.md) · [E3 result](../experiments/EXP-REMOTE-004-selection-delta.en.md)

**The aim is to see how `/gtFaderData`'s `r` and `/cs/mixer/record/N` move when only the record-enable of a non-selected track changes once, with the selection left alone.** In E3 the automatic record-enable moved with the selection and the 3 in `r` moved with it (EXP-REMOTE-004). Which value an explicit record-enable gives has not been seen yet.

| Item | Value |
|---|---|
| Status | Plan only. Not run on the night of 2026-10-07 (the MCU was unusable because of a second unit on the same port ([EXP-MCU-029](../experiments/EXP-MCU-029-two-units-on-one-port.en.md)), and the screen was locked) |
| Approval | The user said "全て許可" (all allowed) directly in chat (using the real Logic; retrying experiments like E3). Test project only, reversible operations only |
| Project | `LogicCLI-Test.logicx` only. Stopped. Not saved |
| Connection | The research peer `logicctl-research-peer`, once (e0 to check the advertised name, e1 for 120 s). Initial sends are only `/protocolVersion=10` and `/jsonSupport=1`. **Only one peer at a time** (who runs it is agreed on the board) |
| The one change | Turn record-enable **on once** for Synth (position 2, a software instrument that is not selected), by exactly one of: **A. clicking R on its track header on screen** (works without the MCU), **B. `logicctl track arm 2 on --expect-name Synth`** (after the second unit is removed and `surface_conflict: false` is checked) |
| Kept unchanged | The selection (Ballad), mute, solo, volume, other tracks' record-enable, the song |
| Output | `Research/raw/remote-recv/<time>-e1/` (reception), `Research/raw/live-arm/e4-arm/` or `e4ui-arm/` (operation times, screen checks) |

## Predictions (from static analysis, [SA-REMOTE-STATE-001 §8.3](../static-analysis/SA-REMOTE-STATE-001.en.md))

| What | Prediction | Confidence |
|---|---|---|
| Synth's `r` | Changes from 0. The value is **1**, or **0x80** depending on the blink phase (a software instrument takes the unread "negative *k*" route, so the value cannot be pinned down) | Low |
| Ballad's `r` | Over the MCU, Ballad's automatic record-enable went off (EXP-MCU-028). If A does the same, 3 → 0; if not, it stays 3. Record either way | Low |
| `/cs/mixer/record/2` | Becomes 1 (the Remote's 8-slot view; slot 2 is Synth when `bankLeftOffset` is 0, a hypothesis) | Medium |
| `/sti` | Unchanged (the selection is not changed) | Medium |
| `ip` | Stays 0 (`_BgTrackInfoIndependentPanKey`, not input monitoring) | Medium |

## Steps

1. On screen, check the test project, stopped, Ballad selected and Synth's R off, and record that with the time. For B, also check `surface_conflict: false` with `logicctl status`.
2. The receiver runs `run.sh e0 --seconds 8` for the advertised name, then starts `run.sh e1 --seconds 120 --target <name>`. Once `/ati`, `/sti` and `/gtFaderData` have arrived, they write "記録準備完了" (ready) on the board. If the three do not arrive, end without doing anything.
3. The operator records the UTC time just before, does A or B **once**, and records the UTC time just after. For B, save `verified` and the JSON. Check on screen that Synth's R lit (blinking), minding the off phase of the blink.
4. After about 30 seconds the receiver stops the run (or it times out).
5. After the reception, restore as a separate operation: turn Synth's record-enable off (R again for A, `track arm 2 off` for B). If Ballad's automatic record-enable went off, move the selection Synth → Ballad (as in EXP-MCU-028). Record the time and the screen.
6. Reading: `remote_state.py timeline <run> --from <frame before the operation>` lists the arrival order of `/cs/mixer/record|select/N`, `/sti` and `/gtFaderData`. `remote_state.py replay` compares `r`, `ip` and `control_surface_view` before and after. The aborted E4 (120 seconds with no operation) serves as the no-change control.

## Stop if

- The title is not "LogicCLI-Test", another song is open, it is playing, or the screen is locked.
- Who receives and who operates is not agreed, or another peer is running.
- For B: `surface_conflict` is true, or the result is `target_mismatch` or `session_changed`.
