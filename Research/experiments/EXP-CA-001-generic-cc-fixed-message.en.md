[日本語](EXP-CA-001-generic-cc-fixed-message.md) | [English](EXP-CA-001-generic-cc-fixed-message.en.md)

# EXP-CA-001: a generic CC assignment (CC 20 → Pan) acts as a "fixed message"

| Item | Value |
|---|---|
| Date | 2026-10-08 01:32–01:45 UTC (the retest of 09:50–09:56 UTC the day before overlapped other operations and is invalid; observation O0 below) |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (stopped, not saved) |
| Initial state | Synth selected, pan +2. Settings > Control Surfaces > General: Pickup mode **on**, Bypass all in background off. The virtual MIDI port `logicctl-cc` was created after Logic started |
| One operation | Send the **exact** learned message `B0 14 40` to the assigned row (no zone, class Channel Strip, selected track, Pan); then other values and a burst, one condition at a time |
| Expected change | Per Apple's guide, a message with neither Lo7 nor Hi7 is received as value 0; it should act only on an exact match and not on nearby values |
| Repetitions | Exact match 8 times (3 single, one burst of 5), non-matching 1 time (this run). The invalid run of the day before had 2 exact and 10 non-matching |

## What Apple's official guide says (ja-jp; the guide's version selector stops at 12.3, there is no 12.4 page yet)

- "MIDI input" parameters (ctls71c30fbf): the value-change message is editable. Variable parts are `Lo7`/`Hi7`; a message with neither is received as value 0 (typically button down/up).
- "Value" parameters (ctls71c308ee): modes are Direct / Toggle / Scale / Relative / Rotate / X-OR; faders and knobs default to Scale, encoders to Relative.
- Expert view (ctls71c3162b): rows under "no zone" are always active, whatever zone is active.
- General settings (lgcp1fe673ef): Pickup mode keeps the value unchanged until the controller reaches the current value.

## Observation

- O1: sending the exact `B0 14 40` three times, one at a time, moved pan +2 → +3 → +4 → +5 (inspector and the MCU `pan_raw` agree).
- O2: one `B0 14 41` changed nothing (pan stayed +4).
- O3: five exact messages written at once took pan +5 → +10. None dropped.
- O4: the row shows its value-change message as a fixed `B0 14 40` (no `Lo7`), Lo7 range 0–127, format unsigned, value −64…+63. By comparison, MCU rows show `90 2E Lo7`.
- O5: while pan changed, Logic sent 0 MIDI messages back to `logicctl-cc` (only device-query sysex arrived).
- O6 (operating caution): pressing "Register message" with a row selected does not re-register that row. It creates a **new key-command row** (default "Show/Hide Loop Browser") and waits for input. Pressing it again removed the empty row. No message was sent.
- O7: typing into the value-change field in the background failed (the accessibility write was refused; the keystrokes went to the assignment list and Cmd+A selected both rows). No data changed.
- O0 (the invalid run of the day before): on 12.4, values 100, 65, 66, 70, 80, 127, 0 and 67 had no effect, and only the two exact messages moved pan (+1, +2). It overlapped other operations, so it is not used as evidence, but it does not contradict O1–O3.
- Raw data (not in Git): `Research/raw/midi-learn/probe5.log` (this run), `probe4.log` (invalid). Screen checks are in the conversation record with operation times.

## Hypothesis

H1: the row is a **fixed-message trigger**; each `B0 14 40` advances pan by one step (a relative one-step action). Other CC 20 values do not match, so they do nothing.
Confidence: "only the exact message acts" is high. "+1 per message as a relative step" is medium (why the sign and step are 1 is not confirmed).
Basis: O1–O3, O4, Apple's statement (no Lo7 means value 0).
Counterexample: none yet. The mode field is not shown on screen, so Direct vs Relative is not confirmed.
H2: editing the value-change message to `B0 14 Lo7` makes it work as a knob, and with Pickup mode on it would not move until the controller nears the current value (a prediction from Apple's text). Confidence: low (untested).
H3: the "Pan" and "-" strip names seen on the MCU LCD the day before may be a transient display right after this assignment acted. Not reproduced this time. Confidence: low.
H4: a generic assignment has no output port, so Logic sends no feedback. Confidence: medium-low (O5 covers one row and one parameter).
The earlier note (CLDE079) "learned but inactive" was wrong: it was a row that acts only on the one value used in learning.

## Next experiments

1. Edit the value-change message to `B0 14 Lo7` (needs real key input), or learn again while sending several values, then send 66, 80 and 100. Comparing Pickup on/off is a settings change, so ask the user first.
2. Ask the user whether to delete this test row or keep it (created only for testing).
