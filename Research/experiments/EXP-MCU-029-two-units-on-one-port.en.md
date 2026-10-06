[日本語](EXP-MCU-029-two-units-on-one-port.md) | [English](EXP-MCU-029-two-units-on-one-port.en.md)

# EXP-MCU-029: two Mackie Control units on one port — the LCD gets mixed and a scan returns a false complete

| Item | Value |
|---|---|
| Date and time | 2026-10-07 01:20 to 01:31 (JST) |
| Logic version | 12.3.1 (6682) |
| macOS version | 27.0, arm64 |
| Logic Remote version | Not applicable (the research peer's PLAN-05 E3 reception came just before; no connection during this experiment) |
| Test project | LogicCLI-Test.logicx (window title checked on screen) |
| Initial state | Stopped. Ballad (3) selected. The song has 14 strips (Remote `/ati` and the screen; outputs and Master included) |
| The one operation | Nothing that changes the song. MCU reads, one Bank Left press, a fader touch, and two restarts of logicd (with MIDI tracing) |
| Expected change | `state` returns 14 strips |
| Repetitions | False complete: 3 times (twice in EXP-MCU-028, once here). A dump with two different displays: twice (16:23:59Z, 16:30:01Z) |
| Approval | Using the real Logic: the user said "全て許可" (all allowed) directly in this chat. Logic's settings were only read (not changed) |

## Observations

- `logicctl state` (16:21:01Z) returned `ok: true`, `complete: true`, **6 strips**, `bank_steps: 0`, named 1=Trk07, 2=Trk06, 3=Trk05, 4=Trk09, 5=St Out, 6=Master. On screen 1=Piano, 2=Synth, 3=Ballad. EXP-MCU-028's `state` (16:03Z, 16:05Z) was complete with **8 strips** (Piano to Trk10). Both are parts of the 14.
- `logicctl debug mcu`: the LCD's name row held the names of positions 9 to 14; the select and REC LEDs were on the third slot (Ballad, if the view were positions 1 to 8). Bank Left did not change the LCD, even after 3 seconds.
- After restarting logicd with tracing, Logic's dump right after the connection sent **whole-display LCD writes with different content** (offset 0, 111 bytes) on the same port, in the same order on both restarts:

  | Time (UTC) | Name row |
  |---|---|
  | 16:23:59.216 / 16:30:01.127 | Piano Synth Ballad Trk08 Audio AmpdUp Bass Trk10 (positions 1 to 8) |
  | 16:23:59.254 / 16:30:01.169 | Trk07 Trk06 Trk05 Trk09 St Out Master (positions 9 to 14) |
  | 16:23:59.318 / 16:30:01.243 | Piano Synth Ballad Trk08 Audio AmpdUp Bass Trk10 (positions 1 to 8) |

  In the 10-02 trace with one unit (EXP-MCU-024), the dump's whole-display write came **twice with the same content**.
- Logic's control surface settings file, **only read** (a copy was taken to a scratch location and only strings were counted), describes three devices: "Control Surface: Mackie Control", "Control Surface: Mackie Control #2" and "Control Surface: logicctl-research-peer".
- logicd does not set its virtual ports' unique ID (CoreMIDI `kMIDIPropertyUniqueID`), so each start gets new IDs. After the 16:30 restart, the settings file (rewritten by Logic at 16:30Z) contained the new source and destination IDs once each, the string "logicctl-mcu" went from 80 to 82 occurrences, and the file grew by 200 bytes (the values themselves are not recorded).
- The 10-04 scan (EXP-MCU-027) was right: 12 strips, `bank_steps: 4`. logicd did not run between 10-04 15:57Z and 10-06 16:03Z.
- logicd with the fix (started 16:30:01Z): `status` has `mcu.surface_conflict: true`. `state` and `track list` were refused with `surface_conflict`, and no button was pressed.
- Raw records: `Research/raw/mcu-two-units/` (trace, diagnosis, JSON) and `Research/raw/live-arm/e4-arm/` (the 16:21 `state`). Not tracked by Git.

## Hypothesis

Hypothesis: **Logic drives two Mackie Control units on `logicctl-mcu`, and the second shows the strips to the right of the first (positions 9 to 16).** Both send LEDs with the same numbers and LCD writes to the same port, so logicd's LCD holds the names of whichever wrote last. Two units show all 14 strips of this song, so neither Channel Right nor Bank Right does anything, and the scan decides it has reached the end.
Confidence: high.
Evidence: two whole-display writes with different content (both times), names matching positions 9 to 14, "Mackie Control #2" in the settings file, and no response to Bank Left.
Counter-example: if two kinds of write continue after the second unit is removed, there is another cause.
Next experiment: after the user removes "Mackie Control #2" in the settings (or says it may be removed), restart logicd and check for one kind of dump, `surface_conflict: false`, and a `state` of 14 strips with `bank_steps` 6. Check the dump by starting logicd with `LOGICD_TRACE=1` and seeing `python3 Tools/research-scripts/mcu_trace.py dumps ~/Library/Logs/logicctl/logicd.log --since <restart time>` report "one unit" (tonight's two dumps report "2 units suspected"; the single-unit trace of 10-02 reports "one unit").

Hypothesis: Logic also remembers a device's ports by unique ID, and every logicd start adds a record for new IDs. This may have played a part in adding the second unit.
Confidence: low.
Evidence: the settings file grows on each restart and takes the new IDs (seen once). But the number of strings (82) does not match the logicd starts in this log (15) (research tools used the same port name too).
Counter-example: the second unit is added even with fixed unique IDs.
Next experiment: a logicd that fixes the unique IDs. Trying it may add yet another unit, and removing one needs the user's permission, so only after talking to the user.

Static note (checked in machine code, [anchor table](../protocol/logic-cs-autoinstall-anchors.tsv), 34 rows): Logic has a toggle for installing control surfaces automatically (`CSM_006_AutoInstall`, `FUN_00ad6130`). Its state query (mode 2) answers "on" while bit 1 of the internal byte `0x26b52cf` is 0, and a one-time initialisation sets that byte to 0. Switching it back on (mode 0) calls `FUN_00a7b48c(0)` and `FUN_00a7e3ac` (presumed to start a scan). Whether the byte is loaded from the settings file was not read.

Hypothesis: with automatic installation on, Logic's device search (logicd's connections did bring queries for models 0x10, 0x11, 0x14, 0x15 and 0x17) took a logicd reply for a new device and added "Mackie Control #2".
Confidence: low (only a candidate mechanism; the moment it was added was not seen).
Next experiment: read the automatic installation path statically (where `FUN_00a7b48c` and `FUN_00a7e3ac` add a device).

Hypothesis: the second unit was added after 10-04. When, and by what (Logic's automatic device scan, an action in the settings window while registering the research peer, …), is not known.
Confidence: low.
Evidence: the 10-04 scan behaved like one unit.
Next experiment: none (the settings file keeps no history). Watch whether it comes back after removal.

## What it means for the product

- The rule "if Channel Right and Bank Right both get no response, this is the end" assumed **one unit**. With a second unit it returns a false `complete: true`.
- logicd counts a whole-display write as a contradiction when it lands **on a different, non-blank name row** (without a handshake in between); a contradiction in the latest window of writes (1 second) is `surface_conflict`, and everything except `status` and the research tool `debug mcu` is refused. A handshake blanks the display, so one unit re-sending changed names (a reconnect after a rename) is not a contradiction. The check also runs **after** each command: if a second unit's dump arrived meanwhile, a read's result is dropped and a write becomes `surface_conflict` as "may have reached Logic, cannot be checked" (the fix for three cases found by Codex's independent review). The transport readback used by other routes refuses too. Tests: `Tests/LogicCoreTests/SurfaceConflictTests.swift`. On the real traces the second unit's writes (16:23:59.254, 16:30:01.169) count as contradictions, and the single-unit trace of 10-02 has none (`mcu_trace.py`).
- No workaround (using only the first unit's 8 strips, treating the second as an extender) was made, because the two units share the LED and LCD channel.
- Limit of the detection: it relies on both units sending their dumps together (as they did both times logicd re-created its port). If a second unit is added while logicd runs and only that unit sends a dump, or a handshake falls between the two units' writes, it cannot be told from one unit reconnecting and may go undetected (unchecked). When in doubt, restarting logicd with `logicctl daemon stop` makes both units dump together and the check runs again. "The names differ before and after a reconnection" is not used as a condition, because switching songs also brings a dump with different content.
- Possible false positive: even with one unit, a whole-display write that differs from the names on display without a handshake in between gives `surface_conflict` (whether a song switch does that is unchecked; there is no trace yet). It only refuses reads and writes, and the fresh dump after `logicctl daemon stop` clears it.
