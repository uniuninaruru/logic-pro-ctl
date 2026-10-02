[日本語](EXP-MCU-021-last-strip-db-text.md) | [English](EXP-MCU-021-last-strip-db-text.en.md)

# EXP-MCU-021: Only the last strip prints its dB text at a shifted position

| Item | Value |
|---|---|
| Date | 2026-10-02 09:15–09:40 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Test project | LogicCLI-Test.logicx (10 tracks + St Out + Master = 12 strips) |
| Tools | `logicd --trace` (MIDI send/receive log), `logicctl track volume` |
| Initial state | All track volumes 0.0 dB |

## Symptom

`track volume 9 -6` and `track volume 10 -6` intermittently ended in `verification_failed`.
`observed` was unrelated to the request, e.g. `{fader_value: 4887, volume_db: 3.5}`.
When `-6` failed, `0` on the same track succeeded (failures: 3 on `track volume 10 -6`, 1 on track 9).

## Observation

The trace was captured for `track volume 10 -6`, whose target was on the **8th strip** (bank offset 2).
The bank offset was not recorded for the track 9 failure. From the positioning steps it was probably offset 1, the 8th strip (not confirmed).
At offset 4 (right after `track list`) tracks 9 and 10 sit on the 5th and 6th strips and succeed,
which is why earlier checks missed it.

MIDI trace (track 10, 8th strip):

| Direction | Message | Meaning |
|---|---|---|
| TX | `90 6F 7F`, `E7 11 4D` | touch the 8th fader and set 9873 |
| RX | `F0 00 00 66 14 12 62 [20×6] 2D 36 2E 30 20 64 42 F7` | LCD from 98: six spaces, then `-6.0 dB` |
| RX | `E7 12 4D` | fader echo 9874 (= −6.0 dB) |

The dB text is 8 characters and is shifted left so it does not run off the row (56 characters).
On strips 1–7 the text starts at the cell start (`56 + 7n`); **on the 8th it starts at 104**.
The cell starts at 105, so reading 7 characters from there gives a fragment such as `.0 dB `.
That fragment was read as `.0` → 0.0, or mixed with the partial writes in between, and verification failed on a wrong value.
I believe `0` succeeded because a missing sign still reads as 0.0 (hypothesis, not confirmed).

## Fix and verification

- The dB read position is now `min(56 + 7n, 104)` (`MCUSurface.dbText`).
- Live: `-6` and `0` on tracks 1–12, including orders that change the bank position (9→8→12→1): all 32 writes verified. All tracks end at 0.0 dB.
- Test: `volumeIsReadFromTheShiftedTextOnTheLastStrip` passes against a fake surface that reproduces the shifted 8th strip.
  With the fix removed the same test fails.

## Conclusion

Hypothesis: the dB text is a fixed 8 characters starting at `min(cell start, 104)`.
Confidence: medium to high. The 3 failures on track 10 (8th strip) match the traced layout, and after the fix all 32 writes, 8th-strip positions included, verified. It matches `56+7n` on the other strips.
Counterexamples: none.
Next validation experiment: in a project with 8 strips or fewer (the bank never moves), check the 8th strip lands at the same position.

## Consequence for logicctl

The defect predates the bank-offset change. It depends on strip placement, so it looks like an
intermittent failure per track number. Before the fix, a volume write on the 8th strip could not be verified.
