[日本語](EXP-REMOTE-006-explicit-arm.md) | [English](EXP-REMOTE-006-explicit-arm.en.md)

# EXP-REMOTE-006: `r` and the MCU REC LED when one explicit record-enable is changed (PLAN-05 E4, method B)

| Item | Value |
|---|---|
| Date and time | 2026-10-07 13:04 to 13:14 (JST) |
| Logic | 12.3.1 (6682), macOS 27.0, arm64. `LogicCLI-Test.logicx` only, stopped, no sound |
| Approval | The user said "全て許可" directly in chat. Restoring through the screen was allowed directly in chat ("you may use the screen for about 10 seconds") |
| Initial state | 14 strips, Ballad selected (automatic record-enable: `r` 3, MCU REC LED on), Synth `r` 0 |
| The one operation | `logicctl track arm 2 on --expect-name Synth` (one MCU REC press, 04:05:00.312Z) |
| Reception | Research peer once, `20261007-130449-e1`, 7,762 frames, `receive_window_over` |
| Raw records | `Research/raw/live-arm/e4-arm/` (operation times, JSON), logicd's trace (not tracked by Git) |

## Observations

- **Remote**: after the press, Synth's `r` **alternated between 128 (0x80) and 1 about every 0.73 s**, and `/gtFaderData` was resent at each flip. Ballad's `r` went 3 → 0. `/cs/mixer/record/2` blinked 1/0 too, `record/3` was 0. `/sti` did not change.
- **MCU**: Ballad's REC LED went off 0.11 s after the press; Synth's REC LED first lit 0.86 s after it and then repeated 7F/00 about every 0.73 s (blinking). One press was sent.
- logicd waited 0.8 s, read the LED as off, and **returned `verification_failed`** (the track was in fact armed).
- Restoring: a second MCU REC press (04:08:23.151Z) **did not disarm**; 0.32 s later the select LED moved to Synth. `track select 3` brought the selection back to Ballad but not its automatic record-enable, and pressing the on-screen R from the background (AXPress) had no effect. With the user's permission the screen was used and R was clicked for real (an accidental click on S was undone at once). Ballad's automatic record-enable came back on screen, but the MCU did not report Ballad's REC LED, and logicd's `state` still read false.

## Hypothesis

Hypothesis: **`r` 1 and 128 are the two phases of the blinking of one explicit record-enable** (as SA-REMOTE-STATE-001 §8.3 predicted; `0x261e118` is the blink phase).
Confidence: high (the 0.73 s alternation was seen in the reception, with the same period as the MCU LED blinking).
Counter-example: another value while recording (no blinking).

Hypothesis: pressing the MCU REC of a track whose record-enable is blinking can move the selection instead of disarming.
Confidence: low (once). In EXP-MCU-028 the MCU did disarm.
Next experiment: arm → disarm a non-selected track twice with the MCU only (prepare a way to restore first).

## What it means for the product

- `track arm` now assumes blinking: the starting state is settled over one blink window (1.6 s); after the press, one "on" report within the window means armed, and no "on" for the whole window with the LED off means disarmed. `rec_armed` in `track get` / `state` is true when the LED was on within the window (fake-Logic tests such as `aBlinkingRecLEDCountsAsArmed`). The live recheck waits until the disarm problem above is understood.
- When reading record-enable through the Remote, take `r` 1 and 128 as the same "explicit record-enable"; 3 is the automatic record-enable that follows the selection, 64 a track that cannot be armed.

## Follow-up (2026-10-07 13:17 to 13:25 JST, MCU only, no reception)

- With the blink-aware build, `track arm 2 on` gave `verified: true`. The following `off` **did disarm, but Logic sent no "off" for the REC LED** (it stopped at the blink's last value, "on"; on screen Synth's R was off and Ballad's automatic record-enable was back). What looked like "cannot disarm" while restoring E4 was this stale LED, plus another press on top of it.
- Fix: when the blinking has stopped after a disarm and no "off" arrived, move one channel away and back (Logic resends the view's LEDs) and read again over the blink window. With this build `on` → `off` → `off` (the second verified without sending) were all `verified: true`, matching the screen. Test: `aDisarmThatLeavesTheLEDOnIsCheckedByMovingTheViewAwayAndBack`.
- Records: `Research/raw/live-arm/disarm-check/`.
