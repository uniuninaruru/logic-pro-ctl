[日本語](EXP-CA-003-value-mode-pickup-ab.md) | [English](EXP-CA-003-value-mode-pickup-ab.en.md)

# EXP-CA-003: the Value pane (mode, multiply) of assignments, and a same-stimulus Pickup comparison

| Item | Value |
|---|---|
| Date | 2026-10-08 02:04–02:12 UTC |
| Logic version | 12.4 (build 6707), recorded from the running process's Info.plist |
| macOS version | 27.0 (26A5416b) |
| Logic Remote version | n/a |
| Test project | LogicCLI-Test.logicx (stopped, not saved) |
| Initial state | Continues [EXP-CA-002](EXP-CA-002-variable-cc-and-pickup.en.md). Assignments CC 20 (fixed), 21 (pan), 22 (volume), 23 (Master Gain) remain. Pickup on |
| One operation | One condition at a time: (1) read each row's Value pane (read-only), (2) send CC 20 with pan at its maximum, (3) send the same stimulus `[90, 100]` to the same unsynchronized target with Pickup on and off, (4) with Pickup on, send "100 then 30" |
| Expected change | (1)(2): if the fixed row is in Rotate mode as Apple describes, it wraps from maximum to minimum. (3)(4): Pickup acts only when on, and synchronizes when the controller reaches or crosses the target's current value |
| Repetitions | (1) 5 rows, (2) 1 time (2 messages), (3) once each for on and off, (4) once |

## What Apple's official guide says

- "Value" parameters (ctls71c308ee, en-us and ja-jp): modes are Direct / Toggle / Scale / Relative / Rotate / X-OR. Rotate adds the incoming value to the current value and cycles between maximum and minimum. Multiply scales the incoming value. This version of the page has no description of feedback.
- "MIDI input" parameters (ctls71c30fbf): **the English and Japanese pages disagree.** For a message with neither Lo7 nor Hi7, the received value is 1 in the English page and 0 in the Japanese page (checked by Codex).
- General settings (lgcp1fe673ef): Pickup mode (the value does not change until the controller reaches the current value).

## Observation

- O1 (Value pane; scroll the pane down to see it): CC 20 (fixed `B0 14 40`) has mode **Rotate**, Multiply 1.00, resolution 128 steps (global resolution on). CC 21, 22 and 23 have mode **Scale**, Multiply 1.00. CC 21 and 22 show "Feedback: format None". The MCU V-Pot rows show mode Relative, format Sign Magnitude, feedback "Auto".
- O2 (Rotate check): with pan at its maximum (+63), the fixed message wrapped it to −64, and once more gave −63.
- O3 (same stimulus, on vs off): right after switching the selection from Synth to Ballad (pan 0), sending `[90, 100]` changed nothing with Pickup on (2 messages ignored), and gave +26, +36 with Pickup off.
- O4 (crossing only): with Pickup on and Ballad unsynchronized, sending 90 → 100 → 30 ignored 90 and 100, and **30 applied −34** (the controller crossed the target's value 64 going from 100 to 30 without ever equalling it).
- O5 (feedback): I set CC 21's feedback format to "single dot/line", changed pan over MCU and sent CC 21; 0 MIDI messages came back to `logicctl-cc` (waited 1.5 s, once). The format list has 11 choices (None, single dot/line, 4 bar types, Q/spread, text only, auto, trim, …). Set back to "None" afterwards.
- O6 (correction of an existing row): the "Note 26 → Play or Stop" row takes its input from a **real keyboard, "Impact LX88+"** (not connected; warning icon), message `90 18 7F 90 1A Lo7`, mode Toggle, feedback "Auto". My earlier note that its input was "All" was a mistake: I had read the display of the new row in learn mode.
- O7 (operating caution): on 12.4, ⌘K opened Musical Typing (Apple's text says ⌘K opens Controller Assignments). I closed it at once and pressed no keys. If Musical Typing stays open, letter keys play notes. From now on I open the window from the menu.
- Raw data (not in Git): `Research/raw/midi-learn/probe6.log`.

## Hypothesis

H1: a fixed-message row is in Rotate mode, adding 1 × Multiply (1.00) to the current value on each message (wrapping from maximum to minimum). Confidence: high (O1, O2, and EXP-CA-001 O1–O3). The incoming value of 1 matches the English page; it does not match the Japanese page's 0 (the reason the added amount is 1 could lie elsewhere; this is not settled).
H2: Pickup synchronizes when the controller's value equals the target's current value or crosses it between consecutive messages, and the message that synchronizes is applied. Confidence: high (EXP-CA-002 equality, O3 on/off comparison, O4 crossing).
H3: a generic assignment (an input-only port) has no output route for feedback, or "single dot/line" sends nothing. Confidence: low (one format, one trial). The MCU rows use "Auto" and do return feedback.
The earlier note (CLDE079) "input All" for the Note 26 row is wrong (O6).

## Cleanup and next experiments

- State restored: Synth selected, pan 0 and volume 0 on all tracks, Pickup on, CC 21 feedback None. The test rows (CC 20–23) remain.
- Next: (1) whether other feedback formats (auto, text only, …) produce output; (2) whether an output destination is tied by name to the input port; (3) MIDI assignment of a key command (the next experiment of EXP-KC-001).
