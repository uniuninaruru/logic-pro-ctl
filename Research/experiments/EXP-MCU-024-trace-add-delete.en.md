[日本語](EXP-MCU-024-trace-add-delete.md) | [English](EXP-MCU-024-trace-add-delete.en.md)

# EXP-MCU-024: The MIDI Logic sends to the MCU when a track is added or deleted

| Item | Value |
|---|---|
| Date | 2026-10-02 14:40–14:46 JST (UTC 05:40–05:46) |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (12 strips). Not saved |
| Tools | `logicd --trace` (received MIDI with timestamps), Logic's menus |
| Raw data | `Research/raw/mcu-trace/EXP-MCU-024-trace.log` (not tracked by Git) |
| Initial state | `logicd` restarted and connected. The display is at the start (`Piano … Trk08`) |
| One operation | Experiment A: add a new audio track from the menu. Experiment B: delete that track (`logicctl` only runs `status` and `track get` in between; it sends nothing at the moment of the operation) |
| Purpose | Check by MIDI the hypothesis of [EXP-MCU-023](EXP-MCU-023-add-delete-reach-surface.en.md): "a delete does not bring the colour sysex (`F0 00 00 66 14 72 …`) that signals a bank move" |
| Repetitions | One cycle |

## Observations

Received MIDI (times in UTC). LCD writes are `F0 00 00 66 14 12 <offset> <characters…> F7`, decoded.

### Experiment A: add

| Time | Received | Meaning |
|---|---|---|
| 05:41:20.236 | LCD offset 0, 55 characters: `Trk06  Trk07  Trk08  8      Trk09  Trk10  St Out Master` | A rewrite of the **whole** name row. The displayed range moved to start at `Trk06` (position 5) |
| 05:41:20.236 | LCD offset 105, 1 character | One character of the lower row |
| 05:41:20.236–.237 | `90 1B 7F`, `90 1F 00` | Select LED changes |
| 05:41:20.237 | **`F0 00 00 66 14 72 04 04 04 04 04 04 05 04 F7`** (colour sysex) | Colour update |

### Experiment B: delete

| Time | Received | Meaning |
|---|---|---|
| 05:41:32.056 | LCD offset 4, 22 characters: `5  Trk06  Trk07  Trk08` | A **differential** rewrite of the name row (from the first changed cell) |
| 05:41:32.056 | `90 1B 00` | Select LED off |
| 05:41:32.122 | `90 1C 7F` | Select LED on |
| 05:41:33.998 | LCD offset 98, 13 characters | A rewrite of the lower row |

- In the 2 seconds after the delete **no colour sysex arrived**.
- The next colour sysex arrived at 05:42:45.430, 73 seconds after the delete. Other MIDI (`F0 00 00 66 14 0E …`) accompanied it at the same moment, so it looks like a separate event (around then the undo-history window of Logic was opened; causation not confirmed).
- The whole trace has 21 colour sysex messages. Only the one right after the add (05:41:20.237) and the two at connection can be said, by time, to have been sent by Logic independently of `logicctl`'s actions. The rest overlap in time with `logicctl`'s positioning (Channel Right / Bank Right), but were not matched one by one.

## Hypothesis

Hypothesis: when a track is added, Logic moves the bank, rewrites the whole name row and sends a colour sysex. When a track is deleted, it writes only a differential of the changed range and sends no colour sysex.
Confidence: medium to high (one cycle; the MIDI record agrees with the inference of EXP-MCU-023).
Evidence: the tables above.
Counterexamples: none.
Not yet verified (does not raise the confidence): differences by the position of the delete, or between a bank that is pulled back and one that is not. One cycle only, and one position of the deleted track.
Next validation experiment: compare the MIDI of deleting a track near the start with a delete where the bank is not pulled back. Reordering still could not be produced (EXP-MCU-023).

## Consequence for logicctl

- The count of colour sysex messages alone cannot detect a shift caused by a delete. The bank position is trusted only while **the name row is unchanged** as well (implemented in EXP-MCU-023).
- Differential LCD writes (with an offset) arrive, and the `mcu_lcd` copies in this experiment show that `MCUSurface` keeps the name row correct.
