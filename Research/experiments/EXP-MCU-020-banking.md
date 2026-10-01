# EXP-MCU-020: MCU bank/channel navigation and the bank-offset bug

| Field | Value |
|---|---|
| Date | 2026-10-01 14:44–14:58 JST |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0 (26A5416b) |
| Test project | LogicCLI-Test.logicx, now 10 tracks: Piano, Audio, Bass, Synth, Trk05…Trk10 (audio) |
| Tool | `logicctl debug mcu …` (raw MCU messages through logicd), `LOGICD_TRACE=1`, Accessibility track-header names |

## Bug found (v0.1)
After 6 tracks were added and track 10 was selected in the GUI, Logic had moved
the MCU bank to offset 4 by itself (Control Surface setting 「選択中の表示に追従」 is on).
`logicctl track select 5` then pressed strip 5 = **track 9** and reported
`verified: true, selected_track: 5`; a following GUI rename hit track 9.
v0.1 assumed strip *n* = track *n*. Severity: wrong-target write reported as verified.

## Observations (single presses, LCD upper row after each)
| Start offset | Press | Result offset |
|---|---|---|
| 4 | Bank Left (0x2E) | 0 (clamped, not −4) |
| 0 | Bank Left | 0 — **Logic sends nothing** (trace) |
| 0 | Channel Right (0x31) | 1 — Logic sends LCD diff, select LED, and `F0 00 00 66 14 72 <8 colour bytes> F7` |
| 1 | Bank Right (0x2F) | 4 = strips (12) − 8 (clamped, not 9) |
| 4 | Bank Right / Channel Right | 4 — nothing sent |
| reconnect logicd | — | offset kept by Logic (4 before and after) |

Strip order = Logic mixer order in "アレンジ" mode: tracks 1…10, then St Out, Master.
LCD shows only the ASCII part of names ("オーディオ 2" → "2").

## Fix (logicd)
- A bank move is detected by any LCD or `14 72` colour update within 300 ms of a
  press; a no-op press produces none.
- `home()`: Bank Left until nothing moves → offset 0. To reach track *n* (index
  *n*−1 ≥ 8): Channel Right (*n*−8) times, counting only presses that moved.
- The offset is cached and invalidated whenever a colour sysex arrives that
  logicd did not cause (Logic moved the bank itself).
- `track list` walks all strips by stepping Channel Right; volume comes from the
  fader position via Logic's own table (SA-001), so no fader is touched.

## Verification after the fix
- `track list`: 12 strips in 1.4 s, names match Accessibility for tracks 1–10.
- Selected 10, then 5 → GUI inspector shows track 5 (screenshot).
- For tracks 5–9: `logicctl track select n` then GUI rename — the rename field
  each time contained track *n*'s old name (オーディオ 2…5, Trk05 for track 9);
  final AX names Trk05…Trk09 on tracks 5–9.
- Writes on tracks 9/10 (mute 10, volume 9 −6, pan 10 −0.5, solo 9) all verified;
  AX: track 9 volume −6.0 dB, track 10 mute 1, track 10 pan 「64中の32、左」. Restored.
- `track get 13` → `no_such_track`.

## Open
Hypothesis: a bank move whose names and colours are identical to the previous
view would be invisible to the detector. Confidence that this matters: low.
Next: check whether Logic also resends colours when a track colour changes
without a move (would only cause an extra re-home).
