[日本語](EXP-MCU-023-add-delete-reach-surface.md) | [English](EXP-MCU-023-add-delete-reach-surface.en.md)

# EXP-MCU-023: Do adding and deleting tracks reach the MCU display? (and a defect that trusted a stale bank position after a delete)

| Item | Value |
|---|---|
| Date | 2026-10-02 14:00–14:40 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (10 tracks + St Out + Master = 12 strips). Not saved |
| Tools | `logicctl` (`--expect-name`), `mcu_lcd` of `logicctl status` (a copy of the LCD; does not move the bank), Logic's menus |
| Initial state | Connected to the MCU. All tracks unmuted |
| One operation | Experiment A: menu "Track → New Audio Track". Experiment B: menu "Track → Delete Track" (with the added track selected) |
| Repetitions | Two add/delete cycles (the first with the old build, the second with the fixed build) |

## Observations

### Experiment A: adding a track (cycle 1)

| Step | Observation |
|---|---|
| LCD before | `Piano  Audio  Bass   Synth  Trk05  Trk06  Trk07  Trk08  ` (the start of the bank) |
| LCD right after (we did not move the bank) | `Trk05  Trk06  8      Trk07  Trk08  Trk09  Trk10  St Out ` |
| Check (using the layout from before) | expecting `Trk07` at 7, `St Out` at 11, `Master` at 12 → **all three `target_mismatch`** (actually `8`, `Trk10`, `St Out`) |
| `track list` | Complete. 13 strips |

- Logic reflected the addition on the surface. **Logic also moved the displayed range (the bank) itself** (the first cell changed from `Piano` to `Trk05`).
- The new track is named "オーディオ 8" in Logic. The LCD shows **`8`**: the non-ASCII characters were not displayed (one example).

### Experiment B: deleting a track (cycle 1, build before the fix)

| Step | Observation |
|---|---|
| LCD before the delete | `Trk06  8      Trk07  Trk08  Trk09  Trk10  St Out Master ` (tracks 6–13; bank position 5) |
| LCD right after the delete | `Trk05  Trk06  Trk07  Trk08  Trk09  Trk10  St Out Master ` (tracks 5–12; the bank was pulled back) |
| `track get 13 --expect-name Master` | **Succeeded (defect).** The non-existent track 13 was read as `Master` |
| `track get 8 --expect-name Trk07` | **Succeeded (defect).** Track 8 should be `Trk08`; it read `Trk07` |
| `track list` | Complete. 12 strips (correct) |

- The display had been updated, but `logicd` kept trusting the bank position from before the delete (5) and read a different cell.

### Cause of the defect (Hypothesis)

Hypothesis: when a delete pulls the bank back, Logic rewrites the name row but does not send the colour sysex that signals a bank move.
Confidence: high. The evidence is that `bankIsKnown` (the colour-update count and the connection generation are the same as when the position was set) stayed true. A MIDI trace was recorded afterwards and confirmed that no colour sysex arrives right after a delete ([EXP-MCU-024](EXP-MCU-024-trace-add-delete.en.md)).
`logicd` detected bank moves by counting colour sysex messages (EXP-MCU-020). A move by a button brings one each time; the pull-back from a delete is presumed not to.

### Fix and re-check (cycle 2, fixed build)

- `MCUBackend`: remember the name row (upper LCD row) from when the position was set; **if the display no longer matches it, do not trust the position and re-establish it from the start**.
- Unit test: `aBankShiftWithoutAColourSignalIsStillNoticed` (a simulation where the bank is pulled back with no colour signal). It failed before the fix and passes after.
- Real Logic: add → (position at the end with `track get 13 --expect-name Master`) → delete. Result:

| Check | Result |
|---|---|
| LCD right after the delete | `Trk05  Trk06  Trk07  Trk08  Trk09  Trk10  St Out Master ` |
| `track get 13` | **`no_such_track`** (it returned `Master` before the fix) |
| `track get 8 --expect-name Trk08` | succeeds |
| `track get 8 --expect-name Trk07` | `target_mismatch` (actually `Trk08`) |
| `track get 12 --expect-name Master` | succeeds |
| `track list` | Complete. 12 strips, all names as before |

## Reordering (not confirmed)

A reorder could not be produced, so there is **no result**.

- Dragging the track header (background operation, from the icon): the track was only selected; the order did not change.
- Menu "Track → Reorder Tracks → Track Name" (background operation): executed, but neither the order nor the LCD changed.
- A later retry (real mouse input with Logic in front): a drag that started on a button only toggled the track's mute (`M`) (restored).
  Slow drags from the track number, the icon and the gap between buttons (3 variants) only selected the track.
  Running the menu "Track Name" with real clicks (once with one track selected, once with all 10) changed nothing either. Logic's undo history has no "reorder" entry (only 2 renames, 3 creates and 3 deletes).
- So **this way of operating does not reorder**. Whether this is Logic's behaviour or a limit of how the input is delivered (synthesised mouse events) is not distinguished.

## Other observations

- `handshake_generation` went from 4 to 8 in the meantime. At a time that matches none of our actions (05:22 UTC), Logic repeated its connection requests. The cause was not investigated.

## Hypothesis

Hypothesis: when adding or deleting tracks changes the order of strips, Logic rewrites the MCU name row. It does not necessarily send the colour sysex that signals a bank move along with it.
Confidence: high that adds and deletes are reflected (twice each on the real Logic; LCD copies and check results agree). Medium for the missing colour sysex (above).
Counterexamples: none.
Next validation experiment: (1) [done] Record the MIDI of a delete: [EXP-MCU-024](EXP-MCU-024-trace-add-delete.en.md).
(2) Reordering by a person's hands, or a key command (synthesised mouse input has not produced it so far). (3) Check that re-establishing the position when the name row differs does not cause excessive re-positioning in real use.

## Consequence for logicctl

- Adds and deletes were detected by `--expect-name` (real Logic). Reordering is still unconfirmed.
- The bank position is now trusted only while **the name row is unchanged**, in addition to the colour-update count and the connection generation.
- On an add, Logic may move the displayed range by itself. The `track list` scan still starts from the beginning each time, as before.
- A non-ASCII name may not appear on the LCD, so `name` can differ from the original name. Use the displayed `name` as it is for the check.
